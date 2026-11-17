package com.btekosistem.android.peer

import org.junit.Assert.assertEquals
import java.net.ConnectException
import java.net.SocketTimeoutException
import org.junit.Test

class ReconnectBackoffTest {
    @Test fun `dizi 1 2 5 10 30 sonra 30 sabit`() {
        val b = ReconnectBackoff()
        val got = List(9) { b.next() }
        assertEquals(listOf(1_000L, 2_000, 5_000, 10_000, 30_000, 30_000, 30_000, 30_000, 30_000), got)
    }

    @Test fun `sifirlama basa doner ve sonsuz denemede tasmaz`() {
        val b = ReconnectBackoff()
        repeat(1_000) { b.next() }
        assertEquals(30_000L, b.next())
        b.reset()
        assertEquals(1_000L, b.next())
        assertEquals(2_000L, b.next())
    }

    @Test fun `kopma nedeni eslemesi`() {
        assertEquals(MacReason.TIMEOUT, MacReason.from(SocketTimeoutException()))
        assertEquals(MacReason.REFUSED, MacReason.from(ConnectException("Connection refused")))
        assertEquals(MacReason.NOT_FOUND, MacReason.from(ConnectException("Network is unreachable")))
        assertEquals(MacReason.LOST, MacReason.from(IllegalStateException()))
    }
}
