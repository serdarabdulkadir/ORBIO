package com.btekosistem.android.peer

import java.nio.ByteBuffer

/** Cerceve: `uzunluk (4 bayt, big-endian, imzasiz) || yuk`; yuk 1..1 048 576 bayt. */
object PeerFraming {
    const val MAX_PAYLOAD = 1_048_576

    fun encode(payload: ByteArray): ByteArray {
        require(payload.size in 1..MAX_PAYLOAD) { "yuk uzunlugu gecersiz" }
        return ByteBuffer.allocate(4 + payload.size).putInt(payload.size).put(payload).array()
    }
}

/** TCP akisi parcali gelebilir: tam cerceve olana dek tamponlar. Gecersiz uzunlukta PeerProtocolException. */
class PeerFrameBuffer {
    private var buf = ByteArray(0)

    fun append(data: ByteArray): List<ByteArray> {
        buf += data
        val out = ArrayList<ByteArray>()
        while (buf.size >= 4) {
            val n = ByteBuffer.wrap(buf, 0, 4).int.toLong() and 0xFFFFFFFFL
            if (n < 1 || n > PeerFraming.MAX_PAYLOAD) throw PeerProtocolException("cerceve uzunlugu gecersiz")
            if (buf.size < 4 + n) break
            out += buf.copyOfRange(4, 4 + n.toInt())
            buf = buf.copyOfRange(4 + n.toInt(), buf.size)
        }
        return out
    }
}
