package com.btekosistem.android.peer

import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/** Yeniden baglanma bekleme suresi: 1, 2, 5, 10, 30 sn; sonra 30 sn'de bir sonsuza dek. Android'e bagimli degil. */
class ReconnectBackoff(private val stepsMs: LongArray = longArrayOf(1_000, 2_000, 5_000, 10_000, 30_000)) {
    private var index = 0

    /** Siradaki bekleme (ms); son adimda sabit kalir, asla pes etmez. */
    fun next(): Long {
        val d = stepsMs[minOf(index, stepsMs.size - 1)]
        if (index < stepsMs.size) index++
        return d
    }

    fun reset() { index = 0 }
}

/** Kopma nedeni (arayuzde tek satir). */
enum class MacReason {
    NOT_FOUND, REFUSED, TIMEOUT, LOST, HANDSHAKE,
    /** Mac'te aktif eslesme kodu var: telefon kodu girmeli. */
    PAIR_NEED_CODE,
    /** Girilen kod yanlis. */
    PAIR_WRONG,
    /** Mac 3 yanlis denemeden sonra kilitledi. */
    PAIR_LOCKED;

    companion object {
        fun from(e: Throwable): MacReason = when {
            e is SocketTimeoutException -> TIMEOUT
            e is ConnectException && e.message?.contains("refused", ignoreCase = true) == true -> REFUSED
            e is ConnectException || e is NoRouteToHostException || e is UnknownHostException -> NOT_FOUND
            else -> LOST
        }
    }
}
