package com.btekosistem.android.ble

import com.btekosistem.android.protocol.AppleFamily
import com.btekosistem.android.protocol.ProximityPairingInfo

/** Bir Apple reklam gorunumu (adres RPA oldugu icin kararsiz olabilir; yalniz tekrarlari ayirmak icin). */
data class AppleSighting(val address: String, val info: ProximityPairingInfo, val rssi: Int, val seenAtMs: Long)

/** Android'e bagimli degil. Yakindaki birden cok Apple cihazindan "bizim" kulakligi secer. */
object AppleSelector {
    const val FRESH_MS = 15_000L
    /** Bagli ses cihazi yoksa yalniz bu esikten guclu reklamlar (yan komsu / uzak cihaz) gosterilir. */
    const val NEAR_RSSI = -75

    private fun familyOfName(name: String?): AppleFamily? {
        val n = name?.lowercase() ?: return null
        return when {
            "airpods" in n -> AppleFamily.AIRPODS
            "beats" in n || "powerbeats" in n -> AppleFamily.BEATS
            else -> null
        }
    }

    /**
     * `connectedAudioNames`: A2DP/HFP ile bagli cihaz adlari. Bunlardan biri Apple/Beats gibi gorunuyorsa yalniz
     * ayni ailedeki (ya da adi model adini iceren) adaylar kalir; kalan adaylar arasindan RSSI'i en guclu secilir.
     */
    fun pick(sightings: Collection<AppleSighting>, connectedAudioNames: List<String?>, nowMs: Long): AppleSighting? {
        val fresh = sightings.filter { nowMs - it.seenAtMs <= FRESH_MS && it.info.modelName != null }
        if (fresh.isEmpty()) return null
        val connected = connectedAudioNames.filterNotNull()
        val families = connected.mapNotNull(::familyOfName).toSet()
        if (families.isNotEmpty()) {
            val byName = fresh.filter { s -> connected.any { n -> n.contains(s.info.modelName!!, ignoreCase = true) } }
            val pool = byName.ifEmpty { fresh.filter { it.info.modelInfo?.family in families } }
            return pool.maxByOrNull { it.rssi }
        }
        return fresh.filter { it.rssi >= NEAR_RSSI }.maxByOrNull { it.rssi }
    }
}
