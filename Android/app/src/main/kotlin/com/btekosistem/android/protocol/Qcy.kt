package com.btekosistem.android.protocol

import java.util.UUID

// QCY (MeloBuds) protokolu. Android'e bagimli degil; Mac tarafindaki QcyProtocol.swift ile ayni kurallar.

/** Bayt dizisi yazma kolayligi: `bytesOf(0xFF, 0x03)`. */
fun bytesOf(vararg values: Int): ByteArray = ByteArray(values.size) { values[it].toByte() }

object QcyGatt {
    val SERVICE: UUID = UUID.fromString("0000A001-0000-1000-8000-00805f9b34fb")
    val COMMAND: UUID = UUID.fromString("00001001-0000-1000-8000-00805f9b34fb")
    val RESPONSE: UUID = UUID.fromString("00001002-0000-1000-8000-00805f9b34fb")
}

/** Yazma hedefi (ctl.write `kar`): 1001 komut (varsayilan, `kar` yok), 000D tus esleme, 000B eski EQ. */
enum class QcyChar(val kar: String?, val uuid: UUID) {
    COMMAND(null, QcyGatt.COMMAND),
    KEYMAP("000d", UUID.fromString("0000000D-0000-1000-8000-00805f9b34fb")),
    LEGACY_EQ("000b", UUID.fromString("0000000B-0000-1000-8000-00805f9b34fb"));

    companion object {
        /** null / "1001" -> COMMAND; bilinmeyen deger null. Buyuk-kucuk harf ayirt edilmez. */
        fun fromKar(kar: String?): QcyChar? = when (kar?.lowercase()) {
            null, "1001" -> COMMAND
            "000d" -> KEYMAP
            "000b" -> LEGACY_EQ
            else -> null
        }
    }
}

/** Reklamdaki pil + kontrol adresi. 0 = okuma yok (ornegin kutu yanda degil). */
data class QcyAdvertisement(
    val left: Int?,
    val right: Int?,
    val caseLevel: Int?,
    val leftCharging: Boolean,
    val rightCharging: Boolean,
    val caseCharging: Boolean,
    /** Kulakligin klasik Bluetooth adresi ("00:11:22:33:44:55"); eslesmis cihazla eslemek icin. */
    val controlAddress: String?,
) {
    companion object {
        const val COMPANY_ID = 0x521C

        /** Android'in verdigi uretici verisi: sirket kimligi ayrilmis, kalan baytlar. */
        fun parse(data: ByteArray): QcyAdvertisement? {
            if (data.size < 8) return null
            fun u(i: Int) = data[i].toInt() and 0xFF
            fun level(raw: Int): Int? = if (raw == 0) null else minOf(raw and 0x7F, 100)
            var address: String? = null
            if (data.size >= 17) {
                val b = intArrayOf(u(12), u(11), u(13), u(16), u(15), u(14))
                if (b.any { it != 0 }) address = b.joinToString(":") { "%02X".format(it) }
            }
            return QcyAdvertisement(
                left = level(u(5)), right = level(u(6)), caseLevel = level(u(7)),
                leftCharging = u(5) and 0x80 != 0, rightCharging = u(6) and 0x80 != 0,
                caseCharging = u(7) and 0x80 != 0, controlAddress = address,
            )
        }

        /** Ilk iki bayt sirket kimligi (kucuk uclu: 1C 52) olan ham paket (testler ve belge icin). */
        fun parseRaw(raw: ByteArray): QcyAdvertisement? {
            if (raw.size < 2) return null
            val id = (raw[0].toInt() and 0xFF) or ((raw[1].toInt() and 0xFF) shl 8)
            return if (id == COMPANY_ID) parse(raw.copyOfRange(2, raw.size)) else null
        }
    }
}

class QcyBlock(val opcode: Int, val parameters: ByteArray) {
    override fun equals(other: Any?) =
        other is QcyBlock && opcode == other.opcode && parameters.contentEquals(other.parameters)

    override fun hashCode() = 31 * opcode + parameters.contentHashCode()
    override fun toString() = "QcyBlock(0x%02X, %s)".format(opcode, parameters.toHex())
}

fun ByteArray.toHex(): String = joinToString(" ") { "%02X".format(it.toInt() and 0xFF) }

object QcyPacket {
    /** `FF <govde uzunlugu = param + 2> <opcode> <param uzunlugu> <parametreler>` */
    fun pack(opcode: Int, parameters: ByteArray): ByteArray =
        bytesOf(0xFF, parameters.size + 2, opcode, parameters.size) + parameters

