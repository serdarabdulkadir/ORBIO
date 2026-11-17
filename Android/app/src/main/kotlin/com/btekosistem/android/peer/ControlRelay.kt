package com.btekosistem.android.peer

import android.util.Log
import com.btekosistem.android.protocol.QcyAdvertisement
import com.btekosistem.android.protocol.QcyChar
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update

/** Kulakligin BLE kontrol kanalina giden/gelen tek yonlu soyutlama: GATT ya da Mac uzerinden aktarim. */
/** KEYMAP: 000D ozelliginin dogrudan GATT okumasi (yalniz yerel). */
enum class IncomingKind { RESPONSE, ADVERT, KEYMAP }

class QcyIncoming(val kind: IncomingKind, val bytes: ByteArray)

interface QcyTransport {
    /** `target`: 1001 (varsayilan), 000D tus esleme, 000B eski EQ. */
    suspend fun write(bytes: ByteArray, target: QcyChar = QcyChar.COMMAND): Boolean
    /** 000D'yi dogrudan okuma istegi; yoksa false (cagiran 0x2B istegine duser). Deger `incoming`den KEYMAP olarak gelir. */
    suspend fun readKeyMap(): Boolean = false
    val incoming: Flow<QcyIncoming>
}

/** Hex yardimcisi: kucuk harf, ayirac yok. */
object QcyHex {
    fun encode(b: ByteArray): String = b.joinToString("") { "%02x".format(it.toInt() and 0xFF) }

    fun decode(s: String): ByteArray? {
        if (s.length % 2 != 0) return null
        val out = ByteArray(s.length / 2)
        for (i in out.indices) {
            val hi = Character.digit(s[2 * i], 16)
            val lo = Character.digit(s[2 * i + 1], 16)
            if (hi < 0 || lo < 0) return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }
}

/**
 * ctl.notify "reklam" bayti: sirket kimligi DAHIL ham uretici verisi (`1c 52` ile baslar).
 * Android'in getManufacturerSpecificData'si kimligi icermez; gonderirken eklenir, alirken atilir.
 */
object QcyAdvCodec {
    fun encode(ad: QcyAdvertisement): ByteArray {
        val d = ByteArray(17)
        fun lvl(v: Int?, charging: Boolean): Byte = (((v ?: 0) and 0x7F) or if (charging) 0x80 else 0).toByte()
        d[5] = lvl(ad.left, ad.leftCharging)
        d[6] = lvl(ad.right, ad.rightCharging)
        d[7] = lvl(ad.caseLevel, ad.caseCharging)
        val o = ad.controlAddress?.split(":")?.mapNotNull { it.toIntOrNull(16) }
        if (o != null && o.size == 6) {
            d[12] = o[0].toByte(); d[11] = o[1].toByte(); d[13] = o[2].toByte()
            d[16] = o[3].toByte(); d[15] = o[4].toByte(); d[14] = o[5].toByte()
        }
        // Mac cozucusu sirket kimligi onekini (1C 52, kucuk uclu) bekler.
        return byteArrayOf(0x1C, 0x52) + d
    }

    /** Bastaki `1c 52` atilarak ayristirilir; onek yoksa null. */
    fun decode(b: ByteArray): QcyAdvertisement? =
        QcyAdvertisement.parseRaw(b)
}

/** Aktarim secimi (saf mantik). */
object TransportPolicy {
    /** Mac o kulakligin kontrol kanalini tutuyorsa ve oturum aciksa GATT'e hic baglanilmaz. */
    fun shouldTryGatt(sessionOpen: Boolean, macOwns: Boolean): Boolean = !(sessionOpen && macOwns)

    /** GATT basarisiz oldu (ConnectFailed/147/zaman asimi): relay'e gecilebilir mi? */
    fun useRelayAfterGattFailure(sessionOpen: Boolean, macOwns: Boolean): Boolean = sessionOpen && macOwns
}

/** Mac'ten gelen ctl.write: hedef karakteristikle birlikte. */
class RelayedWrite(val address: String, val bytes: ByteArray, val target: QcyChar)

/**
 * ctl.owner / ctl.write / ctl.notify durumu: kim hangi kulakligin BLE kanalini tutuyor.
 * Ag katmanindan bagimsiz: mesajlari `sender` ile gonderir, gelenleri onMessage ile alir.
 */
class ControlRelay {
    private val _macOwned = MutableStateFlow<Set<String>>(emptySet())
    /** Mac'in sahip oldugunu bildirdigi kulakliklar (buyuk harf klasik adres). Oturum kopunca bosalir. */
    val macOwned: StateFlow<Set<String>> = _macOwned.asStateFlow()

    private val _sessionOpen = MutableStateFlow(false)
    val sessionOpen: StateFlow<Boolean> = _sessionOpen.asStateFlow()

    private val _notifies = MutableSharedFlow<Pair<String, QcyIncoming>>(extraBufferCapacity = 64)
    private val _writes = MutableSharedFlow<RelayedWrite>(extraBufferCapacity = 64)
    /** Mac'ten gelen ctl.write (telefon sahipse kulakliga yazilir). */
    val writesFromMac = _writes.asSharedFlow()

