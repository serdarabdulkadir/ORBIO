package com.btekosistem.android.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScanSchedulerTest {
    private fun ms(s: Int) = s * 1_000L

    @Test fun `etkin pencere 4 sn acik 20 sn kapali`() {
        val s = ScanScheduler()
        assertEquals(ScanScheduler.Action.START, s.tick(ms(0), ScanProfile.ACTIVE))
        assertEquals(ScanScheduler.Action.NONE, s.tick(ms(3), ScanProfile.ACTIVE))
        assertEquals(ScanScheduler.Action.STOP, s.tick(ms(4), ScanProfile.ACTIVE))
        assertEquals(ScanScheduler.Action.NONE, s.tick(ms(23), ScanProfile.ACTIVE))
        assertEquals(ScanScheduler.Action.START, s.tick(ms(24), ScanProfile.ACTIVE))
    }

    @Test fun `kapali profil hemen durdurur`() {
        val s = ScanScheduler()
        s.tick(ms(0), ScanProfile.ACTIVE)
        assertEquals(ScanScheduler.Action.STOP, s.tick(ms(1), ScanProfile.OFF))
        assertEquals(ScanScheduler.Action.NONE, s.tick(ms(2), ScanProfile.OFF))
        assertFalse(s.isScanning)
    }

    @Test fun `seyrek pencere 2 sn acik 60 sn kapali`() {
        val s = ScanScheduler()
        assertEquals(ScanScheduler.Action.START, s.tick(ms(0), ScanProfile.SPARSE))
        assertEquals(ScanScheduler.Action.STOP, s.tick(ms(2), ScanProfile.SPARSE))
        assertEquals(ScanScheduler.Action.NONE, s.tick(ms(61), ScanProfile.SPARSE))
        assertEquals(ScanScheduler.Action.START, s.tick(ms(62), ScanProfile.SPARSE))
    }

    @Test fun `seyrekten etkine gecis kapali sureyi 20 sn ile sinirlar`() {
        val s = ScanScheduler()
        s.tick(ms(0), ScanProfile.SPARSE)
        s.tick(ms(2), ScanProfile.SPARSE)
        assertEquals(ScanScheduler.Action.NONE, s.tick(ms(21), ScanProfile.ACTIVE))
        assertEquals(ScanScheduler.Action.START, s.tick(ms(22), ScanProfile.ACTIVE))
    }

    @Test fun `bostayken talep gelince hemen baslar`() {
        val s = ScanScheduler()
        assertEquals(ScanScheduler.Action.NONE, s.tick(ms(0), ScanProfile.OFF))
        assertEquals(ScanScheduler.Action.START, s.tick(ms(5), ScanProfile.ACTIVE))
        assertTrue(s.isScanning)
    }

    @Test fun `etkin toplam yuk yuzde 20nin altinda`() {
        val s = ScanScheduler()
        var scanning = false
        var on = 0
        for (sec in 0 until 240) {
            when (s.tick(ms(sec), ScanProfile.ACTIVE)) {
                ScanScheduler.Action.START -> scanning = true
                ScanScheduler.Action.STOP -> scanning = false
                ScanScheduler.Action.NONE -> {}
            }
            if (scanning) on++
        }
        assertTrue(on / 240.0 < 0.2)
    }

    @Test fun `yazma araligi en az 150 ms`() {
        val p = WritePacer(150)
        assertEquals(0L, p.reserve(1_000))
        assertEquals(100L, p.reserve(1_050))   // 1000+150 -> 1150; simdi 1050
        assertEquals(150L, p.reserve(1_150))   // onceki yazma 1150'ye ayrildi
        assertEquals(0L, p.reserve(2_000))
    }
}
