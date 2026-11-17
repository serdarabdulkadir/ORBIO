package com.btekosistem.android.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScanPolicyTest {
    @Test fun `adres yokken ACTIVE ve LOW_LATENCY`() {
        val p = ScanPolicy.profile(false, 1, 1)
        assertEquals(ScanProfile.ACTIVE, p)
        assertEquals(ScanIntensity.LOW_LATENCY, ScanPolicy.intensity(p, 1))
    }

    @Test fun `adres biliniyorsa ya da bagliysa SPARSE ve BALANCED`() {
        assertEquals(ScanProfile.SPARSE, ScanPolicy.profile(false, 1, 0))
        assertEquals(ScanProfile.SPARSE, ScanPolicy.profile(true, 1, 1))
        assertEquals(ScanIntensity.BALANCED, ScanPolicy.intensity(ScanProfile.SPARSE, 1))
    }

    @Test fun `eslesmis cihaz yoksa ACTIVE ama BALANCED`() {
        val p = ScanPolicy.profile(false, 0, 0)
        assertEquals(ScanProfile.ACTIVE, p)
        assertEquals(ScanIntensity.BALANCED, ScanPolicy.intensity(p, 0))
    }

    @Test fun `otomatik baglanma ustel geri cekilme 5 sn ile 2 dk arasi`() {
        val a = AutoConnect()
        assertTrue(a.mayAttempt(0))
        val got = (1..7).map { a.delayFor(it) }
        assertEquals(listOf(5_000L, 10_000, 20_000, 40_000, 80_000, 120_000, 120_000), got)
        a.failed(1_000)
        assertFalse(a.mayAttempt(5_999))
        assertTrue(a.mayAttempt(6_000))
    }

    @Test fun `elle kesince kapanir elle baglaninca acilir basari sifirlar`() {
        val a = AutoConnect()
        a.failed(0); a.failed(0)
        a.disable()
        assertFalse(a.mayAttempt(1_000_000))
        a.enable()
        assertTrue(a.mayAttempt(0))
        a.failed(0); a.succeeded(0); a.failed(100)
        assertFalse(a.mayAttempt(5_099))
        assertTrue(a.mayAttempt(5_100))
    }
}
