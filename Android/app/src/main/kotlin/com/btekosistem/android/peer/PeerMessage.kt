package com.btekosistem.android.peer

data class PeerContact(val ad: String, val numaralar: List<String>)

/** `tur`: cep / ev / is / diger. */
data class PeerContactNumber(val no: String, val tur: String)

/** Tam rehber kaydi. `foto`: kucuk JPEG, standart base64 (opsiyonel). */
data class PeerContactRecord(
    val kid: String, val ad: String, val numaralar: List<PeerContactNumber>,
    val favori: Boolean, val gruplar: List<String>, val foto: String? = null,
)

/** `yon`: gelen / giden / cevapsiz. `zaman`: epoch saniye. */
data class PeerCallLogEntry(val numara: String, val kisiAdi: String?, val yon: String, val zaman: Long, val sureSn: Int)

/** docs/telefon-kanali.md bolum 7. Alan adlari belgedeki gibi (Turkce, ASCII). */
sealed class PeerMessage {
    abstract val id: Long?

    data class Hello(
        val ad: String, val surum: String, val protokol: Int, val cihazId: String, val platform: String,
        override val id: Long? = null,
    ) : PeerMessage()

    data class Ping(override val id: Long? = null) : PeerMessage()
    data class Pong(override val id: Long? = null) : PeerMessage()

    data class PhoneState(
        val ad: String, val model: String, val pil: Int, val sarj: Boolean, val sinyal: Int, val ag: String,
        override val id: Long? = null,
    ) : PeerMessage()

    data class CallState(
        val durum: String, val yon: String? = null, val numara: String? = null, val kisiAdi: String? = null,
        val sureSn: Int? = null, override val id: Long? = null,
    ) : PeerMessage()

    data class CallAnswer(override val id: Long? = null) : PeerMessage()
    data class CallReject(override val id: Long? = null) : PeerMessage()
    data class CallHangup(override val id: Long? = null) : PeerMessage()
    data class CallDial(val numara: String, override val id: Long? = null) : PeerMessage()

    data class ContactsSearch(val sorgu: String, override val id: Long? = null) : PeerMessage()
    data class ContactsResult(val kisiler: List<PeerContact>, override val id: Long? = null) : PeerMessage()

    data class CallLogRecent(val adet: Int? = null, override val id: Long? = null) : PeerMessage()
    data class CallLogResult(val kayitlar: List<PeerCallLogEntry>, override val id: Long? = null) : PeerMessage()

    data class ContactsSync(val ofset: Int, val adet: Int? = null, override val id: Long? = null) : PeerMessage()
    data class ContactsPage(
        val ofset: Int, val toplam: Int, val son: Boolean, val kisiler: List<PeerContactRecord>,
        override val id: Long? = null,
    ) : PeerMessage()
    data class ContactsChanged(override val id: Long? = null) : PeerMessage()

    data class CallLogSync(val ofset: Int, val adet: Int? = null, override val id: Long? = null) : PeerMessage()
    data class CallLogPage(
        val ofset: Int, val toplam: Int, val son: Boolean, val kayitlar: List<PeerCallLogEntry>,
        override val id: Long? = null,
    ) : PeerMessage()
    data class CallLogChanged(override val id: Long? = null) : PeerMessage()

    data class EarbudState(val cihazId: String, val ad: String, val baglanti: String, override val id: Long? = null) : PeerMessage()
    data class EarbudRelease(val cihazAdresi: String, override val id: Long? = null) : PeerMessage()
    data class EarbudReleaseResult(val sonuc: String, val cihazAdresi: String? = null, override val id: Long? = null) : PeerMessage()
    data class EarbudConnect(val cihazAdresi: String, override val id: Long? = null) : PeerMessage()
    data class EarbudConnectResult(val sonuc: String, val cihazAdresi: String? = null, override val id: Long? = null) : PeerMessage()

