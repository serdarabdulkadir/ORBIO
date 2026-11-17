package com.btekosistem.android.peer

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.CallLog.Calls
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.Settings
import android.util.Log
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.btekosistem.android.R
import com.btekosistem.android.ble.BtEnvironment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class PhoneInfo(val ad: String, val model: String, val pil: Int, val sarj: Boolean, val sinyal: Int, val ag: String)

/** durum: bosta / caliyor / acik / araniyor. yon: gelen / giden. */
data class CallInfo(
    val durum: String = "bosta",
    val yon: String? = null,
    val numara: String? = null,
    val kisiAdi: String? = null,
    val startedAt: Long? = null,
)

data class Grants(val readState: Boolean, val answer: Boolean, val call: Boolean, val callLog: Boolean, val contacts: Boolean)

enum class ActionResult { OK, NO_PERMISSION, UNSUPPORTED, INVALID, FAILED }

/** Telefonun durumu, arama durumu ve eylemleri: hem arayuz hem Mac istekleri bunu kullanir. */
@SuppressLint("MissingPermission")
class PhoneController private constructor(context: Context) {
    private val app = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val main = Handler(Looper.getMainLooper())

    private val _info = MutableStateFlow(readInfo())
    val info: StateFlow<PhoneInfo> = _info.asStateFlow()
    private val _call = MutableStateFlow(CallInfo())
    val call: StateFlow<CallInfo> = _call.asStateFlow()
    private val _grants = MutableStateFlow(readGrants())
    val grants: StateFlow<Grants> = _grants.asStateFlow()

    private var started = false
    private var monitorStarted = false
    private var pendingNumber: String? = null
    private var pendingDial: String? = null
    @Volatile private var dialedByApp = false
    private val _endBlocked = MutableStateFlow(false)
    /** endCall false dondu ve arama bu uygulamadan baslatilmisti: telefon uygulamadan sonlandirmaya izin vermiyor. */
    val endBlocked: StateFlow<Boolean> = _endBlocked.asStateFlow()
    private var keepModern: Any? = null
    private var keepLegacy: Any? = null

    fun refreshGrants() { _grants.value = readGrants() }

    private fun readGrants() = Grants(
        readState = has(Manifest.permission.READ_PHONE_STATE),
        answer = has(Manifest.permission.ANSWER_PHONE_CALLS),
        call = has(Manifest.permission.CALL_PHONE),
        callLog = has(Manifest.permission.READ_CALL_LOG),
        contacts = has(Manifest.permission.READ_CONTACTS),
    )

    private fun has(p: String) = BtEnvironment.isGranted(app, p)

