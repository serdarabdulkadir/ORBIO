package com.btekosistem.android.peer

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.CallLog.Calls
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.GroupMembership
import android.provider.ContactsContract.CommonDataKinds.Phone
import com.btekosistem.android.ble.BtEnvironment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.Base64

/** Sayfalama ve alan kurallari (saf mantik; birim testi var). */
object ContactPaging {
    const val DEFAULT_CONTACTS = 40
    const val MAX_CONTACTS = 100
    const val DEFAULT_LOG = 100
    const val MAX_LOG = 200
    /** Tek sayfanin yaklasik JSON ust siniri (cerceve siniri 1 MiB; guvenli pay). */
    const val PAGE_BUDGET_CHARS = 450_000
    const val PHOTO_PX = 96
    const val PHOTO_MAX_BYTES = 8 * 1024

    fun clampContacts(adet: Int?): Int = (adet ?: DEFAULT_CONTACTS).coerceIn(1, MAX_CONTACTS)
    fun clampLog(adet: Int?): Int = (adet ?: DEFAULT_LOG).coerceIn(1, MAX_LOG)

    /** Sayfa son mu: bu sayfadan sonra kalan kayit yok. */
    fun isLast(offset: Int, returned: Int, total: Int): Boolean = returned == 0 || offset + returned >= total

    fun numberType(type: Int): String = when (type) {
        Phone.TYPE_MOBILE, Phone.TYPE_WORK_MOBILE -> "cep"
        Phone.TYPE_HOME, Phone.TYPE_FAX_HOME -> "ev"
        Phone.TYPE_WORK, Phone.TYPE_FAX_WORK -> "is"
        else -> "diger"
    }

    fun callDirection(type: Int): String = when (type) {
        Calls.INCOMING_TYPE, Calls.ANSWERED_EXTERNALLY_TYPE -> "gelen"
        Calls.OUTGOING_TYPE -> "giden"
        else -> "cevapsiz"
    }

    /** Sayfa butcesine sigana kadar kayit alir (en az bir). Boyut olcusu: foto + ad + numaralar. */
    fun <T> takeWithinBudget(items: List<T>, weight: (T) -> Int, budget: Int = PAGE_BUDGET_CHARS): List<T> {
        var used = 0
        val out = ArrayList<T>()
        for (i in items) {
            val w = weight(i)
            if (out.isNotEmpty() && used + w > budget) break
            used += w
            out += i
        }
        return out
    }
}

data class ContactsPageData(val toplam: Int, val kisiler: List<PeerContactRecord>)
data class CallLogPageData(val toplam: Int, val kayitlar: List<PeerCallLogEntry>)

/**
 * Rehber ve arama kaydi okuyucusu. Yalnizca Mac istegi uzerine okur; hicbir yere kaydetmez.
 * Izin kontrolu cagiranin isidir (PeerManager); burada yine de runtime izni yoksa bos doner.
 */
@SuppressLint("MissingPermission")
class ContactsReader(context: Context) {
    private val app = context.applicationContext
    private val cr get() = app.contentResolver

    private fun has(p: String) = BtEnvironment.isGranted(app, p)

    // Saglayicilar QUERY_ARG_OFFSET/LIMIT'i yok sayabilir; sayfalama imlecte elle yapilir (skipTo + limit).
    private fun pagedArgs(sort: String): Bundle = Bundle().apply {
        putString(android.content.ContentResolver.QUERY_ARG_SQL_SORT_ORDER, sort)
    }

    /** Imleci `offset` satirindan once konumlar; ofset satir sayisini asarsa false (okunacak satir yok). */
    private fun android.database.Cursor.skipTo(offset: Int): Boolean =
        offset < count && moveToPosition(offset - 1)