    /** Bu taraf o kulakligin BLE kontrol kanalini tutuyor mu (iki yon). `cihazAdresi`: buyuk harf klasik adres. */
    data class CtlOwner(val cihazAdresi: String, val sahip: Boolean, override val id: Long? = null) : PeerMessage()
    /** Sahip olmayan -> sahip. `bayt`: QCY paketi, kucuk harf hex. */
    data class CtlWrite(val cihazAdresi: String, val bayt: String, val kar: String? = null, override val id: Long? = null) : PeerMessage()
    /** Sahip -> diger. `tur`: "yanit" | "reklam". */
    data class CtlNotify(val cihazAdresi: String, val tur: String, val bayt: String, override val id: Long? = null) : PeerMessage()

    data class PermState(
        val cagriYonetimi: Boolean, val kisiler: Boolean, val aramaGecmisi: Boolean,
        override val id: Long? = null,
    ) : PeerMessage()

    /** `media.state` (tel->mac): telefondaki medya oturumu. Opsiyonel alan null ise JSON'a yazilmaz. */
    data class MediaState(
        val caliyor: Boolean, val oturum: Boolean, val uygulama: String? = null, val baslik: String? = null, val sanatci: String? = null,
        override val id: Long? = null,
    ) : PeerMessage()

    /** `media.cmd` (iki yon): komut = MediaCmd.wire. */
    data class MediaCommand(val komut: String, override val id: Long? = null) : PeerMessage()

    /** `vol.state` (iki yon): cihaz = "mac" | "telefon"; seviye 0..100. */
    data class VolState(val cihaz: String, val seviye: Int, val sessiz: Boolean, override val id: Long? = null) : PeerMessage()

    /** `vol.set` (iki yon): hedef = "mac" | "telefon"; opsiyonel alan null ise JSON'a yazilmaz. */
    data class VolSet(val hedef: String, val seviye: Int? = null, val sessiz: Boolean? = null, override val id: Long? = null) : PeerMessage()

    data class Err(val kod: String, val mesaj: String, override val id: Long? = null) : PeerMessage()

    /** Taninmayan `t`: olumcul degil, `error` {bilinmeyen_tip} ile yanitlanir. */
    data class Unknown(val type: String, override val id: Long? = null) : PeerMessage()
}

object PeerCodec {
    fun encode(m: PeerMessage): String = PeerJson.write(toMap(m))