    /** Okuma istegi: `FF 03 FE 01 <opcode>` */
    fun request(opcode: Int): ByteArray = pack(0xFE, bytesOf(opcode))

    /** Yanit paketindeki (opcode, parametre) bloklari. Bozuk paket bos liste doner. */
    fun parse(packet: ByteArray): List<QcyBlock> {
        fun u(i: Int) = packet[i].toInt() and 0xFF
        if (packet.size < 4 || u(0) != 0xFF || u(1) + 2 != packet.size) return emptyList()
        val out = ArrayList<QcyBlock>()
        var i = 2
        while (i < packet.size) {
            if (i + 2 > packet.size) return emptyList()
            val op = u(i)
            val len = u(i + 1)
            i += 2
            if (i + len > packet.size) return emptyList()
            out += QcyBlock(op, packet.copyOfRange(i, i + len))
            i += len
        }
        return out
    }
}

enum class ListeningMode { KAPALI, GURULTU_ENGELLEME, SEFFAF }

/** Gurultu engelleme sahnesi: 0x17 parametreleri `01 <sahne> <deger>`. */
enum class NoiseScene(val sceneByte: Int, val valueByte: Int) {
    UYARLANIR(0x05, 0x00),
    KAPALI_ALAN(0x01, 0x02),
    YOLCULUK(0x02, 0x02),
    GURULTULU(0x03, 0x02),
    RUZGAR_KARSITI(0x04, 0x00);

    val packet: ByteArray get() = QcyPacket.pack(QcyNoise.OPCODE, bytesOf(0x01, sceneByte, valueByte))

    companion object {
        /** Sahne ve deger tabloyla birebir eslesmezse null. */
        fun parse(p: ByteArray): NoiseScene? {
            if (p.size < 3 || p[0].toInt() != 0x01) return null
            return entries.firstOrNull {
                it.sceneByte == (p[1].toInt() and 0xFF) && it.valueByte == (p[2].toInt() and 0xFF)
            }
        }
    }
}

object QcyNoise {
    const val OPCODE = 0x17

    /** Gurultu engelleme icin varsayilan sahne Uyarlanir (`01 05 00`). */
    fun setMode(mode: ListeningMode): ByteArray = when (mode) {
        ListeningMode.KAPALI -> QcyPacket.pack(OPCODE, bytesOf(0x02, 0x00, 0x00))
        ListeningMode.GURULTU_ENGELLEME -> NoiseScene.UYARLANIR.packet
        ListeningMode.SEFFAF -> QcyPacket.pack(OPCODE, bytesOf(0x03, 0x01, 0x04))
    }

    const val TRANSPARENCY_MIN = 1
    const val TRANSPARENCY_MAX = 8
    const val TRANSPARENCY_DEFAULT = 4

    /** Seffaflik seviyesi (deneysel): `FF 05 17 03 03 01 <seviye>`; seviye 1..8'e sinirlanir. */
    fun transparencyLevel(level: Int): ByteArray =
        QcyPacket.pack(OPCODE, bytesOf(0x03, 0x01, level.coerceIn(TRANSPARENCY_MIN, TRANSPARENCY_MAX)))

    /** Seffaf mod yanitindaki (`03 01 <seviye>`) seviye; baska yanitta ya da kisa pakette null. */
    fun parseTransparency(p: ByteArray): Int? =
        if (p.size >= 3 && (p[0].toInt() and 0xFF) == 0x03) p[2].toInt() and 0xFF else null

    fun parseMode(p: ByteArray): ListeningMode? {
        if (p.isEmpty()) return null
        return when (p[0].toInt() and 0xFF) {
            0x01 -> ListeningMode.GURULTU_ENGELLEME
            0x02 -> ListeningMode.KAPALI
            0x03 -> ListeningMode.SEFFAF
            else -> null
        }
    }
}

/**
 * Kulak algilama (0x2C). Okuma: `<durum 00/01> <muzik> <anc> [ton]`.
 * Yazma: `<durum 01 acik / 02 kapali> <muzik> <anc> [ton 01/02]`.
 * Muzik / ANC / ton baytlarinin anlami belgeli degil: yalnizca cihazdan okunan deger aynen geri yazilir.
 */
data class QcyWearing(val enabled: Boolean, val music: Int, val anc: Int, val tone: Int?) {
    /** Yalnizca durum baytini degistirir; diger baytlar cihazdan okunan degerle aynen yazilir. */
    fun setEnabledPacket(enabled: Boolean): ByteArray {
        val p = mutableListOf(if (enabled) 0x01 else 0x02, music, anc)
        tone?.let { p += it }
        return QcyPacket.pack(OPCODE, p.toIntArray().let { bytesOf(*it) })
    }

