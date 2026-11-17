package com.btekosistem.android.peer

import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.AlgorithmParameters
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

// docs/telefon-kanali.md bolum 3-5. Android'e bagimli degil (yalniz java.security / javax.crypto).

fun hexToBytes(hex: String): ByteArray {
    val h = hex.replace(" ", "")
    require(h.length % 2 == 0)
    return ByteArray(h.length / 2) { h.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}

fun ByteArray.toHexLower(): String = joinToString("") { "%02x".format(it.toInt() and 0xFF) }

class PeerCryptoException(message: String) : Exception(message)

/** P-256 yardimcilari: ham skalerden anahtar, X9.63 (04 || X || Y) serilestirme, ECDH. */
object P256 {
    private val P = BigInteger("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", 16)
    private val B = BigInteger("5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b", 16)

    val spec: ECParameterSpec by lazy {
        val ap = AlgorithmParameters.getInstance("EC")
        ap.init(ECGenParameterSpec("secp256r1"))
        ap.getParameterSpec(ECParameterSpec::class.java)
    }

    fun fixed32(v: BigInteger): ByteArray {
        val b = v.toByteArray()
        return when {
            b.size == 32 -> b
            b.size > 32 -> b.copyOfRange(b.size - 32, b.size)
            else -> ByteArray(32 - b.size) + b
        }
    }

    fun privateKeyFromRaw(raw: ByteArray): PrivateKey {
        require(raw.size == 32) { "ozel anahtar 32 bayt olmali" }
        return KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, raw), spec))
    }

    fun rawFromPrivate(key: PrivateKey): ByteArray = fixed32((key as ECPrivateKey).s)

    fun isValidPoint(b: ByteArray): Boolean {
        if (b.size != 65 || b[0].toInt() != 4) return false
        val x = BigInteger(1, b.copyOfRange(1, 33))
        val y = BigInteger(1, b.copyOfRange(33, 65))
        if (x >= P || y >= P) return false
        val lhs = y.multiply(y).mod(P)
        val rhs = x.pow(3).subtract(x.multiply(BigInteger.valueOf(3))).add(B).mod(P)
        return lhs == rhs
    }

    fun publicFromX963(b: ByteArray): PublicKey {
        if (!isValidPoint(b)) throw PeerCryptoException("gecersiz egri noktasi")
        val x = BigInteger(1, b.copyOfRange(1, 33))
        val y = BigInteger(1, b.copyOfRange(33, 65))
        return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(x, y), spec))
    }

    fun x963(pub: PublicKey): ByteArray {
        val w = (pub as ECPublicKey).w
        return byteArrayOf(4) + fixed32(w.affineX) + fixed32(w.affineY)
    }

    /** (ham ozel anahtar 32 bayt, X9.63 acik anahtar 65 bayt) */
    fun generate(): Pair<ByteArray, ByteArray> {
        val g = KeyPairGenerator.getInstance("EC")
        g.initialize(ECGenParameterSpec("secp256r1"))
        val kp = g.generateKeyPair()
        return rawFromPrivate(kp.private) to x963(kp.public)
    }

    /** 32 bayt x koordinati. */
    fun ecdh(priv: PrivateKey, pub: PublicKey): ByteArray {
        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(priv)
        ka.doPhase(pub, true)
        return ka.generateSecret()
    }
}

fun hmacSha256(key: ByteArray, vararg parts: ByteArray): ByteArray {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(if (key.isEmpty()) ByteArray(32) else key, "HmacSHA256"))
    for (p in parts) mac.update(p)
    return mac.doFinal()
}

/** RFC 5869. */
fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
    val prk = hmacSha256(salt, ikm)
    var t = ByteArray(0)
    var out = ByteArray(0)
    var i = 1
    while (out.size < length) {
        t = hmacSha256(prk, t, info, byteArrayOf(i.toByte()))
        out += t
        i++
    }
    return out.copyOf(length)
}

class SessionKeys(val macToPhone: ByteArray, val phoneToMac: ByteArray, val sas: String)

object PeerKdf {
    private val LABEL = "BTEKO1".toByteArray(Charsets.US_ASCII)
    private val INFO = "btekosistem/v1".toByteArray(Charsets.US_ASCII)

    fun derive(secret: ByteArray, macPub: ByteArray, phonePub: ByteArray, macNonce: ByteArray, phoneNonce: ByteArray): SessionKeys {
        val transcript = LABEL + macPub + phonePub + macNonce + phoneNonce
        val salt = MessageDigest.getInstance("SHA-256").digest(transcript)
        val okm = hkdfSha256(secret, salt, INFO, 68)
        val raw = ByteBuffer.wrap(okm, 64, 4).int.toLong() and 0xFFFFFFFFL
        return SessionKeys(okm.copyOfRange(0, 32), okm.copyOfRange(32, 64), (raw % 1_000_000L).toString().padStart(6, '0'))
    }
}

/** AES-256-GCM paketi: `sayac8 || sifreliMetin || etiket(16)`, nonce = 4 sifir bayt || sayac8, AAD = sayac8. */
object PeerAead {
    fun counterBytes(counter: Long): ByteArray = ByteBuffer.allocate(8).putLong(counter).array()

    fun seal(key: ByteArray, counter: Long, plain: ByteArray): ByteArray {
        val c8 = counterBytes(counter)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, ByteArray(4) + c8))
        cipher.updateAAD(c8)
        return c8 + cipher.doFinal(plain)
    }

    /** (sayac, acik metin). Etiket dogrulanamazsa PeerCryptoException. */
    fun open(key: ByteArray, packet: ByteArray): Pair<Long, ByteArray> {
        if (packet.size < 24) throw PeerCryptoException("paket kisa")
        val c8 = packet.copyOfRange(0, 8)
        val counter = ByteBuffer.wrap(c8).long
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, ByteArray(4) + c8))
            cipher.updateAAD(c8)
            return counter to cipher.doFinal(packet, 8, packet.size - 8)
        } catch (e: GeneralSecurityException) {
            throw PeerCryptoException("etiket dogrulanamadi")
        }
    }
}

class PeerSealer(private val key: ByteArray) {
    private var counter = 0L
    fun seal(plain: ByteArray): ByteArray {
        counter++
        return PeerAead.seal(key, counter, plain)
    }
}

class PeerOpener(private val key: ByteArray) {
    private var last = 0L

    /** Tekrar (sayac <= son) ve dogrulanamayan paket PeerCryptoException; basarisiz paket sayaci ilerletmez. */
    fun open(packet: ByteArray): ByteArray {
        if (packet.size < 24) throw PeerCryptoException("paket kisa")
        val counter = ByteBuffer.wrap(packet, 0, 8).long
        if (java.lang.Long.compareUnsigned(counter, last) <= 0) throw PeerCryptoException("tekrar")
        val (_, plain) = PeerAead.open(key, packet)
        last = counter
        return plain
    }
}
