package com.btekosistem.android.peer

import com.btekosistem.android.protocol.QcyAdvertisement
import com.btekosistem.android.protocol.QcyChar
import kotlinx.coroutines.launch
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ControlRelayTest {
    private val addr = "84:AC:60:20:9D:3A"

    @Test fun `hex gidis donus`() {
        val b = byteArrayOf(0xFF.toByte(), 0x03, 0xFE.toByte(), 0x01, 0x17)
        assertEquals("ff03fe0117", QcyHex.encode(b))
        assertArrayEquals(b, QcyHex.decode("FF03fe0117"))
        assertNull(QcyHex.decode("abc"))
        assertNull(QcyHex.decode("zz"))
    }

    @Test fun `aktarim secimi`() {
        assertFalse(TransportPolicy.shouldTryGatt(sessionOpen = true, macOwns = true))
        assertTrue(TransportPolicy.shouldTryGatt(sessionOpen = true, macOwns = false))
        assertTrue(TransportPolicy.shouldTryGatt(sessionOpen = false, macOwns = true))
        assertTrue(TransportPolicy.useRelayAfterGattFailure(true, true))
        assertFalse(TransportPolicy.useRelayAfterGattFailure(true, false))
        assertFalse(TransportPolicy.useRelayAfterGattFailure(false, true))
    }

    @Test fun `mac sahipligi oturum kopunca sifirlanir`() {
        val r = ControlRelay()
        r.sessionStarted { }
        r.onMessage(PeerMessage.CtlOwner(addr.lowercase(), true))
        assertTrue(r.macOwns(addr))
        r.onMessage(PeerMessage.CtlOwner(addr, false))
        assertFalse(r.macOwns(addr))
        r.onMessage(PeerMessage.CtlOwner(addr, true))
        r.sessionEnded()
        assertFalse(r.macOwns(addr))
        assertFalse(r.sessionOpen.value)
    }

    @Test fun `telefon sahiplik bildirir ve oturum kurulunca yeniden gonderir`() {
        val sent = ArrayList<PeerMessage>()
        val r = ControlRelay()
        r.setPhoneOwns(addr, true) // oturum yok: gonderilmez
        r.sessionStarted { sent += it }
        assertEquals(listOf<PeerMessage>(PeerMessage.CtlOwner(addr, true)), sent)
        r.setPhoneOwns(addr, true) // degisim yok
        r.setPhoneOwns(addr, false)
        assertEquals(PeerMessage.CtlOwner(addr, false), sent.last())
        assertEquals(2, sent.size)
    }

    @Test fun `yazma ve bildirim iletimi`() {
        val sent = ArrayList<PeerMessage>()
        val r = ControlRelay()
        assertFalse(r.sendWrite(addr, byteArrayOf(1)))
        r.sessionStarted { sent += it }
        assertTrue(r.sendWrite(addr, byteArrayOf(0xFF.toByte(), 0x03)))
        assertEquals(PeerMessage.CtlWrite(addr, "ff03"), sent.last())
        assertTrue(r.sendWrite(addr, byteArrayOf(3, 1), QcyChar.KEYMAP))
        assertEquals(PeerMessage.CtlWrite(addr, "0301", "000d"), sent.last())
        assertTrue(r.sendWrite(addr, byteArrayOf(2), QcyChar.LEGACY_EQ))
        assertEquals(PeerMessage.CtlWrite(addr, "02", "000b"), sent.last())
        r.sendNotify(addr, IncomingKind.RESPONSE, byteArrayOf(1, 2))
        assertEquals(PeerMessage.CtlNotify(addr, "yanit", "0102"), sent.last())
        val n = sent.size
        r.sendNotify(addr, IncomingKind.ADVERT, byteArrayOf(9), nowMs = 1000)
        r.sendNotify(addr, IncomingKind.ADVERT, byteArrayOf(9), nowMs = 2000) // ayni veri, 5 sn dolmadi
        assertEquals(n + 1, sent.size)
        assertEquals(PeerMessage.CtlNotify(addr, "reklam", "09"), sent.last())
        r.sendNotify(addr, IncomingKind.ADVERT, byteArrayOf(9), nowMs = 7000)
        assertEquals(n + 2, sent.size)
    }

    @Test fun `gelen ctl write kar a gore hedeflenir`() {
        val r = ControlRelay()
        val got = ArrayList<RelayedWrite>()
        val job = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Unconfined).launch { r.writesFromMac.collect { got += it } }
        r.onMessage(PeerMessage.CtlWrite(addr, "ff03fe0117"))
        r.onMessage(PeerMessage.CtlWrite(addr, "0301", "000D"))
        r.onMessage(PeerMessage.CtlWrite(addr, "02", "000b"))
        r.onMessage(PeerMessage.CtlWrite(addr, "02", "zzzz")) // bilinmeyen kar atilir
        job.cancel()
        assertEquals(listOf(QcyChar.COMMAND, QcyChar.KEYMAP, QcyChar.LEGACY_EQ), got.map { it.target })
        assertEquals(null, QcyChar.fromKar("1002"))
    }

    @Test fun `reklam kodlayici ayristiriciyla uyumlu`() {
        val ad = QcyAdvertisement(80, 75, 60, true, false, false, addr)
        val back = QcyAdvCodec.decode(QcyAdvCodec.encode(ad))
        assertEquals(ad, back)
        val raw = QcyAdvCodec.encode(ad)
        assertEquals(19, raw.size)
        assertEquals("1c52", QcyHex.encode(raw.copyOfRange(0, 2)))
    }
}