    companion object {
        const val OPCODE = 0x2C

        fun parse(p: ByteArray): QcyWearing? {
            if (p.size != 3 && p.size != 4) return null
            fun u(i: Int) = p[i].toInt() and 0xFF
            val on = when (u(0)) {
                0x01 -> true
                0x00, 0x02 -> false
                else -> return null
            }
            return QcyWearing(on, u(1), u(2), if (p.size == 4) u(3) else null)
        }
    }
}

/** Cihazdan okunan durum; yalnizca okunanlar dolu. */
data class QcyDeviceState(
    val mode: ListeningMode? = null,
    val scene: NoiseScene? = null,
    val wearing: QcyWearing? = null,
    /** Seffaf moddayken cihazin bildirdigi seviye (deneysel). */
    val transparency: Int? = null,
    /** Oyun / dusuk gecikme modu (0x09). */
    val gameMode: Boolean? = null,
    /** Kulak algilama ac/kapa (0x06); `wearing` (0x2C eylemleri) ayri. */
    val earDetection: Boolean? = null,
    /** Secili EQ on ayari (0x22). */
    val eqPreset: QcyEqPreset? = null,
    /** Dokunmatik tus eslemesi (0x2B yaniti ya da 000D okumasi); okunmadiysa null. */
    val touchKeys: QcyTouchMap? = null,
) {
    /** Bir yanit blogunu isler; taninmayan opcode durumu degistirmez. */
    fun apply(block: QcyBlock): QcyDeviceState = when (block.opcode) {
        QcyNoise.OPCODE -> {
            val m = QcyNoise.parseMode(block.parameters)
            if (m == null) this
            else copy(mode = m, scene = if (m == ListeningMode.GURULTU_ENGELLEME) NoiseScene.parse(block.parameters) else null,
                transparency = if (m == ListeningMode.SEFFAF) QcyNoise.parseTransparency(block.parameters) else null)
        }
        QcyWearing.OPCODE -> QcyWearing.parse(block.parameters)?.let { copy(wearing = it) } ?: this
        QcyGameMode.OPCODE -> QcySwitch.parse(block.parameters)?.let { copy(gameMode = it) } ?: this
        QcyEarDetection.OPCODE -> QcySwitch.parse(block.parameters)?.let { copy(earDetection = it) } ?: this
        QcyEqPreset.OPCODE -> QcyEqPreset.parse(block.parameters)?.let { copy(eqPreset = it) } ?: this
        QcyTouchMap.OPCODE -> QcyTouchMap.parse(block.parameters)?.let { copy(touchKeys = it) } ?: this
        else -> this
    }

    fun apply(packet: ByteArray): QcyDeviceState = QcyPacket.parse(packet).fold(this) { s, b -> s.apply(b) }

    /** 000D ozelliginin ham okumasi; gecersizse durum degismez. */
    fun applyKeyMap(bytes: ByteArray): QcyDeviceState = QcyTouchMap.parse(bytes)?.let { copy(touchKeys = it) } ?: this
}

// Dogrulanmis ek komutlar (docs/arastirma-2.md bolum 4); Swift QcyProtocol.swift ile birebir.

/** `isVerified` yalnizca arastirmada "Dogrulandi" olanlar icin true; digerleri icin paket uretilmez. */
enum class QcyCapability(val isVerified: Boolean) {
    GAME_MODE(true), EAR_DETECTION(true), EQ_PRESET(true),
    EQ_CUSTOM(false), TRANSPARENCY_LEVELS(false), MULTIPOINT(false), TOUCH_KEYS(false);

    /** Paket bicimi resmi uygulama APK'sindan okundu (docs/qcy-protokol-cozum.md); cihazda denenmedi. */
    val isApkRead: Boolean get() = this == EQ_CUSTOM || this == TOUCH_KEYS

    companion object {
        val verified: List<QcyCapability> get() = entries.filter { it.isVerified }
    }
}

/** Cihaz profiline gore dogrulama (yalniz TWS profili; Swift `Device.isQcyVerified` karsiligi). */
fun QcyCapability.isVerifiedFor(tws: Boolean): Boolean = tws && isVerified

/** Arayuzde etkin mi: dogrulanmis ya da APK'dan okunmus (rozetle "cihazda denenmedi" gosterilir). */
fun QcyCapability.isEnabledFor(tws: Boolean): Boolean = tws && (isVerified || isApkRead)