    suspend fun contactsPage(offset: Int, adet: Int?): ContactsPageData = withContext(Dispatchers.IO) {
        if (!has(Manifest.permission.READ_CONTACTS)) return@withContext ContactsPageData(0, emptyList())
        val limit = ContactPaging.clampContacts(adet)
        val off = offset.coerceAtLeast(0)
        val where = "${ContactsContract.Contacts.HAS_PHONE_NUMBER}=1"
        val total = try {
            cr.query(ContactsContract.Contacts.CONTENT_URI, arrayOf(ContactsContract.Contacts._ID), where, null, null)?.use { it.count } ?: 0
        } catch (_: Exception) { 0 }

        class Base(val id: String, val name: String, val starred: Boolean, val thumb: String?)
        val bases = ArrayList<Base>()
        try {
            val args = pagedArgs("${ContactsContract.Contacts.SORT_KEY_PRIMARY} COLLATE LOCALIZED ASC, ${ContactsContract.Contacts._ID} ASC").apply {
                putString(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION, where)
            }
            cr.query(
                ContactsContract.Contacts.CONTENT_URI,
                arrayOf(
                    ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
                    ContactsContract.Contacts.STARRED, ContactsContract.Contacts.PHOTO_THUMBNAIL_URI,
                ),
                args, null,
            )?.use { c ->
                var read = 0
                if (c.skipTo(off)) while (read < limit && c.moveToNext()) {
                    read++
                    // Satir atlanmaz: Mac'in sayaci (ofset) telefondaki satir sirasiyla ayni kalmali.
                    val name = c.getString(1)?.takeIf { it.isNotBlank() } ?: "(Adsız)"
                    bases += Base(c.getString(0), name, c.getInt(2) == 1, c.getString(3))
                }
            }
        } catch (_: Exception) { }
        if (bases.isEmpty()) return@withContext ContactsPageData(total, emptyList())

        val ids = bases.map { it.id }
        val numbers = HashMap<String, MutableList<PeerContactNumber>>()
        val groupRows = HashMap<String, MutableList<String>>()
        val marks = ids.joinToString(",") { "?" }
        try {
            cr.query(
                Phone.CONTENT_URI, arrayOf(Phone.CONTACT_ID, Phone.NUMBER, Phone.TYPE),
                "${Phone.CONTACT_ID} IN ($marks)", ids.toTypedArray(),
                "${Phone.IS_PRIMARY} DESC, ${Phone._ID} ASC",
            )?.use { c ->
                while (c.moveToNext()) {
                    val no = c.getString(1)?.trim()?.takeIf { it.isNotEmpty() } ?: continue
                    val list = numbers.getOrPut(c.getString(0)) { ArrayList() }
                    if (list.none { it.no == no }) list += PeerContactNumber(no, ContactPaging.numberType(c.getInt(2)))
                }
            }
        } catch (_: Exception) { }
        try {
            cr.query(
                ContactsContract.Data.CONTENT_URI, arrayOf(ContactsContract.Data.CONTACT_ID, GroupMembership.GROUP_ROW_ID),
                "${ContactsContract.Data.MIMETYPE}=? AND ${ContactsContract.Data.CONTACT_ID} IN ($marks)",
                arrayOf(GroupMembership.CONTENT_ITEM_TYPE) + ids.toTypedArray(), null,
            )?.use { c ->
                while (c.moveToNext()) groupRows.getOrPut(c.getString(0)) { ArrayList() } += c.getString(1)
            }
        } catch (_: Exception) { }
        val titles = if (groupRows.isEmpty()) emptyMap() else groupTitles()

        val records = bases.map { b ->
            PeerContactRecord(
                kid = b.id, ad = b.name, numaralar = numbers[b.id] ?: emptyList<PeerContactNumber>(), favori = b.starred,
                gruplar = (groupRows[b.id] ?: emptyList<String>()).mapNotNull { titles[it] }.distinct(),
                foto = b.thumb?.let { photoBase64(it) },
            )
        }
        val fit = ContactPaging.takeWithinBudget(records, { r -> 160 + r.ad.length * 2 + r.numaralar.sumOf { it.no.length + 24 } + (r.foto?.length ?: 0) + r.gruplar.sumOf { it.length + 4 } })
        ContactsPageData(total, fit)
    }

    private fun groupTitles(): Map<String, String> {
        val out = HashMap<String, String>()
        try {
            cr.query(
                ContactsContract.Groups.CONTENT_URI, arrayOf(ContactsContract.Groups._ID, ContactsContract.Groups.TITLE),
                "${ContactsContract.Groups.DELETED}=0", null, null,
            )?.use { c ->
                while (c.moveToNext()) {
                    val t = c.getString(1)?.trim()
                    if (!t.isNullOrEmpty()) out[c.getString(0)] = t
                }
            }
        } catch (_: Exception) { }
        return out
    }

    /** 96 px JPEG kucuk resim (en cok 8 KB); okunamazsa ya da buyukse null. */
    private fun photoBase64(uri: String): String? = try {
        cr.openInputStream(Uri.parse(uri))?.use { ins ->
            val bmp = BitmapFactory.decodeStream(ins) ?: return null
            val scale = ContactPaging.PHOTO_PX.toFloat() / maxOf(bmp.width, bmp.height)
            val small = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt().coerceAtLeast(1), (bmp.height * scale).toInt().coerceAtLeast(1), true) else bmp
            val out = ByteArrayOutputStream()
            small.compress(Bitmap.CompressFormat.JPEG, 70, out)
            val bytes = out.toByteArray()
            if (bytes.size > ContactPaging.PHOTO_MAX_BYTES) null else Base64.getEncoder().encodeToString(bytes)
        }
    } catch (_: Exception) { null }

    suspend fun callLogPage(offset: Int, adet: Int?): CallLogPageData = withContext(Dispatchers.IO) {
        if (!has(Manifest.permission.READ_CALL_LOG)) return@withContext CallLogPageData(0, emptyList())
        val limit = ContactPaging.clampLog(adet)
        val off = offset.coerceAtLeast(0)
        val total = try {
            cr.query(Calls.CONTENT_URI, arrayOf(Calls._ID), null, null, null)?.use { it.count } ?: 0
        } catch (_: Exception) { 0 }
        val out = ArrayList<PeerCallLogEntry>()
        try {
            cr.query(
                Calls.CONTENT_URI, arrayOf(Calls.NUMBER, Calls.CACHED_NAME, Calls.TYPE, Calls.DATE, Calls.DURATION),
                pagedArgs("${Calls.DATE} DESC, ${Calls._ID} DESC"), null,
            )?.use { c ->
                var read = 0
                if (c.skipTo(off)) while (read < limit && c.moveToNext()) {
                    read++
                    out += PeerCallLogEntry(
                        c.getString(0).orEmpty(), c.getString(1)?.takeIf { it.isNotBlank() },
                        ContactPaging.callDirection(c.getInt(2)), c.getLong(3) / 1000, c.getInt(4),
                    )
                }
            }
        } catch (_: Exception) { }
        CallLogPageData(total, out)
    }

    /** Rehber ya da arama kaydi degisince (2 sn sakinlesince) tek sinyal. */
    @OptIn(FlowPreview::class)
    fun changes(uri: Uri): Flow<Unit> = callbackFlow {
        val obs = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { trySend(Unit) }
        }
        try { cr.registerContentObserver(uri, true, obs) } catch (_: Exception) { }
        awaitClose { try { cr.unregisterContentObserver(obs) } catch (_: Exception) { } }
    }.debounce(2_000)
}
