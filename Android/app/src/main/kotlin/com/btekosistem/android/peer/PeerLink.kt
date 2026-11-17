package com.btekosistem.android.peer

import java.io.InputStream
import java.io.OutputStream
import java.net.Socket

/** Telefon-Mac kanalinin yolu: Wi-Fi (TCP) ya da Bluetooth (RFCOMM yedek). */
enum class PeerPath { WIFI, BLUETOOTH }

/** Oturum kodunun gordugu tek sey: bayt akisi. TCP ve RFCOMM ayni PeerSession / PeerFraming ile calisir. */
interface PeerLink {
    val path: PeerPath
    val input: InputStream
    val output: OutputStream
    fun close()
}

class SocketLink(private val socket: Socket) : PeerLink {
    override val path = PeerPath.WIFI
    override val input: InputStream get() = socket.getInputStream()
    override val output: OutputStream get() = socket.getOutputStream()
    override fun close() { try { socket.close() } catch (_: Exception) { } }
}

/** Yol secimi (saf mantik): oncelik Wi-Fi'dir; Bluetooth yalniz eslesmis Mac icin, tek oturum, Wi-Fi bosken. */
object PeerPathPolicy {
    /** Gelen RFCOMM baglantisi kabul edilir mi? Wi-Fi oturumu (kurulan ya da kuruluyor) varsa reddedilir. */
    fun acceptBluetooth(wifiBusy: Boolean, bluetoothActive: Boolean, paired: Boolean, pairingOpen: Boolean = false): Boolean =
        (paired || pairingOpen) && !wifiBusy && !bluetoothActive

    /** Ilk eslesme penceresi: yalniz kullanicinin sectigi Bluetooth cihazindan gelen baglanti kabul edilir. */
    fun pairingAddressMatches(expected: String?, remote: String?): Boolean =
        expected != null && remote != null && expected.equals(remote, ignoreCase = true)

    const val BT_ID_PREFIX = "bt:"

    /** Mac kimligi henuz bilinmiyorken gecici kimlik; el sikisma sonrasi Hello.cihazId ile degistirilir. */
    fun isProvisionalId(id: String): Boolean = id.startsWith(BT_ID_PREFIX)

    /** Yalniz Bluetooth acikken Wi-Fi'de Mac bulundu: Wi-Fi'ye gec, Bluetooth'u kapat. */
    fun switchToWifi(bluetoothActive: Boolean, macFoundOnWifi: Boolean): Boolean = bluetoothActive && macFoundOnWifi

    /** Dosya aktarimi (TransferEngine) yalniz Wi-Fi'de acik. */
    fun fileTransferAllowed(path: PeerPath?): Boolean = path != PeerPath.BLUETOOTH

    /** Dosya aktarimi tipli mesaj mi (BT'de kapali olanlar). */
    fun isTransferType(type: String): Boolean =
        type.startsWith("transfer.") || type.startsWith("file.") || type.startsWith("dosya.")
}
