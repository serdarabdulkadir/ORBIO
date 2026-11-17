package com.btekosistem.android.peer

import java.security.PrivateKey
import java.util.Base64

enum class PeerRole(val wire: String) { MAC("mac"), TELEFON("telefon") }

enum class CloseReason { PROTOCOL, VERSION, ROLE, KEY_CHANGED, CRYPTO, SAS_REJECTED, LOCAL, PAIR_REFUSED }

sealed interface PeerEvent {
    /** Karsiya yazilacak cerceveli bayt. */
    class Send(val bytes: ByteArray) : PeerEvent
    class SasRequired(val code: String) : PeerEvent
    /** Kullanici SAS'i onayladi: uygulama karsi anahtari kalici sabitlemeli. */
    class Paired(val peerPub: ByteArray, val peerName: String) : PeerEvent
    data object Ready : PeerEvent
    class Received(val message: PeerMessage) : PeerEvent
    class Closed(val reason: CloseReason) : PeerEvent
}

/**
 * Kanal durum makinesi (docs/telefon-kanali.md): bayt girer, cerceveli bayt ve olay cikar. Aga bagli degil, tek iplik kullanimli.
 * Zaman asimlarini (el sikisma 10 sn, SAS 60 sn, bosta 45 sn) cagiran uygular.
 */
