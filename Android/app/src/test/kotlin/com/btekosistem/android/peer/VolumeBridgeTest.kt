package com.btekosistem.android.peer

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

class VolumeBridgeTest {
    private class FakePort(var state: VolState = VolState(40, false)) : VolumePort {
        var cb: (() -> Unit)? = null
        override fun read() = state
        override fun apply(level: Int?, muted: Boolean?) { state = VolState(level ?: state.level, muted ?: state.muted) }
        override fun setOnChange(cb: (() -> Unit)?) { this.cb = cb }
        /** Sistem/kullanici degisikligi (receiver tetigi). */
        fun external(s: VolState) { state = s; cb?.invoke() }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val port = FakePort()
    private val sent = CopyOnWriteArrayList<PeerMessage>()

    private fun wire(): VolumeBridge {
        val b = VolumeBridge(port, scope, 40)
        b.attachMac { sent += it }
        return b
    }

    @After fun tearDown() { scope.cancel() }

    // Swift tarafi (PeerMessageTests) ile ayni dizgiler.
    @Test fun `vol JSON ornekleri Swift ile birebir`() {
        assertEquals("""{"cihaz":"mac","sessiz":false,"seviye":40,"t":"vol.state"}""", PeerCodec.encode(PeerMessage.VolState("mac", 40, false)))
        assertEquals("""{"hedef":"telefon","seviye":70,"t":"vol.set"}""", PeerCodec.encode(PeerMessage.VolSet("telefon", 70)))
        assertEquals("""{"hedef":"mac","sessiz":true,"t":"vol.set"}""", PeerCodec.encode(PeerMessage.VolSet("mac", sessiz = true)))
    }

    @Test fun `vol mesajlari geri okunur`() {
        val a = PeerMessage.VolState("telefon", 55, true)
        val b = PeerMessage.VolSet("mac", 10)
        val c = PeerMessage.VolSet("telefon", sessiz = false)
        assertEquals(a, PeerCodec.decode(PeerCodec.encode(a)))
        assertEquals(b, PeerCodec.decode(PeerCodec.encode(b)))
        assertEquals(c, PeerCodec.decode(PeerCodec.encode(c)))
    }

    @Test fun `oturum kurulunca bir kez yollanir ve hizli degisimler birlesir`() {
        wire()
        Thread.sleep(200)
        assertEquals(listOf<PeerMessage>(PeerMessage.VolState("telefon", 40, false)), sent.toList())
        port.external(VolState(41, false)); port.external(VolState(42, false)); port.external(VolState(43, false))
        Thread.sleep(250)
        assertEquals(PeerMessage.VolState("telefon", 43, false), sent.last())
        assertEquals(2, sent.size)
    }

    @Test fun `uzaktan uygulanan degisim geri yayinlanmaz`() {
        val b = wire()
        Thread.sleep(200)
        sent.clear()
        b.onRemoteSet(PeerMessage.VolSet("telefon", 80))
        port.cb?.invoke()
        Thread.sleep(250)
        assertEquals(VolState(80, false), port.state)
        assertEquals(VolState(80, false), b.local.value)
        assertEquals(0, sent.size)
        // sonraki yerel degisim yine yollanir
        port.external(VolState(20, false))
        Thread.sleep(250)
        assertEquals(listOf<PeerMessage>(PeerMessage.VolState("telefon", 20, false)), sent.toList())
    }

    @Test fun `baska hedefe giden vol set yok sayilir ve mac durumu tutulur`() {
        val b = wire()
        b.onRemoteSet(PeerMessage.VolSet("mac", 5))
        assertEquals(VolState(40, false), port.state)
        assertNull(b.mac.value)
        b.onMacState(PeerMessage.VolState("mac", 60, true))
        assertEquals(VolState(60, true), b.mac.value)
        b.detachMac()
        assertNull(b.mac.value)
    }

    @Test fun `setMac vol set yollar`() {
        val b = wire()
        b.setMac(30, null)
        assertEquals(PeerMessage.VolSet("mac", 30), sent.last { it is PeerMessage.VolSet })
    }
}