    @Volatile private var sender: ((PeerMessage) -> Unit)? = null
    private val phoneOwned = HashSet<String>()
    private val lastAdvert = HashMap<String, Pair<String, Long>>()

    fun macOwns(address: String): Boolean = address.uppercase() in _macOwned.value

    fun sessionStarted(send: (PeerMessage) -> Unit) {
        sender = send
        _sessionOpen.value = true
        Log.i(TAG, "relay: oturum acik")
        val mine = synchronized(phoneOwned) { phoneOwned.toList() }
        for (a in mine) send(PeerMessage.CtlOwner(a, true))
    }

    fun sessionEnded() {
        sender = null
        _sessionOpen.value = false
        _macOwned.value = emptySet()
        synchronized(lastAdvert) { lastAdvert.clear() }
        Log.i(TAG, "relay: oturum kapandi")
    }

    /** Telefon GATT'i tutuyor / biraktı: durum degisince Mac'e bildir. */
    fun setPhoneOwns(address: String, owns: Boolean) {
        val a = address.uppercase()
        val changed = synchronized(phoneOwned) { if (owns) phoneOwned.add(a) else phoneOwned.remove(a) }
        if (changed) {
            Log.i(TAG, "relay: ctl.owner gonder $a sahip=$owns")
            sender?.invoke(PeerMessage.CtlOwner(a, owns))
        }
    }

    /** Mac'in ctl.owner istegine kosulsuz yanit (Mac 20/30 sn bekler): degisiklik olmasa da gonderilir. */
    fun ackOwner(address: String, owns: Boolean) {
        sender?.invoke(PeerMessage.CtlOwner(address.uppercase(), owns))
    }

    fun phoneOwns(address: String): Boolean = synchronized(phoneOwned) { address.uppercase() in phoneOwned }

    /** Sahip olmayan taraf: komutu Mac'e yolla. Oturum yoksa false. */
    fun sendWrite(address: String, bytes: ByteArray, target: QcyChar = QcyChar.COMMAND): Boolean {
        val s = sender ?: return false
        s(PeerMessage.CtlWrite(address.uppercase(), QcyHex.encode(bytes), target.kar))
        return true
    }

    /** Sahip taraf: yanit (her zaman) ya da reklam (ayni veri 5 sn icinde tekrarlanmaz) gonder. */
    fun sendNotify(address: String, kind: IncomingKind, bytes: ByteArray, nowMs: Long = System.currentTimeMillis()) {
        val s = sender ?: return
        val a = address.uppercase()
        val hex = QcyHex.encode(bytes)
        if (kind == IncomingKind.ADVERT) {
            synchronized(lastAdvert) {
                val last = lastAdvert[a]
                if (last != null && last.first == hex && nowMs - last.second < ADVERT_REPEAT_MS) return
                lastAdvert[a] = hex to nowMs
            }
        }
        s(PeerMessage.CtlNotify(a, if (kind == IncomingKind.RESPONSE) "yanit" else "reklam", hex))
    }

    fun incomingFor(address: String): Flow<QcyIncoming> {
        val a = address.uppercase()
        return _notifies.filter { it.first == a }.map { it.second }
    }

    /** Mac'ten gelen ctl.* mesajlari. Bozuk hex olumcul degil, yok sayilir. */
    fun onMessage(m: PeerMessage) {
        when (m) {
            is PeerMessage.CtlOwner -> {
                val a = m.cihazAdresi.uppercase()
                Log.i(TAG, "relay: Mac ctl.owner $a sahip=${m.sahip}")
                _macOwned.update { if (m.sahip) it + a else it - a }
            }
            is PeerMessage.CtlWrite -> {
                val b = QcyHex.decode(m.bayt) ?: return
                val target = QcyChar.fromKar(m.kar) ?: run { Log.i(TAG, "relay: bilinmeyen kar atildi"); return }
                _writes.tryEmit(RelayedWrite(m.cihazAdresi.uppercase(), b, target))
            }
            is PeerMessage.CtlNotify -> {
                val b = QcyHex.decode(m.bayt) ?: return
                val kind = when (m.tur) {
                    "yanit" -> IncomingKind.RESPONSE
                    "reklam" -> IncomingKind.ADVERT
                    else -> return
                }
                _notifies.tryEmit(m.cihazAdresi.uppercase() to QcyIncoming(kind, b))
            }
            else -> {}
        }
    }

    /** Sahip olmayan taraf icin aktarim: yazmalar Mac'e, gelenler ctl.notify'dan. */
    fun transportFor(address: String): QcyTransport = object : QcyTransport {
        override suspend fun write(bytes: ByteArray, target: QcyChar): Boolean = sendWrite(address, bytes, target)
        override val incoming: Flow<QcyIncoming> = incomingFor(address)
    }

    private companion object {
        const val TAG = "BTrack"
        const val ADVERT_REPEAT_MS = 5_000L
    }
}
