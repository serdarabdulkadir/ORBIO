package com.btekosistem.android.protocol

// AirPods / Beats "Proximity Pairing" BLE reklam cozucu (Continuity tipi 0x07).
// Android'e bagimli degil; Mac tarafindaki ProximityPairing.swift ile ayni bayt yorumu (sol/sag cevirme dahil).
// Son 16 bayt sifreli: cozulmez, atlanir. Kulakta / kutu bitleri deneysel (kendi cihazda dogrulanacak).

/** Pil seviyesi: nibble 0..10 -> x10 yuzde, digerleri (0xF) bilinmiyor (null). */
internal fun batteryFromNibble(nibble: Int): Int? = if (nibble in 0..10) nibble * 10 else null

data class ProximityPairingInfo(
    val model: Int,
    val modelName: String?,
    val rawStatus: Int,
    val left: Int?,
    val right: Int?,
    val caseBattery: Int?,
    val leftCharging: Boolean,
    val rightCharging: Boolean,
    val caseCharging: Boolean,
    val leftInEar: Boolean,
    val rightInEar: Boolean,
    val lidCounter: Int,
    val color: Int,
    /** Tek parca cihazlarin (Max, Solo, Studio...) tek pili (alt nibble). */
    val headsetBattery: Int?,
    val headsetCharging: Boolean,
    val headsetWorn: Boolean,
    val onePodInCase: Boolean,
    val bothPodsInCase: Boolean,
) {
    val modelInfo: AppleModel? get() = AppleModelCatalog.model(model)
    /** Kapak durumu: iki kulaklik de kutudaysa kutu kapali sayilir (deneysel). */
    val lidOpen: Boolean get() = !bothPodsInCase
}

object ProximityPairingParser {
    const val APPLE_COMPANY_ID = 0x004C
    private const val MESSAGE_TYPE = 0x07

    /** `data`: sirket kimligi DAHIL (ilk 2 bayt little-endian), Swift `parse(manufacturerData:)` ile ayni. */
    fun parse(manufacturerData: ByteArray): ProximityPairingInfo? {
        if (manufacturerData.size < 2) return null
        val company = (manufacturerData[0].toInt() and 0xFF) or ((manufacturerData[1].toInt() and 0xFF) shl 8)
        if (company != APPLE_COMPANY_ID) return null
        return parsePayload(manufacturerData.copyOfRange(2, manufacturerData.size))
    }

    /** `p`: sirket kimligi SONRASI Continuity yuku (Android `getManufacturerSpecificData(0x4C)` cikti). Tip 0x07 aranir. */
    fun parsePayload(p: ByteArray): ProximityPairingInfo? {
        var i = 0
        while (i + 1 < p.size) {
            val type = p[i].toInt() and 0xFF
            val len = p[i + 1].toInt() and 0xFF
            val start = i + 2
            if (start + len > p.size) return null
            if (type == MESSAGE_TYPE) return decodeBody(p.copyOfRange(start, start + len))
            i = start + len
        }
        return null
    }

    private fun decodeBody(b: ByteArray): ProximityPairingInfo? {
        // b[0]=onek 0x01, b[1..2]=model (big-endian), b[3]=durum, b[4]=pil nibble'lari,
        // b[5]=sarj bitleri (ust nibble) + kutu pili (alt), b[6]=kapak sayaci, b[7]=renk.
        if (b.size < 9 || (b[0].toInt() and 0xFF) != 0x01) return null
        fun u(i: Int) = b[i].toInt() and 0xFF
        val model = (u(1) shl 8) or u(2)
        val status = u(3)
        val flipped = (status and 0x20) != 0
        val podA = batteryFromNibble(u(4) shr 4)
        val podB = batteryFromNibble(u(4) and 0x0F)
        val chargeBits = u(5) shr 4
        val chargeA = (chargeBits and 0x02) != 0
        val chargeB = (chargeBits and 0x01) != 0
        val thisInCase = (status and 0x40) != 0
        val inEarA = (status and 0x08) != 0
        val inEarB = (status and 0x02) != 0
        val leftUsesBit3 = (!flipped) != thisInCase
        return ProximityPairingInfo(
            model = model,
            modelName = AppleModelCatalog.model(model)?.name,
            rawStatus = status,
            left = if (flipped) podB else podA,
            right = if (flipped) podA else podB,
            caseBattery = batteryFromNibble(u(5) and 0x0F),
            leftCharging = if (flipped) chargeB else chargeA,
            rightCharging = if (flipped) chargeA else chargeB,
            caseCharging = (chargeBits and 0x04) != 0,
            leftInEar = if (leftUsesBit3) inEarA else inEarB,
            rightInEar = if (leftUsesBit3) inEarB else inEarA,
            lidCounter = u(6),
            color = u(7),
            headsetBattery = batteryFromNibble(u(4) and 0x0F),
            headsetCharging = (chargeBits and 0x01) != 0,
            headsetWorn = (status and 0x20) != 0,
            onePodInCase = (status and 0x10) != 0,
            bothPodsInCase = (status and 0x04) != 0,
        )
    }
}

enum class AppleFamily { AIRPODS, BEATS }

/** `TRUE_WIRELESS` = sol + sag (+ kutu); `HEADSET` = tek parca / boyun kablolu (tek pil). */
enum class AppleForm { TRUE_WIRELESS, HEADSET }

/** Model yetenekleri (bit maskesi). Android'de AAP kanali guvenilir olmadigi icin yalnizca bilgi amaclidir. */
object AppleCap {
    const val NOISE_CONTROL = 1 shl 0
    const val ADAPTIVE = 1 shl 1
    const val EAR_DETECTION = 1 shl 2
    const val CASE_BATTERY = 1 shl 3
    const val CONVERSATION_AWARENESS = 1 shl 4
    const val ONE_BUD_ANC = 1 shl 5
    const val ADAPTIVE_STRENGTH = 1 shl 6
    const val PERSONALIZED_VOLUME = 1 shl 7
    const val SLEEP_DETECTION = 1 shl 8
}