/** `01` acik, `02` kapali (`00` okumada kapali). */
internal object QcySwitch {
    fun parse(p: ByteArray): Boolean? = when (p.firstOrNull()?.toInt()?.and(0xFF)) {
        0x01 -> true
        0x00, 0x02 -> false
        else -> null
    }

    fun packet(opcode: Int, on: Boolean): ByteArray = QcyPacket.pack(opcode, bytesOf(if (on) 0x01 else 0x02))
}

/** Oyun / dusuk gecikme modu: `FF 03 09 01 <01 acik / 02 kapali>`. */
object QcyGameMode {
    const val OPCODE = 0x09
    fun packet(enabled: Boolean): ByteArray = QcySwitch.packet(OPCODE, enabled)
    fun parse(p: ByteArray): Boolean? = QcySwitch.parse(p)
}

/** Kulak algilama ac/kapa: `FF 03 06 01 <01 acik / 02 kapali>`. */
object QcyEarDetection {
    const val OPCODE = 0x06
    fun packet(enabled: Boolean): ByteArray = QcySwitch.packet(OPCODE, enabled)
    fun parse(p: ByteArray): Boolean? = QcySwitch.parse(p)
}

/**
 * EQ hazir ayari (docs/qcy-protokol-cozum.md bolum 4.1, 6 ayar, indeks 0..5); Swift `QcyEqPreset` ile birebir.
 * Yazma: 0x22 paketi, eqIndex = indeks, master 0, bantlar tablodan.
 */
