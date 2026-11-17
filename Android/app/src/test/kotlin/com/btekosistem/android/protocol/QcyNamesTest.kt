package com.btekosistem.android.protocol

import com.btekosistem.android.ble.QcyNames
import org.junit.Test
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue

class QcyNamesTest {
    @Test fun matchesKnownNames() {
        assertTrue(QcyNames.isQcy("QCY MeloBuds Pro"))
        assertTrue(QcyNames.isQcy("  qcy t13 "))
        assertTrue(QcyNames.isQcy("MeloBuds"))
        assertTrue(QcyNames.isQcy("Melo T1"))
    }

    @Test fun rejectsOthers() {
        assertFalse(QcyNames.isQcy(null))
        assertFalse(QcyNames.isQcy(""))
        assertFalse(QcyNames.isQcy("AirPods Pro"))
    }
}