    fun toMap(m: PeerMessage): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["t"] = typeOf(m)
        m.id?.let { out["id"] = it }
        fun put(k: String, v: Any?) { if (v != null) out[k] = v }
        when (m) {
            is PeerMessage.Hello -> { put("ad", m.ad); put("surum", m.surum); put("protokol", m.protokol); put("cihazId", m.cihazId); put("platform", m.platform) }
            is PeerMessage.Ping, is PeerMessage.Pong, is PeerMessage.CallAnswer, is PeerMessage.CallReject, is PeerMessage.CallHangup,
            is PeerMessage.ContactsChanged, is PeerMessage.CallLogChanged -> {}
            is PeerMessage.PhoneState -> { put("ad", m.ad); put("model", m.model); put("pil", m.pil); put("sarj", m.sarj); put("sinyal", m.sinyal); put("ag", m.ag) }
            is PeerMessage.CallState -> { put("durum", m.durum); put("yon", m.yon); put("numara", m.numara); put("kisiAdi", m.kisiAdi); put("sureSn", m.sureSn) }
            is PeerMessage.CallDial -> put("numara", m.numara)
            is PeerMessage.ContactsSearch -> put("sorgu", m.sorgu)
            is PeerMessage.ContactsResult -> put("kisiler", m.kisiler.map { mapOf("ad" to it.ad, "numaralar" to it.numaralar) })
            is PeerMessage.CallLogRecent -> put("adet", m.adet)
            is PeerMessage.CallLogResult -> put("kayitlar", m.kayitlar.map { logMap(it) })
            is PeerMessage.ContactsSync -> { put("ofset", m.ofset); put("adet", m.adet) }
            is PeerMessage.ContactsPage -> {
                put("ofset", m.ofset); put("toplam", m.toplam); put("son", m.son)
                put("kisiler", m.kisiler.map { recordMap(it) })
            }
            is PeerMessage.CallLogSync -> { put("ofset", m.ofset); put("adet", m.adet) }
            is PeerMessage.CallLogPage -> {
                put("ofset", m.ofset); put("toplam", m.toplam); put("son", m.son)
                put("kayitlar", m.kayitlar.map { logMap(it) })
            }
            is PeerMessage.EarbudState -> { put("cihazId", m.cihazId); put("ad", m.ad); put("baglanti", m.baglanti) }
            is PeerMessage.EarbudRelease -> put("cihazAdresi", m.cihazAdresi)
            is PeerMessage.EarbudConnect -> put("cihazAdresi", m.cihazAdresi)
            is PeerMessage.EarbudReleaseResult -> { put("sonuc", m.sonuc); put("cihazAdresi", m.cihazAdresi) }
            is PeerMessage.EarbudConnectResult -> { put("sonuc", m.sonuc); put("cihazAdresi", m.cihazAdresi) }
            is PeerMessage.CtlOwner -> { put("cihazAdresi", m.cihazAdresi); put("sahip", m.sahip) }
            is PeerMessage.CtlWrite -> { put("cihazAdresi", m.cihazAdresi); put("bayt", m.bayt); put("kar", m.kar) }
            is PeerMessage.CtlNotify -> { put("cihazAdresi", m.cihazAdresi); put("tur", m.tur); put("bayt", m.bayt) }
            is PeerMessage.PermState -> { put("cagriYonetimi", m.cagriYonetimi); put("kisiler", m.kisiler); put("aramaGecmisi", m.aramaGecmisi) }
            is PeerMessage.MediaState -> { put("caliyor", m.caliyor); put("oturum", m.oturum); put("uygulama", m.uygulama); put("baslik", m.baslik); put("sanatci", m.sanatci) }
            is PeerMessage.MediaCommand -> put("komut", m.komut)
            is PeerMessage.VolState -> { put("cihaz", m.cihaz); put("seviye", m.seviye); put("sessiz", m.sessiz) }
            is PeerMessage.VolSet -> { put("hedef", m.hedef); put("seviye", m.seviye); put("sessiz", m.sessiz) }
            is PeerMessage.Err -> { put("kod", m.kod); put("mesaj", m.mesaj) }
            is PeerMessage.Unknown -> {}
        }
        return out
    }

    private fun logMap(it: PeerCallLogEntry): Map<String, Any?> {
        val e = HashMap<String, Any?>()
        e["numara"] = it.numara
        it.kisiAdi?.let { n -> e["kisiAdi"] = n }
        e["yon"] = it.yon; e["zaman"] = it.zaman; e["sureSn"] = it.sureSn
        return e
    }

    private fun recordMap(r: PeerContactRecord): Map<String, Any?> {
        val e = HashMap<String, Any?>()
        e["kid"] = r.kid; e["ad"] = r.ad; e["favori"] = r.favori; e["gruplar"] = r.gruplar
        e["numaralar"] = r.numaralar.map { mapOf("no" to it.no, "tur" to it.tur) }
        r.foto?.let { e["foto"] = it }
        return e
    }

    private fun typeOf(m: PeerMessage): String = when (m) {
        is PeerMessage.Hello -> "hello"
        is PeerMessage.Ping -> "ping"
        is PeerMessage.Pong -> "pong"
        is PeerMessage.PhoneState -> "phone.state"
        is PeerMessage.CallState -> "call.state"
        is PeerMessage.CallAnswer -> "call.answer"
        is PeerMessage.CallReject -> "call.reject"
        is PeerMessage.CallHangup -> "call.hangup"
        is PeerMessage.CallDial -> "call.dial"
        is PeerMessage.ContactsSearch -> "contacts.search"
        is PeerMessage.ContactsResult -> "contacts.result"
        is PeerMessage.CallLogRecent -> "calllog.recent"
        is PeerMessage.CallLogResult -> "calllog.result"
        is PeerMessage.ContactsSync -> "contacts.sync"
        is PeerMessage.ContactsPage -> "contacts.page"
        is PeerMessage.ContactsChanged -> "contacts.changed"
        is PeerMessage.CallLogSync -> "calllog.sync"
        is PeerMessage.CallLogPage -> "calllog.page"
        is PeerMessage.CallLogChanged -> "calllog.changed"
        is PeerMessage.EarbudState -> "earbud.state"
        is PeerMessage.EarbudRelease -> "earbud.release"
        is PeerMessage.EarbudReleaseResult -> "earbud.release.result"
        is PeerMessage.EarbudConnect -> "earbud.connect"
        is PeerMessage.EarbudConnectResult -> "earbud.connect.result"
        is PeerMessage.CtlOwner -> "ctl.owner"
        is PeerMessage.CtlWrite -> "ctl.write"
        is PeerMessage.CtlNotify -> "ctl.notify"
        is PeerMessage.PermState -> "perm.state"
        is PeerMessage.MediaState -> "media.state"
        is PeerMessage.MediaCommand -> "media.cmd"
        is PeerMessage.VolState -> "vol.state"
        is PeerMessage.VolSet -> "vol.set"
        is PeerMessage.Err -> "error"
        is PeerMessage.Unknown -> m.type
    }

    /** Bozuk JSON ya da eksik zorunlu alan: PeerProtocolException. Bilinmeyen `t`: Unknown. */
    fun decode(text: String): PeerMessage {
        val root = PeerJson.parse(text) as? Map<*, *> ?: throw PeerProtocolException("mesaj nesne degil")
        val o = Fields(root)
        val t = o.str("t")
        val id = o.longOpt("id")
        return when (t) {
            "hello" -> PeerMessage.Hello(o.str("ad"), o.strOrNumber("surum"), o.int("protokol"), o.str("cihazId"), o.str("platform"), id)
            "ping" -> PeerMessage.Ping(id)
            "pong" -> PeerMessage.Pong(id)
            "phone.state" -> PeerMessage.PhoneState(o.str("ad"), o.str("model"), o.int("pil"), o.bool("sarj"), o.int("sinyal"), o.str("ag"), id)
            "call.state" -> PeerMessage.CallState(o.str("durum"), o.strOpt("yon"), o.strOpt("numara"), o.strOpt("kisiAdi"), o.intOpt("sureSn"), id)
            "call.answer" -> PeerMessage.CallAnswer(id)
            "call.reject" -> PeerMessage.CallReject(id)
            "call.hangup" -> PeerMessage.CallHangup(id)
            "call.dial" -> PeerMessage.CallDial(o.str("numara"), id)
            "contacts.search" -> PeerMessage.ContactsSearch(o.str("sorgu"), id)
            "contacts.result" -> PeerMessage.ContactsResult(
                o.list("kisiler").map {
                    val f = Fields(it as? Map<*, *> ?: throw PeerProtocolException("kisi nesne degil"))
                    PeerContact(f.str("ad"), f.list("numaralar").map { n -> n as? String ?: throw PeerProtocolException("numara metin degil") })
                },
                id,
            )
            "calllog.recent" -> PeerMessage.CallLogRecent(o.intOpt("adet"), id)
            "calllog.result" -> PeerMessage.CallLogResult(o.list("kayitlar").map { parseLog(it) }, id)
            "contacts.sync" -> PeerMessage.ContactsSync(o.int("ofset"), o.intOpt("adet"), id)
            "contacts.page" -> PeerMessage.ContactsPage(o.int("ofset"), o.int("toplam"), o.bool("son"), o.list("kisiler").map { parseRecord(it) }, id)
            "contacts.changed" -> PeerMessage.ContactsChanged(id)
            "calllog.sync" -> PeerMessage.CallLogSync(o.int("ofset"), o.intOpt("adet"), id)
            "calllog.page" -> PeerMessage.CallLogPage(o.int("ofset"), o.int("toplam"), o.bool("son"), o.list("kayitlar").map { parseLog(it) }, id)
            "calllog.changed" -> PeerMessage.CallLogChanged(id)
            "earbud.state" -> PeerMessage.EarbudState(o.str("cihazId"), o.str("ad"), o.str("baglanti"), id)
            "earbud.release" -> PeerMessage.EarbudRelease(o.str("cihazAdresi"), id)
            "earbud.release.result" -> PeerMessage.EarbudReleaseResult(o.str("sonuc"), o.strOpt("cihazAdresi"), id)
            "earbud.connect" -> PeerMessage.EarbudConnect(o.str("cihazAdresi"), id)
            "earbud.connect.result" -> PeerMessage.EarbudConnectResult(o.str("sonuc"), o.strOpt("cihazAdresi"), id)
            "ctl.owner" -> PeerMessage.CtlOwner(o.str("cihazAdresi"), o.bool("sahip"), id)
            "ctl.write" -> PeerMessage.CtlWrite(o.str("cihazAdresi"), o.str("bayt"), o.strOpt("kar"), id)
            "ctl.notify" -> PeerMessage.CtlNotify(o.str("cihazAdresi"), o.str("tur"), o.str("bayt"), id)
            "perm.state" -> PeerMessage.PermState(o.bool("cagriYonetimi"), o.bool("kisiler"), o.bool("aramaGecmisi"), id)
            "media.state" -> PeerMessage.MediaState(o.bool("caliyor"), o.bool("oturum"), o.strOpt("uygulama"), o.strOpt("baslik"), o.strOpt("sanatci"), id)
            "media.cmd" -> PeerMessage.MediaCommand(o.str("komut"), id)
            "vol.state" -> PeerMessage.VolState(o.str("cihaz"), o.int("seviye").coerceIn(0, 100), o.bool("sessiz"), id)
            "vol.set" -> PeerMessage.VolSet(o.str("hedef"), o.intOpt("seviye")?.coerceIn(0, 100), o.boolOpt("sessiz"), id)
            "error" -> PeerMessage.Err(o.str("kod"), o.strOpt("mesaj") ?: "", id)
            else -> PeerMessage.Unknown(t, id)
        }
    }

    private fun parseLog(it: Any?): PeerCallLogEntry {
        val f = Fields(it as? Map<*, *> ?: throw PeerProtocolException("kayit nesne degil"))
        return PeerCallLogEntry(f.str("numara"), f.strOpt("kisiAdi"), f.str("yon"), f.long("zaman"), f.int("sureSn"))
    }

    private fun parseRecord(it: Any?): PeerContactRecord {
        val f = Fields(it as? Map<*, *> ?: throw PeerProtocolException("kisi nesne degil"))
        return PeerContactRecord(
            f.str("kid"), f.str("ad"),
            f.list("numaralar").map { n ->
                val nf = Fields(n as? Map<*, *> ?: throw PeerProtocolException("numara nesne degil"))
                PeerContactNumber(nf.str("no"), nf.str("tur"))
            },
            f.bool("favori"),
            f.list("gruplar").map { g -> g as? String ?: throw PeerProtocolException("grup metin degil") },
            f.strOpt("foto"),
        )
    }

    private class Fields(val m: Map<*, *>) {
        fun str(k: String): String = m[k] as? String ?: throw PeerProtocolException("eksik alan: $k")
        fun strOpt(k: String): String? = m[k] as? String
        fun strOrNumber(k: String): String = when (val v = m[k]) {
            is String -> v
            is Number -> v.toString()
            else -> throw PeerProtocolException("eksik alan: $k")
        }
        fun long(k: String): Long = (m[k] as? Number)?.toLong() ?: throw PeerProtocolException("eksik alan: $k")
        fun longOpt(k: String): Long? = (m[k] as? Number)?.toLong()
        fun int(k: String): Int = long(k).toInt()
        fun intOpt(k: String): Int? = longOpt(k)?.toInt()
        fun bool(k: String): Boolean = m[k] as? Boolean ?: throw PeerProtocolException("eksik alan: $k")
        fun boolOpt(k: String): Boolean? = m[k] as? Boolean
        fun list(k: String): List<*> = m[k] as? List<*> ?: throw PeerProtocolException("eksik alan: $k")
    }
}
