package com.btekosistem.android.peer

/** Kanal protokolu hatasi: bozuk JSON, eksik alan, gecersiz cerceve. Olumcudur (baglanti kapanir). */
class PeerProtocolException(message: String) : Exception(message)

/** Bagimlilik gerektirmeyen kucuk JSON okuyucu/yazici. Yazarken anahtarlari siralar (belgedeki referans kodlayici gibi). */
object PeerJson {
    private const val MAX_DEPTH = 32

    fun parse(text: String): Any? {
        val p = Parser(text)
        val v = p.value(0)
        p.skipWs()
        if (!p.atEnd()) throw PeerProtocolException("json: fazla veri")
        return v
    }

    fun write(value: Any?): String {
        val sb = StringBuilder()
        put(sb, value)
        return sb.toString()
    }

    private fun put(sb: StringBuilder, v: Any?) {
        when (v) {
            null -> sb.append("null")
            is String -> quote(sb, v)
            is Boolean -> sb.append(if (v) "true" else "false")
            is Int, is Long, is Short, is Byte, is Double -> sb.append(v.toString())
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for (k in v.keys.map { it as String }.sorted()) {
                    if (!first) sb.append(',')
                    first = false
                    quote(sb, k)
                    sb.append(':')
                    put(sb, v[k])
                }
                sb.append('}')
            }
            is List<*> -> {
                sb.append('[')
                v.forEachIndexed { i, e ->
                    if (i > 0) sb.append(',')
                    put(sb, e)
                }
                sb.append(']')
            }
            else -> throw IllegalArgumentException("json: desteklenmeyen tur")
        }
    }

    private fun quote(sb: StringBuilder, s: String) {
        sb.append('"')
        for (ch in s) {
            when {
                ch == '"' -> sb.append("\\\"")
                ch == '\\' -> sb.append("\\\\")
                ch == '\n' -> sb.append("\\n")
                ch == '\r' -> sb.append("\\r")
                ch == '\t' -> sb.append("\\t")
                ch < ' ' -> sb.append("\\u%04x".format(ch.code))
                else -> sb.append(ch)
            }
        }
        sb.append('"')
    }

    private class Parser(val s: String) {
        var i = 0

        fun atEnd() = i >= s.length

        fun skipWs() {
            while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) i++
        }

        fun fail(): Nothing = throw PeerProtocolException("json: gecersiz")

        fun value(depth: Int): Any? {
            if (depth > MAX_DEPTH) fail()
            skipWs()
            if (atEnd()) fail()
            return when (s[i]) {
                '{' -> obj(depth)
                '[' -> arr(depth)
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> num()
            }
        }

        private fun lit(word: String, v: Any?): Any? {
            if (!s.startsWith(word, i)) fail()
            i += word.length
            return v
        }

        private fun obj(depth: Int): Map<String, Any?> {
            i++
            val m = LinkedHashMap<String, Any?>()
            skipWs()
            if (!atEnd() && s[i] == '}') { i++; return m }
            while (true) {
                skipWs()
                if (atEnd() || s[i] != '"') fail()
                val k = str()
                skipWs()
                if (atEnd() || s[i] != ':') fail()
                i++
                m[k] = value(depth + 1)
                skipWs()
                if (atEnd()) fail()
                if (s[i] == ',') { i++; continue }
                if (s[i] == '}') { i++; return m }
                fail()
            }
        }

        private fun arr(depth: Int): List<Any?> {
            i++
            val l = ArrayList<Any?>()
            skipWs()
            if (!atEnd() && s[i] == ']') { i++; return l }
            while (true) {
                l += value(depth + 1)
                skipWs()
                if (atEnd()) fail()
                if (s[i] == ',') { i++; continue }
                if (s[i] == ']') { i++; return l }
                fail()
            }
        }

        private fun str(): String {
            i++
            val sb = StringBuilder()
            while (true) {
                if (atEnd()) fail()
                val ch = s[i++]
                if (ch == '"') return sb.toString()
                if (ch == '\\') {
                    if (atEnd()) fail()
                    when (s[i++]) {
                        '"' -> sb.append('"')
                        '\\' -> sb.append('\\')
                        '/' -> sb.append('/')
                        'b' -> sb.append('\b')
                        'f' -> sb.append('\u000C')
                        'n' -> sb.append('\n')
                        'r' -> sb.append('\r')
                        't' -> sb.append('\t')
                        'u' -> {
                            if (i + 4 > s.length) fail()
                            val code = s.substring(i, i + 4).toIntOrNull(16) ?: fail()
                            i += 4
                            sb.append(code.toChar())
                        }
                        else -> fail()
                    }
                } else if (ch < ' ') {
                    fail()
                } else {
                    sb.append(ch)
                }
            }
        }

        private fun num(): Any {
            val st = i
            while (i < s.length && (s[i].isDigit() || s[i] == '+' || s[i] == '-' || s[i] == '.' || s[i] == 'e' || s[i] == 'E')) i++
            if (st == i) fail()
            val t = s.substring(st, i)
            return if (t.any { it == '.' || it == 'e' || it == 'E' }) (t.toDoubleOrNull() ?: fail()) else (t.toLongOrNull() ?: fail())
        }
    }
}
