package com.btekosistem.android.ble

/** Tarama yogunlugu: surekli tarama A2DP akarken 2.4 GHz'te cizirti yapar, bu yuzden pencereli taranir. */
enum class ScanProfile(val onMs: Long, val offMs: Long) {
    /** Tarama yok. */
    OFF(0, 0),
    /** Kontrol kanali hazir (pil GATT / Mac yanit akisindan): seyrek kisa pencere. */
    SPARSE(2_000, 60_000),
    /** Cihaz gorunmuyor / bagli degil: 4 sn acik, 20 sn kapali. */
    ACTIVE(4_000, 20_000),
}

/** Android'e bagimli degil; Mac tarafindaki ScanScheduler.swift ile ayni kurallar. */
class ScanScheduler {
    enum class Action { NONE, START, STOP }

    private enum class Phase { IDLE, SCANNING, COOLING }

    private var phase = Phase.IDLE
    private var until = 0L
    private var coolingSince = 0L
    private var last = ScanProfile.OFF

    val isScanning: Boolean get() = phase == Phase.SCANNING

    /** Saniyede bir cagrilir. */
    fun tick(nowMs: Long, profile: ScanProfile): Action {
        val previous = last
        last = profile
        if (profile == ScanProfile.OFF) {
            val was = isScanning
            phase = Phase.IDLE
            return if (was) Action.STOP else Action.NONE
        }
        when (phase) {
            Phase.IDLE -> {
                phase = Phase.SCANNING; until = nowMs + profile.onMs
                return Action.START
            }
            Phase.SCANNING -> {
                if (nowMs >= until) {
                    phase = Phase.COOLING; coolingSince = nowMs; until = nowMs + profile.offMs
                    return Action.STOP
                }
                if (profile != previous) until = minOf(until, nowMs + profile.onMs)
                return Action.NONE
            }
            Phase.COOLING -> {
                val end = minOf(until, coolingSince + profile.offMs)
                if (nowMs >= end) {
                    phase = Phase.SCANNING; until = nowMs + profile.onMs
                    return Action.START
                }
                return Action.NONE
            }
        }
    }

    fun reset() { phase = Phase.IDLE; last = ScanProfile.OFF }
}

/** Yazmalar arasi en az `minIntervalMs`: BLE denetleyicisine art arda yazma yagdirmaz. */
class WritePacer(private val minIntervalMs: Long = 150) {
    private var lastMs = Long.MIN_VALUE / 2

    /** Simdi yazilirsa beklenmesi gereken ms (0 = hemen). Cagri yazmayi kaydeder. */
    fun reserve(nowMs: Long): Long {
        val wait = maxOf(0L, lastMs + minIntervalMs - nowMs)
        lastMs = nowMs + wait
        return wait
    }
}
