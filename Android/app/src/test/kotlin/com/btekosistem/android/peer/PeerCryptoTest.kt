package com.btekosistem.android.peer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

object Vectors {
    val macPriv = ByteArray(32) { (it + 1).toByte() }
    val phonePriv = ByteArray(32) { (it + 33).toByte() }
    val macNonce = ByteArray(16) { (0xA0 + it).toByte() }
    val phoneNonce = ByteArray(16) { (0xB0 + it).toByte() }
    val macPub = hexToBytes("04515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354")
    val phonePub = hexToBytes("041f140146bfb1b251f84f4ddbe0d4cdcfd77afd984a9520e35794021f8312bb9eec995a08b1fa7704df3dcc0b50a9665263fb7711f95f9f8a449c5096e47c892b")
    const val SECRET = "4fe243908f378aa1c2a69538822e6ed908c3225d8692575507c649901245150a"
    const val MAC_TO_PHONE = "3e7994371738fd367f8393c81893a0371df27a71ed52fdd4142ec49917eccef0"
    const val PHONE_TO_MAC = "cbe20cf9b684bdb2a428ae219e708ce69a45856684940b59a7a0165e3df6aaf8"
}

class PeerCryptoTest {
    @Test fun `HKDF RFC 5869 test 1`() {
        val okm = hkdfSha256(ByteArray(22) { 0x0b }, ByteArray(13) { it.toByte() }, ByteArray(10) { (0xf0 + it).toByte() }, 42)
        assertEquals("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865", okm.toHexLower())
    }

    @Test fun `ham skalerden acik anahtar belgedeki X963 ile eslesir`() {
        assertEquals(Vectors.macPub.toHexLower(), P256.x963(P256.publicFromX963(Vectors.macPub)).toHexLower())
        assertTrue(P256.isValidPoint(Vectors.macPub))
        assertTrue(P256.isValidPoint(Vectors.phonePub))
        assertEquals(Vectors.macPriv.toHexLower(), P256.rawFromPrivate(P256.privateKeyFromRaw(Vectors.macPriv)).toHexLower())
    }

    @Test fun `gecersiz egri noktasi reddedilir`() {
        val bad = Vectors.macPub.copyOf().also { it[64] = (it[64] + 1).toByte() }
        assertFalse(P256.isValidPoint(bad))
        assertThrows(PeerCryptoException::class.java) { P256.publicFromX963(bad) }
        assertFalse(P256.isValidPoint(Vectors.macPub.copyOf(64)))
    }

    @Test fun `ECDH iki yonde de belgedeki sirri verir`() {
        val a = P256.ecdh(P256.privateKeyFromRaw(Vectors.macPriv), P256.publicFromX963(Vectors.phonePub))
        val b = P256.ecdh(P256.privateKeyFromRaw(Vectors.phonePriv), P256.publicFromX963(Vectors.macPub))
        assertEquals(Vectors.SECRET, a.toHexLower())
        assertEquals(Vectors.SECRET, b.toHexLower())
    }

    @Test fun `anahtar turetme ve SAS belgedeki vektorle eslesir`() {
        val keys = PeerKdf.derive(hexToBytes(Vectors.SECRET), Vectors.macPub, Vectors.phonePub, Vectors.macNonce, Vectors.phoneNonce)
        assertEquals(Vectors.MAC_TO_PHONE, keys.macToPhone.toHexLower())
        assertEquals(Vectors.PHONE_TO_MAC, keys.phoneToMac.toHexLower())
        assertEquals("538801", keys.sas)
    }

    @Test fun `AES-GCM paketi belgedeki vektorle eslesir`() {
        val key = ByteArray(32) { it.toByte() }
        val plain = """{"id":1,"t":"ping"}""".toByteArray()
        assertEquals(19, plain.size)
        val packet = PeerAead.seal(key, 1, plain)
        assertEquals("00000000000000016ef4d69866ce01322c5a7303ced6539972bd6149d15d86aae12692f305fb8fdc1a15c0", packet.toHexLower())
        assertArrayEquals(plain, PeerAead.open(key, packet).second)
    }

    @Test fun `sayac artar tekrar ve bozuk paket reddedilir`() {
        val key = ByteArray(32) { it.toByte() }
        val sealer = PeerSealer(key)
        val opener = PeerOpener(key)
        val p1 = sealer.seal("bir".toByteArray())
        val p2 = sealer.seal("iki".toByteArray())
        assertEquals("bir", String(opener.open(p1)))
        assertThrows(PeerCryptoException::class.java) { opener.open(p1) }
        val tampered = p2.copyOf().also { it[10] = (it[10] + 1).toByte() }
        assertThrows(PeerCryptoException::class.java) { opener.open(tampered) }
        // dogrulanamayan paket sayaci ilerletmedi: asil paket hala kabul edilir
        assertEquals("iki", String(opener.open(p2)))
        assertThrows(PeerCryptoException::class.java) { opener.open(ByteArray(23)) }
    }

    @Test fun `uretilen anahtar ciftinin ozel ve acik kisimlari tutarli`() {
        val (priv, pub) = P256.generate()
        assertEquals(32, priv.size)
        assertEquals(65, pub.size)
        assertTrue(P256.isValidPoint(pub))
    }
}