enum class QcyEqPreset(val index: Int, val nameTr: String, val bands: List<Int>) {
    DEFAULT(0, "Varsayılan", listOf(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
    POP(1, "Pop", listOf(-6, 5, -3, -2, 5, 4, -4, -3, 6, 4)),
    BASS(2, "Bas", listOf(8, 7, 5, 4, 0, 0, 0, 0, 0, 0)),
    ROCK(3, "Rock", listOf(7, 6, 2, 1, -3, -4, 2, 1, 4, 5)),
    SOFT(4, "Yumuşak", listOf(5, -5, -4, -4, 3, 2, 4, 4, 0, 0)),
    CLASSIC(5, "Klasik", listOf(6, 7, 1, 2, -1, 1, -4, -6, -7, -8));

    /** 0x22 paketi (77 bayt): eqIndex = indeks. */
    val packet: ByteArray get() = QcyCustomEq.packets(bands, eqIndex = index).first()

    /** Eski 000B yazma yuku (11 bayt): `[eqType] + 10 isaretli bayt`. */
    val legacyBytes: ByteArray get() = bytesOf(index, *bands.map { it and 0xFF }.toIntArray())

    companion object {
        const val OPCODE = 0x22
        val RANGE = 0..5
        val all: List<QcyEqPreset> get() = entries
        fun of(index: Int): QcyEqPreset? = entries.firstOrNull { it.index == index }

        /** Ilk bayt on ayar indeksi; 0..5 disi (ornegin 255 = ozel) ya da bos ise null. */
        fun parse(p: ByteArray): QcyEqPreset? = p.firstOrNull()?.let { of(it.toInt() and 0xFF) }
    }
}

// Dokunmatik kontroller ve ozel EQ (docs/qcy-protokol-cozum.md bolum 3 ve 4). [APK]; cihazda DOGRULANMADI.

enum class QcyTouchSide { LEFT, RIGHT }

/** Tek / cift / uc dokunus (eventID 1-6). Uzun basis dogrulanmadigi icin yok. */
enum class QcyTouchGesture { SINGLE, DOUBLE, TRIPLE }

/** Tus islev kodlari (bolum 3.2). */
enum class QcyKeyFunction(val code: Int) {
    NONE(0), PLAY_PAUSE(1), PREVIOUS(2), NEXT(3), ASSISTANT(4), VOLUME_UP(5), VOLUME_DOWN(6), GAME_MODE(7);

    companion object {
        fun of(code: Int): QcyKeyFunction? = entries.firstOrNull { it.code == code }
    }
}

/** `000D` yazma yolu: `[eventID, islevKodu]` ciftleri (ham, cerceve yok). */
object QcyTouchKeys {
    /** 1/2 tek, 3/4 cift, 5/6 uc; tek sayi sol, cift sayi sag. */
    fun eventId(side: QcyTouchSide, gesture: QcyTouchGesture): Int =
        gesture.ordinal * 2 + 1 + (if (side == QcyTouchSide.RIGHT) 1 else 0)

    /** Sol cift dokunus -> oynat/duraklat = `03 01`; sag uc dokunus -> asistan = `06 04`. */
    fun packet(side: QcyTouchSide, gesture: QcyTouchGesture, function: QcyKeyFunction): ByteArray =
        bytesOf(eventId(side, gesture), function.code)
}

/** Cihazdan okunan tus eslemesi (000D okumasi ya da 0x2B yaniti): `[eventID, kod, ...]`. */
class QcyTouchMap private constructor(val bytes: ByteArray) {
    /** Okunan islev; eventID yoksa ya da kod taninmiyorsa null. */
    fun function(side: QcyTouchSide, gesture: QcyTouchGesture): QcyKeyFunction? {
        val id = QcyTouchKeys.eventId(side, gesture)
        var i = 0
        while (i + 1 < bytes.size) {
            if ((bytes[i].toInt() and 0xFF) == id) return QcyKeyFunction.of(bytes[i + 1].toInt() and 0xFF)
            i += 2
        }
        return null
    }

    private fun indexOf(key: Int): Int? {
        var i = 0
        while (i + 1 < bytes.size) {
            if ((bytes[i].toInt() and 0xFF) == key) return i
            i += 2
        }
        return null
    }

    /** Yalnizca ilgili cift degisir (kalan baytlar aynen korunur); eventID yoksa null. Swift `QcyKeyMap.setting`. */
    fun setting(side: QcyTouchSide, gesture: QcyTouchGesture, function: QcyKeyFunction): QcyTouchMap? {
        val i = indexOf(QcyTouchKeys.eventId(side, gesture)) ?: return null
        val copy = bytes.copyOf()
        copy[i + 1] = function.code.toByte()
        return QcyTouchMap(copy)
    }

    override fun equals(other: Any?) = other is QcyTouchMap && bytes.contentEquals(other.bytes)
    override fun hashCode() = bytes.contentHashCode()
    override fun toString() = "QcyTouchMap(${bytes.toHex()})"

    companion object {
        /** 0x2B yanitinda ayni ciftler gelir. */
        const val OPCODE = 0x2B

        /** Bos ya da tek sayida bayt gecersiz. */
        fun parse(p: ByteArray): QcyTouchMap? = if (p.size >= 2 && p.size % 2 == 0) QcyTouchMap(p.copyOf()) else null
    }
}

/** Ozel EQ (bolum 4.2): 1001 uzerinden `FF N <cmd> <len> <eqIndex> <master_lo> <master_hi> {bant}...`. */
object QcyCustomEq {
    val FREQUENCIES = listOf(31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
    const val BAND_COUNT = 10
    const val MIN_DB = -8
    const val MAX_DB = 8
    /** 255 = ozel / son kullanilan. */
    const val CUSTOM_INDEX = 255
    /** Filtre turu: 255 = belirtilmemis. */
    const val FILTER_UNSPECIFIED = 255
    /** Q*100. Belgede Q degeri verilmiyor: 1.00 varsayim, cihazda dogrulanmadi. */
    const val DEFAULT_Q = 100

    private fun le(v: Int) = intArrayOf(v and 0xFF, (v shr 8) and 0xFF)

    /**
     * `opcode` 0x22 (7 bayt/bant, tur dahil) ya da 0x20 (6 bayt/bant). Kazanclar 10 deger, dB; -8..+8'e sinirlanir
     * (eksik deger 0). Kazanc int16 LE = dB*100, frekans uint16 LE, Q uint16 LE.
     */
    fun packets(
        gainsDb: List<Int>,
        opcode: Int = 0x22,
        eqIndex: Int = CUSTOM_INDEX,
        masterDb: Int = 0,
        q: Int = DEFAULT_Q,
    ): List<ByteArray> {
        require(opcode == 0x22 || opcode == 0x20) { "opcode 0x22 ya da 0x20 olmali" }
        val body = ArrayList<Int>()
        body += eqIndex and 0xFF
        body += le(masterDb * 100).toList()
        FREQUENCIES.forEachIndexed { i, f ->
            val g = (gainsDb.getOrElse(i) { 0 }.coerceIn(MIN_DB, MAX_DB)) * 100
            body += le(f).toList(); body += le(g).toList(); body += le(q).toList()
            if (opcode == 0x22) body += FILTER_UNSPECIFIED
        }
        return listOf(QcyPacket.pack(opcode, bytesOf(*body.toIntArray())))
    }
}
