package com.btekosistem.android.peer

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerPathPolicyTest {
    @Test fun `bluetooth yalniz eslesmis ve wifi yokken tek oturum`() {
        assertTrue(PeerPathPolicy.acceptBluetooth(wifiBusy = false, bluetoothActive = false, paired = true))
        assertFalse(PeerPathPolicy.acceptBluetooth(true, false, true))
        assertFalse(PeerPathPolicy.acceptBluetooth(false, true, true))
        assertFalse(PeerPathPolicy.acceptBluetooth(false, false, false))
    }

    @Test fun `wifi'de mac bulununca bluetooth'tan gecilir`() {
        assertTrue(PeerPathPolicy.switchToWifi(true, true))
        assertFalse(PeerPathPolicy.switchToWifi(false, true))
        assertFalse(PeerPathPolicy.switchToWifi(true, false))
    }

    @Test fun `dosya aktarimi bluetooth'ta kapali`() {
        assertFalse(PeerPathPolicy.fileTransferAllowed(PeerPath.BLUETOOTH))
        assertTrue(PeerPathPolicy.fileTransferAllowed(PeerPath.WIFI))
        assertTrue(PeerPathPolicy.isTransferType("transfer.offer"))
        assertFalse(PeerPathPolicy.isTransferType("call.state"))
    }

    @Test fun `ilk eslesme penceresi acikken eslesmemis Mac kabul edilir`() {
        assertTrue(PeerPathPolicy.acceptBluetooth(false, false, paired = false, pairingOpen = true))
        assertFalse(PeerPathPolicy.acceptBluetooth(true, false, paired = false, pairingOpen = true))
        assertTrue(PeerPathPolicy.pairingAddressMatches("AA:BB:CC:DD:EE:FF", "aa:bb:cc:dd:ee:ff"))
        assertFalse(PeerPathPolicy.pairingAddressMatches("AA:BB:CC:DD:EE:FF", "11:22:33:44:55:66"))
        assertFalse(PeerPathPolicy.pairingAddressMatches(null, "11:22:33:44:55:66"))
        assertTrue(PeerPathPolicy.isProvisionalId("bt:AA:BB"))
        assertFalse(PeerPathPolicy.isProvisionalId("uuid-1"))
    }
}
