package com.btekosistem.android.peer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PeerFramingTest {
    @Test fun `cerceve ornegi`() {
        assertArrayEquals(byteArrayOf(0, 0, 0, 3, 1, 2, 3), PeerFraming.encode(byteArrayOf(1, 2, 3)))
    }

    @Test fun `parcali gelen akis tamponlanir ve birlesik cerceveler ayrilir`() {
        val b = PeerFrameBuffer()
        val a = PeerFraming.encode(byteArrayOf(1, 2, 3))
        val c = PeerFraming.encode(byteArrayOf(9))
        val all = a + c
        assertEquals(0, b.append(all.copyOfRange(0, 2)).size)
        assertEquals(0, b.append(all.copyOfRange(2, 6)).size)
        val out = b.append(all.copyOfRange(6, all.size))
        assertEquals(2, out.size)
        assertArrayEquals(byteArrayOf(1, 2, 3), out[0])
        assertArrayEquals(byteArrayOf(9), out[1])
    }

    @Test fun `sifir ve fazla uzunluk protokol hatasidir`() {
        assertThrows(PeerProtocolException::class.java) { PeerFrameBuffer().append(byteArrayOf(0, 0, 0, 0)) }
        assertThrows(PeerProtocolException::class.java) { PeerFrameBuffer().append(byteArrayOf(0, 0x10, 0, 1)) }
        assertThrows(PeerProtocolException::class.java) { PeerFrameBuffer().append(byteArrayOf(-1, -1, -1, -1)) }
        assertThrows(IllegalArgumentException::class.java) { PeerFraming.encode(ByteArray(0)) }
    }

    @Test fun `sinir uzunlugu kabul edilir`() {
        val payload = ByteArray(PeerFraming.MAX_PAYLOAD) { 7 }
        val out = PeerFrameBuffer().append(PeerFraming.encode(payload))
        assertEquals(1, out.size)
        assertEquals(PeerFraming.MAX_PAYLOAD, out[0].size)
    }
}