data class AppleModel(
    val id: Int,
    val name: String,
    val family: AppleFamily,
    val form: AppleForm,
    val capabilities: Int,
    /** Model kimligi iki bagimsiz kaynakta tutarli mi (false = deneysel). */
    val idVerified: Boolean,
) {
    fun supports(cap: Int) = capabilities and cap == cap
    val hasCase: Boolean get() = supports(AppleCap.CASE_BATTERY)
}

object AppleModelCatalog {
    private const val PLAIN = AppleCap.EAR_DETECTION or AppleCap.CASE_BATTERY
    private const val PRO1 = AppleCap.NOISE_CONTROL or AppleCap.ONE_BUD_ANC or AppleCap.EAR_DETECTION or AppleCap.CASE_BATTERY
    private const val PRO2 = AppleCap.NOISE_CONTROL or AppleCap.ADAPTIVE or AppleCap.CONVERSATION_AWARENESS or
        AppleCap.ONE_BUD_ANC or AppleCap.ADAPTIVE_STRENGTH or AppleCap.PERSONALIZED_VOLUME or
        AppleCap.SLEEP_DETECTION or AppleCap.EAR_DETECTION or AppleCap.CASE_BATTERY
    private const val BEATS_ANC = AppleCap.NOISE_CONTROL
    private const val NEW5 = AppleCap.NOISE_CONTROL or AppleCap.ADAPTIVE or AppleCap.CONVERSATION_AWARENESS or
        AppleCap.ADAPTIVE_STRENGTH or AppleCap.EAR_DETECTION or AppleCap.CASE_BATTERY

    private fun m(id: Int, name: String, f: AppleFamily, form: AppleForm, caps: Int, verified: Boolean) =
        AppleModel(id, name, f, form, caps, verified)

    private val A = AppleFamily.AIRPODS
    private val B = AppleFamily.BEATS
    private val TW = AppleForm.TRUE_WIRELESS
    private val HS = AppleForm.HEADSET

    val all: List<AppleModel> = listOf(
        m(0x0220, "AirPods (1. nesil)", A, TW, PLAIN, true),
        m(0x0F20, "AirPods (2. nesil)", A, TW, PLAIN, true),
        m(0x1320, "AirPods (3. nesil)", A, TW, PLAIN, true),
        m(0x1920, "AirPods 4", A, TW, PLAIN or AppleCap.SLEEP_DETECTION, false),
        m(0x1B20, "AirPods 4 (ANC)", A, TW, PRO2, false),
        m(0x0E20, "AirPods Pro", A, TW, PRO1, true),
        m(0x1420, "AirPods Pro (2. nesil, Lightning)", A, TW, PRO2, true),
        m(0x2420, "AirPods Pro (2. nesil, USB-C)", A, TW, PRO2, false),
        m(0x2720, "AirPods Pro 3", A, TW, PRO2, false),
        m(0x0A20, "AirPods Max (Lightning)", A, HS, AppleCap.NOISE_CONTROL or AppleCap.EAR_DETECTION, true),
        m(0x1F20, "AirPods Max (USB-C)", A, HS, AppleCap.NOISE_CONTROL or AppleCap.EAR_DETECTION, false),
        m(0x2D20, "AirPods Max 2", A, HS,
            AppleCap.NOISE_CONTROL or AppleCap.ADAPTIVE or AppleCap.CONVERSATION_AWARENESS or AppleCap.ADAPTIVE_STRENGTH or
                AppleCap.PERSONALIZED_VOLUME or AppleCap.EAR_DETECTION, false),
        m(0x3620, "AirPods (5. nesil)", A, TW, NEW5, false),
        m(0x3020, "AirPods (5. nesil, kablosuz kutu)", A, TW, NEW5, false),
        m(0x0320, "Powerbeats3", B, HS, 0, true),
        m(0x0D20, "Powerbeats4", B, HS, 0, false),
        m(0x0520, "BeatsX", B, HS, 0, true),
        m(0x0620, "Beats Solo3", B, HS, 0, true),
        m(0x0920, "Beats Studio3", B, HS, BEATS_ANC, false),
        m(0x0B20, "Powerbeats Pro", B, TW, PLAIN, true),
        m(0x0C20, "Beats Solo Pro", B, HS, BEATS_ANC, true),
        m(0x1020, "Beats Flex", B, HS, 0, true),
        m(0x1120, "Beats Studio Buds", B, TW, BEATS_ANC or AppleCap.CASE_BATTERY, true),
        m(0x1220, "Beats Fit Pro", B, TW, BEATS_ANC or AppleCap.EAR_DETECTION or AppleCap.CASE_BATTERY, true),
        m(0x1620, "Beats Studio Buds+", B, TW, BEATS_ANC or AppleCap.CASE_BATTERY, false),
        m(0x1720, "Beats Studio Pro", B, HS, BEATS_ANC, false),
        m(0x1D20, "Powerbeats Pro 2", B, TW,
            BEATS_ANC or AppleCap.EAR_DETECTION or AppleCap.CASE_BATTERY or AppleCap.SLEEP_DETECTION, false),
        m(0x2520, "Beats Solo 4", B, HS, 0, false),
        m(0x2620, "Beats Solo Buds", B, TW, AppleCap.CASE_BATTERY, false),
        m(0x3820, "Beats 360", B, HS, BEATS_ANC, false),
    )

    private val byId: Map<Int, AppleModel> = all.associateBy { it.id }

    fun model(id: Int): AppleModel? = byId[id]
}
