package com.btekosistem.android.ble

/** Tarama gucu (Android ScanSettings modlarina eslenir; saf mantik icin ayri). */
enum class ScanIntensity { BALANCED, LOW_LATENCY }

/**
 * Hangi tarama profili / gucu: LE adresi bilinmeyen eslesmis QCY varken ACTIVE pencerede LOW_LATENCY (pencere kisa ve seyrek);
 * adres biliniyorsa dogrudan GATT'e gidilir, tarama yalniz seyrek (SPARSE) kalir. ScanScheduler kurallari degismez.
 */
object ScanPolicy {
    fun profile(connected: Boolean, bondedQcy: Int, unresolvedQcy: Int): ScanProfile = when {
        connected -> ScanProfile.SPARSE
        bondedQcy > 0 && unresolvedQcy == 0 -> ScanProfile.SPARSE
        else -> ScanProfile.ACTIVE
    }

    fun intensity(profile: ScanProfile, unresolvedQcy: Int): ScanIntensity =
        if (profile == ScanProfile.ACTIVE && unresolvedQcy > 0) ScanIntensity.LOW_LATENCY else ScanIntensity.BALANCED
}

/**
 * Kulakliga otomatik GATT baglanma kapisi: en az 5 sn, en cok 2 dk ustel geri cekilme; elle "kes" o oturumda otomatigi kapatir.
 */
class AutoConnect(private val minMs: Long = 5_000L, private val maxMs: Long = 120_000L) {
    private var enabled = true
    private var failures = 0
    private var nextAt = 0L

    val isEnabled: Boolean get() = enabled

    fun mayAttempt(nowMs: Long): Boolean = enabled && nowMs >= nextAt

    fun delayFor(failureCount: Int): Long {
        var d = minMs
        repeat((failureCount - 1).coerceAtLeast(0)) { d = minOf(d * 2, maxMs) }
        return minOf(d, maxMs)
    }

    fun failed(nowMs: Long) {
        failures++
        nextAt = nowMs + delayFor(failures)
    }

    fun succeeded(nowMs: Long) {
        failures = 0
        nextAt = nowMs + minMs
    }

    /** Kullanici elle kesti: oturum boyunca otomatik baglanma yok. */
    fun disable() { enabled = false }

    /** Kullanici elle baglandi: otomatik yeniden acilir, geri cekilme sifirlanir. */
    fun enable() { enabled = true; failures = 0; nextAt = 0L }
}
