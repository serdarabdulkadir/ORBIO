package com.btekosistem.android.peer

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OwnershipPolicyTest {
    @Test fun `oturum yokken otomatik GATT serbest`() {
        assertTrue(OwnershipPolicy.autoGattAllowed(false, false, false))
    }

    @Test fun `oturum aciksa Mac sahipken telefon denemez`() {
        assertFalse(OwnershipPolicy.autoGattAllowed(true, true, true))
        assertFalse(OwnershipPolicy.autoGattAllowed(true, true, false))
    }

    @Test fun `oturum acik Mac sahip degil yalniz telefondan yonetim basladiysa`() {
        assertFalse(OwnershipPolicy.autoGattAllowed(true, false, false))
        assertTrue(OwnershipPolicy.autoGattAllowed(true, false, true))
    }

    @Test fun `Mac biraktiktan sonra GATT'e donus`() {
        assertTrue(OwnershipPolicy.returnToGattAfterMacRelease(true, false))
        assertFalse(OwnershipPolicy.returnToGattAfterMacRelease(false, false))
    }
}
