package com.btekosistem.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerSessionTest {
    private fun mac(pinned: ByteArray? = null) = PeerSession(
        PeerRole.MAC, P256.privateKeyFromRaw(Vectors.macPriv), Vectors.macPub, "MacBook", pinned, Vectors.macNonce,
        PeerMessage.Hello("MacBook", "1.0", 1, "mac-id", "mac"),
    )

    private fun phone(pinned: ByteArray? = null) = PeerSession(
        PeerRole.TELEFON, P256.privateKeyFromRaw(Vectors.phonePriv), Vectors.phonePub, "Pixel", pinned, Vectors.phoneNonce,
        PeerMessage.Hello("Pixel", "0.2.0", 1, "phone-id", "android"),
    )

    private fun bytes(events: List<PeerEvent>) = events.filterIsInstance<PeerEvent.Send>().fold(ByteArray(0)) { acc, e -> acc + e.bytes }

    @Test fun `ilk eslesme iki tarafta ayni SAS gosterir ve onayla oturum kurulur`() {
        val m = mac(); val p = phone()
        val hsM = bytes(m.start()); val hsP = bytes(p.start())
        val evM = m.receive(hsP); val evP = p.receive(hsM)
        assertEquals("538801", (evM.single() as PeerEvent.SasRequired).code)
        assertEquals("538801", (evP.single() as PeerEvent.SasRequired).code)
        assertEquals(PeerSession.Phase.AWAIT_SAS, p.phase)

        val okM = m.confirmSas(true); val okP = p.confirmSas(true)
        assertTrue(okP.any { it is PeerEvent.Paired })
        assertTrue(okP.any { it is PeerEvent.Ready })
        // Mac'in hello'su SAS'tan once gelmis olsaydi bekletilirdi; simdi karsilikli hello islenir
        val gotP = p.receive(bytes(okM)).filterIsInstance<PeerEvent.Received>().single().message as PeerMessage.Hello
        val gotM = m.receive(bytes(okP)).filterIsInstance<PeerEvent.Received>().single().message as PeerMessage.Hello
        assertEquals("mac", gotP.platform)
        assertEquals("android", gotM.platform)

        val ping = p.send(PeerMessage.Ping(1))
        assertEquals(PeerMessage.Ping(1), (m.receive(bytes(ping)).single() as PeerEvent.Received).message)
    }

    @Test fun `SAS onaylanmadan gelen sifreli mesaj bekler onaydan sonra islenir`() {
        val m = mac(); val p = phone()
        val hsM = bytes(m.start()); val hsP = bytes(p.start())
        m.receive(hsP); p.receive(hsM)
        val early = bytes(m.confirmSas(true))          // Mac onayladi, hello gonderdi
        assertTrue(p.receive(early).isEmpty())          // telefon henuz onaylamadi: bekletildi
        val after = p.confirmSas(true)
        assertNotNull(after.filterIsInstance<PeerEvent.Received>().singleOrNull())
    }

    @Test fun `SAS reddi baglantiyi kapatir`() {
        val m = mac(); val p = phone()
        m.receive(bytes(p.start())); p.receive(bytes(m.start()))
        val ev = p.confirmSas(false)
        assertEquals(CloseReason.SAS_REJECTED, (ev.single() as PeerEvent.Closed).reason)
        assertEquals(PeerSession.Phase.CLOSED, p.phase)
    }

    @Test fun `sabitlenmis anahtarda SAS gosterilmez dogrudan hazir olur`() {
        val p = phone(pinned = Vectors.macPub); val m = mac()
        m.start()
        val ev = p.receive(bytes(m.start()))
        assertTrue(ev.any { it is PeerEvent.Ready })
        assertTrue(ev.none { it is PeerEvent.SasRequired })
    }

    @Test fun `sabitlenen anahtar degisirse kapatir`() {
        val p = phone(pinned = Vectors.phonePub) // yanlis anahtar sabitlenmis gibi
        val ev = p.receive(bytes(mac().start()))
        assertEquals(CloseReason.KEY_CHANGED, (ev.single() as PeerEvent.Closed).reason)
    }

    @Test fun `ayni rol ve gecersiz el sikisma kapatilir`() {
        val p = phone()
        val ev = p.receive(bytes(phone().start()))
        assertEquals(CloseReason.ROLE, (ev.single() as PeerEvent.Closed).reason)
        val q = phone()
        val bad = PeerFraming.encode("""{"t":"hs","v":1,"rol":"mac","pub":"AAAA","nonce":"AAAA"}""".toByteArray())
        assertEquals(CloseReason.PROTOCOL, (q.receive(bad).single() as PeerEvent.Closed).reason)
    }

    @Test fun `tekrar edilen sifreli cerceve olumculdur`() {
        val p = phone(pinned = Vectors.macPub); val m = mac(pinned = Vectors.phonePub)
        val hsM = bytes(m.start()); val hsP = bytes(p.start())
        val fromM = bytes(m.receive(hsP)); p.receive(hsM)
        val first = p.receive(fromM)
        assertTrue(first.any { it is PeerEvent.Received })
        val again = p.receive(fromM)
        assertEquals(CloseReason.CRYPTO, (again.single() as PeerEvent.Closed).reason)
    }

    @Test fun `eslesme kodu hs cercevesinde HMAC kaniti olarak gider ve kodun kendisi gitmez`() {
        val p = PeerSession(
            PeerRole.TELEFON, P256.privateKeyFromRaw(Vectors.phonePriv), Vectors.phonePub, "Pixel", null, Vectors.phoneNonce,
            PeerMessage.Hello("Pixel", "0.2.0", 1, "phone-id", "android"), "123456",
        )
        val text = String(bytes(p.start()).copyOfRange(4, bytes(p.start()).size), Charsets.UTF_8)
        assertTrue(text.contains("\"kod\""))
        assertTrue(!text.contains("123456"))
        assertTrue(!String(bytes(phone().start()), Charsets.UTF_8).contains("\"kod\""))
    }

    @Test fun `Mac eslesmeyi reddederse neden telefona ulasir`() {
        val p = phone()
        p.start()
        val red = PeerFraming.encode("""{"t":"hs_red","neden":"kod_gerekli"}""".toByteArray())
        assertEquals(CloseReason.PAIR_REFUSED, (p.receive(red).single() as PeerEvent.Closed).reason)
        assertEquals("kod_gerekli", p.refusal)
    }
}