    @Synchronized
    fun ensureStarted() {
        refreshGrants()
        if (!started) {
            started = true
            Notifs.ensureChannels(app)
            ContextCompat.registerReceiver(
                app,
                object : BroadcastReceiver() { override fun onReceive(c: Context, i: Intent) { refreshInfo() } },
                IntentFilter(Intent.ACTION_BATTERY_CHANGED), ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            try {
                (app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).registerDefaultNetworkCallback(
                    object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) { refreshInfo() }
                        override fun onLost(network: Network) { refreshInfo() }
                        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) { refreshInfo() }
                    },
                )
            } catch (_: Exception) { }
            scope.launch {
                while (true) { delay(15_000); refreshInfo() }
            }
            scope.launch {
                var last: CallInfo? = null
                _call.collect { c ->
                    if (c != last) { last = c; syncNotification(c) }
                }
            }
        }
        startCallMonitorIfPossible()
    }

    // --- Telefon durumu ---

    fun refreshInfo() { _info.value = readInfo() }

    private fun readInfo(): PhoneInfo {
        val sticky = app.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = sticky?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = sticky?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val pct = if (level >= 0 && scale > 0) (level * 100 / scale).coerceIn(0, 100) else 0
        val status = sticky?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL || plugged != 0

        var signal = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                signal = (app.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager).signalStrength?.level ?: 0
            } catch (_: Exception) { }
        }

        var net = "yok"
        try {
            val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
            if (caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                net = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobil"
                    else -> "yok"
                }
            }
        } catch (_: Exception) { }

        val custom: String? = try {
            Settings.Global.getString(app.contentResolver, "device_name")
        } catch (_: Exception) {
            null
        }
        val name = custom ?: Build.MODEL
        return PhoneInfo(name, Build.MODEL, pct, charging, signal.coerceIn(0, 4), net)
    }

    // --- Arama durumu ---

    @Suppress("DEPRECATION")
    @Synchronized
    private fun startCallMonitorIfPossible() {
        if (monitorStarted || !_grants.value.readState) return
        monitorStarted = true
        val tm = app.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) registerModern(tm) else registerLegacy(tm)
            ContextCompat.registerReceiver(
                app,
                object : BroadcastReceiver() {
                    override fun onReceive(c: Context, i: Intent) {
                        val n = i.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                        if (!n.isNullOrBlank()) onNumber(n)
                    }
                },
                IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED), ContextCompat.RECEIVER_EXPORTED,
            )
        } catch (e: Exception) {
            monitorStarted = false
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun registerModern(tm: TelephonyManager) {
        val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
            override fun onCallStateChanged(state: Int) { handleState(state) }
        }
        keepModern = cb
        tm.registerTelephonyCallback(ContextCompat.getMainExecutor(app), cb)
    }

    @Suppress("DEPRECATION")
    private fun registerLegacy(tm: TelephonyManager) {
        main.post {
            val l = object : PhoneStateListener() {
                @Deprecated("Deprecated in Java")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    if (!phoneNumber.isNullOrBlank()) pendingNumber = phoneNumber
                    handleState(state)
                }
            }
            keepLegacy = l
            tm.listen(l, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    private fun onNumber(n: String) {
        pendingNumber = n
        scope.launch {
            val name = lookupName(n)
            _call.update { if (it.durum != "bosta" && it.yon == "gelen") it.copy(numara = n, kisiAdi = name ?: it.kisiAdi) else it }
        }
    }

    private fun handleState(state: Int) {
        val prev = _call.value
        val now = SystemClock.elapsedRealtime()
        val next = when (state) {
            TelephonyManager.CALL_STATE_RINGING ->
                CallInfo("caliyor", "gelen", pendingNumber, pendingNumber?.let { lookupName(it) })
            TelephonyManager.CALL_STATE_OFFHOOK -> when (prev.durum) {
                "caliyor" -> prev.copy(durum = "acik", startedAt = now)
                "acik", "araniyor" -> prev
                else -> CallInfo("araniyor", "giden", pendingDial, pendingDial?.let { lookupName(it) }, now)
            }
            else -> {
                pendingNumber = null; pendingDial = null; dialedByApp = false
                CallInfo()
            }
        }
        Log.d(TAG, "arama durumu: ${prev.durum} -> ${next.durum}")
        _call.value = next
    }

    private fun lookupName(number: String): String? {
        if (!_grants.value.contacts) return null
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            app.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (_: Exception) { null }
    }

    private fun syncNotification(c: CallInfo) {
        val nm = NotificationManagerCompat.from(app)
        if (c.durum != "caliyor") { nm.cancel(NOTIF_CALL); return }
        val who = c.kisiAdi ?: c.numara ?: app.getString(R.string.call_unknown)
        val n = NotificationCompat.Builder(app, Notifs.CH_CALL)
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setContentTitle(who)
            .setContentText(app.getString(R.string.call_incoming))
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setContentIntent(Notifs.openApp(app))
            .build()
        try { nm.notify(NOTIF_CALL, n) } catch (_: SecurityException) { }
    }

    // --- Eylemler ---

    private fun telecom() = app.getSystemService(Context.TELECOM_SERVICE) as TelecomManager

    fun answer(): ActionResult {
        if (!has(Manifest.permission.ANSWER_PHONE_CALLS)) return ActionResult.NO_PERMISSION
        return try {
            telecom().acceptRingingCall()
            Log.d(TAG, "acceptRingingCall cagrildi (durum=${_call.value.durum})")
            ActionResult.OK
        } catch (e: Exception) {
            Log.d(TAG, "acceptRingingCall hata: $e")
            ActionResult.FAILED
        }
    }

    /** Calan aramayi reddeder ya da surenini bitirir (TelecomManager.endCall, API 28+). */
    fun endCall(): ActionResult {
        if (!has(Manifest.permission.ANSWER_PHONE_CALLS)) { Log.d(TAG, "endCall: ANSWER_PHONE_CALLS izni yok"); return ActionResult.NO_PERMISSION }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return ActionResult.UNSUPPORTED
        return try {
            val ok = telecom().endCall()
            Log.d(TAG, "endCall=$ok (durum=${_call.value.durum}, uygulamadanAranan=$dialedByApp)")
            when {
                ok -> { _endBlocked.value = false; ActionResult.OK }
                dialedByApp -> { _endBlocked.value = true; ActionResult.UNSUPPORTED }
                else -> ActionResult.FAILED
            }
        } catch (e: Exception) {
            Log.d(TAG, "endCall hata: $e")
            ActionResult.FAILED
        }
    }

    fun dial(raw: String): ActionResult {
        val number = normalizeDialNumber(raw) ?: return ActionResult.INVALID
        if (!has(Manifest.permission.CALL_PHONE)) return ActionResult.NO_PERMISSION
        return try {
            pendingDial = number
            dialedByApp = true
            telecom().placeCall(Uri.fromParts("tel", number, null), Bundle())
            Log.d(TAG, "placeCall cagrildi")
            ActionResult.OK
        } catch (e: Exception) {
            Log.d(TAG, "placeCall hata: $e")
            dialedByApp = false
            ActionResult.FAILED
        }
    }

    suspend fun searchContacts(query: String): List<PeerContact> = withContext(Dispatchers.IO) {
        if (!has(Manifest.permission.READ_CONTACTS)) return@withContext emptyList()
        val q = query.trim().replace("%", "").replace("_", "")
        if (q.isEmpty()) return@withContext emptyList()
        val out = LinkedHashMap<String, LinkedHashSet<String>>()
        try {
            app.contentResolver.query(
                Phone.CONTENT_URI, arrayOf(Phone.DISPLAY_NAME, Phone.NUMBER),
                "${Phone.DISPLAY_NAME} LIKE ? OR ${Phone.NUMBER} LIKE ?", arrayOf("%$q%", "%$q%"),
                "${Phone.DISPLAY_NAME} COLLATE NOCASE ASC",
            )?.use { c ->
                var rows = 0
                while (c.moveToNext() && rows < 80 && out.size <= 20) {
                    rows++
                    val name = c.getString(0) ?: continue
                    val num = c.getString(1) ?: continue
                    out.getOrPut(name) { LinkedHashSet() }.add(num)
                }
            }
        } catch (_: Exception) { }
        out.entries.take(20).map { PeerContact(it.key, it.value.toList()) }
    }

    suspend fun recentCalls(count: Int): List<PeerCallLogEntry> = withContext(Dispatchers.IO) {
        if (!has(Manifest.permission.READ_CALL_LOG)) return@withContext emptyList()
        val out = ArrayList<PeerCallLogEntry>()
        try {
            app.contentResolver.query(
                Calls.CONTENT_URI, arrayOf(Calls.NUMBER, Calls.CACHED_NAME, Calls.TYPE, Calls.DATE, Calls.DURATION), null, null, "${Calls.DATE} DESC",
            )?.use { c ->
                while (c.moveToNext() && out.size < count) {
                    val yon = when (c.getInt(2)) {
                        Calls.INCOMING_TYPE, Calls.ANSWERED_EXTERNALLY_TYPE -> "gelen"
                        Calls.OUTGOING_TYPE -> "giden"
                        else -> "cevapsiz"
                    }
                    out += PeerCallLogEntry(c.getString(0).orEmpty(), c.getString(1), yon, c.getLong(3) / 1000, c.getInt(4))
                }
            }
        } catch (_: Exception) { }
        out
    }

    companion object {
        private const val NOTIF_CALL = 2001
        private const val TAG = "BTPeer"

        @Volatile private var instance: PhoneController? = null

        fun get(context: Context): PhoneController =
            instance ?: synchronized(this) { instance ?: PhoneController(context).also { instance = it } }
    }
}