class PeerSession(
    val role: PeerRole,
    private val ownPrivate: PrivateKey,
    private val ownPublic: ByteArray,
    private val ownName: String,
    private val pinnedPeer: ByteArray?,
    private val ownNonce: ByteArray,
    private val hello: PeerMessage.Hello,
    /** Mac'te "Telefonu esle" ile uretilen 6 haneli kod (yalniz ilk eslesmede); aga HMAC kaniti olarak cikar. */
    private val pairCode: String? = null,
) {
    enum class Phase { HANDSHAKE, AWAIT_SAS, READY, CLOSED }

    var phase = Phase.HANDSHAKE
        private set
    var peerName: String = ""
        private set

    /** Mac eslesmeyi reddederse nedeni: "eslesme_kapali", "kod_yanlis", "kilitli" (yoksa null). */
    var refusal: String? = null
        private set

    private val frames = PeerFrameBuffer()
    private var sealer: PeerSealer? = null
    private var opener: PeerOpener? = null
    private var peerPub: ByteArray? = null
    private val pending = ArrayList<PeerMessage>()
    private val b64 = Base64.getEncoder()

    fun start(): List<PeerEvent> {
        val hs = mapOf(
            "t" to "hs", "v" to 1, "rol" to role.wire,
            "pub" to b64.encodeToString(ownPublic), "nonce" to b64.encodeToString(ownNonce), "ad" to ownName,
        ).let { base ->
            if (role == PeerRole.TELEFON && pairCode != null) base + ("kod" to b64.encodeToString(pairProof(pairCode))) else base
        }
        return listOf(PeerEvent.Send(PeerFraming.encode(PeerJson.write(hs).toByteArray(Charsets.UTF_8))))
    }

    /** HMAC-SHA256(anahtar = kod UTF-8, mesaj = "btrack-pair-v1" || pub || nonce); Mac'teki PairingGate.proof ile ayni. */
    private fun pairProof(code: String): ByteArray {
        val mac = javax.crypto.Mac.getInstance("HmacSHA256")
        mac.init(javax.crypto.spec.SecretKeySpec(code.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        mac.update("btrack-pair-v1".toByteArray(Charsets.UTF_8))
        mac.update(ownPublic)
        mac.update(ownNonce)
        return mac.doFinal()
    }

    fun receive(bytes: ByteArray): List<PeerEvent> {
        if (phase == Phase.CLOSED) return emptyList()
        val events = ArrayList<PeerEvent>()
        val list = try {
            frames.append(bytes)
        } catch (e: PeerProtocolException) {
            close(CloseReason.PROTOCOL, events)
            return events
        }
        for (f in list) {
            if (phase == Phase.CLOSED) break
            if (phase == Phase.HANDSHAKE) onHandshake(f, events) else onEncrypted(f, events)
        }
        return events
    }

    fun confirmSas(accepted: Boolean): List<PeerEvent> {
        if (phase != Phase.AWAIT_SAS) return emptyList()
        val events = ArrayList<PeerEvent>()
        if (!accepted) {
            pending.clear()
            close(CloseReason.SAS_REJECTED, events)
            return events
        }
        events += PeerEvent.Paired(peerPub!!, peerName)
        ready(events)
        pending.forEach { events += PeerEvent.Received(it) }
        pending.clear()
        return events
    }

    fun send(message: PeerMessage): List<PeerEvent> {
        if (phase != Phase.READY) return emptyList()
        return listOf(encrypted(message))
    }

    fun close(): List<PeerEvent> {
        if (phase == Phase.CLOSED) return emptyList()
        val events = ArrayList<PeerEvent>()
        close(CloseReason.LOCAL, events)
        return events
    }

    private fun encrypted(m: PeerMessage): PeerEvent.Send =
        PeerEvent.Send(PeerFraming.encode(sealer!!.seal(PeerCodec.encode(m).toByteArray(Charsets.UTF_8))))

    private fun ready(events: MutableList<PeerEvent>) {
        phase = Phase.READY
        events += PeerEvent.Ready
        events += encrypted(hello)
    }

    private fun close(reason: CloseReason, events: MutableList<PeerEvent>) {
        phase = Phase.CLOSED
        events += PeerEvent.Closed(reason)
    }

    private fun onHandshake(frame: ByteArray, events: MutableList<PeerEvent>) {
        try {
            val m = PeerJson.parse(String(frame, Charsets.UTF_8)) as? Map<*, *>
            if (m != null && m["t"] == "hs_red") {
                refusal = m["neden"] as? String ?: "eslesme_kapali"
                return close(CloseReason.PAIR_REFUSED, events)
            }
            if (m == null || m["t"] != "hs") return close(CloseReason.PROTOCOL, events)
            val v = (m["v"] as? Number)?.toInt()
            if (v != 1) return close(CloseReason.VERSION, events)
            if (m["rol"] != (if (role == PeerRole.MAC) PeerRole.TELEFON else PeerRole.MAC).wire) return close(CloseReason.ROLE, events)
            val pub = Base64.getDecoder().decode(m["pub"] as? String ?: return close(CloseReason.PROTOCOL, events))
            val nonce = Base64.getDecoder().decode(m["nonce"] as? String ?: return close(CloseReason.PROTOCOL, events))
            if (nonce.size != 16 || !P256.isValidPoint(pub)) return close(CloseReason.PROTOCOL, events)
            if (pinnedPeer != null && !pinnedPeer.contentEquals(pub)) return close(CloseReason.KEY_CHANGED, events)

            peerPub = pub
            peerName = m["ad"] as? String ?: ""
            val secret = P256.ecdh(ownPrivate, P256.publicFromX963(pub))
            val keys = if (role == PeerRole.MAC) {
                PeerKdf.derive(secret, ownPublic, pub, ownNonce, nonce)
            } else {
                PeerKdf.derive(secret, pub, ownPublic, nonce, ownNonce)
            }
            if (role == PeerRole.MAC) {
                sealer = PeerSealer(keys.macToPhone); opener = PeerOpener(keys.phoneToMac)
            } else {
                sealer = PeerSealer(keys.phoneToMac); opener = PeerOpener(keys.macToPhone)
            }
            if (pinnedPeer != null) {
                ready(events)
            } else {
                phase = Phase.AWAIT_SAS
                events += PeerEvent.SasRequired(keys.sas)
            }
        } catch (e: PeerProtocolException) {
            close(CloseReason.PROTOCOL, events)
        } catch (e: IllegalArgumentException) {
            close(CloseReason.PROTOCOL, events)
        } catch (e: java.security.GeneralSecurityException) {
            close(CloseReason.CRYPTO, events)
        } catch (e: PeerCryptoException) {
            close(CloseReason.CRYPTO, events)
        }
    }

    private fun onEncrypted(frame: ByteArray, events: MutableList<PeerEvent>) {
        val plain = try {
            opener!!.open(frame)
        } catch (e: PeerCryptoException) {
            return close(CloseReason.CRYPTO, events)
        }
        val msg = try {
            PeerCodec.decode(String(plain, Charsets.UTF_8))
        } catch (e: PeerProtocolException) {
            return close(CloseReason.PROTOCOL, events)
        }
        if (phase == Phase.AWAIT_SAS) pending += msg else events += PeerEvent.Received(msg)
    }
}
