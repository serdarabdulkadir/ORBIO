package com.btekosistem.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

private val AYSE = PeerContactRecord("12", "Ayşe", listOf(PeerContactNumber("+905551112233", "cep")), true, listOf("Aile"), "AQID")

class PeerMessageTest {
    // Swift tarafi (PeerMessageTests.peerKisiSenkronuJSONOrnekleri) ile ayni dizgiler.
    @Test fun `kisi senkronu JSON ornekleri Swift ile birebir`() {
        assertEquals("""{"adet":40,"id":3,"ofset":80,"t":"contacts.sync"}""", PeerCodec.encode(PeerMessage.ContactsSync(80, 40, 3)))
        assertEquals("""{"ofset":0,"t":"contacts.sync"}""", PeerCodec.encode(PeerMessage.ContactsSync(0)))
        assertEquals(
            """{"id":3,"kisiler":[{"ad":"Ayşe","favori":true,"foto":"AQID","gruplar":["Aile"],"kid":"12","numaralar":[{"no":"+905551112233","tur":"cep"}]}],"ofset":0,"son":false,"t":"contacts.page","toplam":2}""",
            PeerCodec.encode(PeerMessage.ContactsPage(0, 2, false, listOf(AYSE), 3)),
        )
        assertEquals(
            """{"kayitlar":[{"kisiAdi":"Ayşe","numara":"+905551112233","sureSn":42,"yon":"gelen","zaman":1700000000}],"ofset":0,"son":true,"t":"calllog.page","toplam":1}""",
            PeerCodec.encode(PeerMessage.CallLogPage(0, 1, true, listOf(PeerCallLogEntry("+905551112233", "Ayşe", "gelen", 1700000000L, 42)))),
        )
        assertEquals("""{"t":"contacts.changed"}""", PeerCodec.encode(PeerMessage.ContactsChanged()))
        assertEquals("""{"t":"calllog.changed"}""", PeerCodec.encode(PeerMessage.CallLogChanged()))
        assertEquals(
            """{"kisiler":[{"ad":"A","favori":false,"gruplar":[],"kid":"1","numaralar":[]}],"ofset":0,"son":true,"t":"contacts.page","toplam":1}""",
            PeerCodec.encode(PeerMessage.ContactsPage(0, 1, true, listOf(PeerContactRecord("1", "A", emptyList(), false, emptyList())))),
        )
    }

    @Test fun `kisi sayfasinda eksik zorunlu alan olumcul`() {
        assertThrows(PeerProtocolException::class.java) { PeerCodec.decode("""{"t":"contacts.page","ofset":0,"toplam":1,"son":true,"kisiler":[{"kid":"1","ad":"A"}]}""") }
        assertThrows(PeerProtocolException::class.java) { PeerCodec.decode("""{"t":"contacts.sync"}""") }
    }

    @Test fun `belgedeki JSON ornekleri birebir uretilir`() {
        assertEquals("""{"id":2,"numara":"555","t":"call.dial"}""", PeerCodec.encode(PeerMessage.CallDial("555", 2)))
        assertEquals("""{"durum":"bosta","t":"call.state"}""", PeerCodec.encode(PeerMessage.CallState("bosta")))
        assertEquals(
            """{"aramaGecmisi":false,"cagriYonetimi":false,"kisiler":false,"t":"perm.state"}""",
            PeerCodec.encode(PeerMessage.PermState(false, false, false)),
        )
        assertEquals("""{"id":1,"t":"ping"}""", PeerCodec.encode(PeerMessage.Ping(1)))
    }

    @Test fun `tum mesajlar kodlanip geri cozulur`() {
        val all = listOf(
            PeerMessage.Hello("Pixel", "0.2.0", 1, "uuid", "android", 1),
            PeerMessage.Pong(5),
            PeerMessage.PhoneState("Pixel", "Pixel 8", 64, true, 3, "wifi"),
            PeerMessage.CallState("caliyor", "gelen", "+90555", "Ayşe \"A\"", 12),
            PeerMessage.CallAnswer(), PeerMessage.CallReject(3), PeerMessage.CallHangup(),
            PeerMessage.ContactsSearch("ay", 7),
            PeerMessage.ContactsResult(listOf(PeerContact("Ayşe", listOf("1", "2"))), 7),
            PeerMessage.CallLogRecent(5, 8), PeerMessage.CallLogRecent(null, 9),
            PeerMessage.CallLogResult(listOf(PeerCallLogEntry("1", null, "gelen", 1700000000L, 30), PeerCallLogEntry("2", "B", "cevapsiz", 5L, 0)), 8),
            PeerMessage.ContactsSync(80, 40, 3), PeerMessage.ContactsSync(0),
            PeerMessage.ContactsPage(0, 2, false, listOf(AYSE, PeerContactRecord("2", "B", emptyList(), false, emptyList())), 3),
            PeerMessage.ContactsChanged(),
            PeerMessage.CallLogSync(0, 100, 4), PeerMessage.CallLogPage(0, 1, true, listOf(PeerCallLogEntry("+905551112233", "Ayşe", "gelen", 1700000000L, 42)), 4),
            PeerMessage.CallLogChanged(),
            PeerMessage.EarbudState("AA:BB", "QCY", "telefon"),
            PeerMessage.EarbudRelease("AA:BB", 4), PeerMessage.EarbudReleaseResult("desteklenmiyor", "AA:BB", 4),
            PeerMessage.EarbudConnect("AA:BB"), PeerMessage.EarbudConnectResult("tamam"),
            PeerMessage.PermState(true, false, true),
            PeerMessage.CtlOwner("84:AC:60:20:9D:3A", true), PeerMessage.CtlWrite("84:AC:60:20:9D:3A", "ff03fe0117"),
            PeerMessage.CtlNotify("84:AC:60:20:9D:3A", "yanit", "ff0417"),
            PeerMessage.Err("izin_yok", "kisiler", 7),
        )
        for (m in all) assertEquals(m, PeerCodec.decode(PeerCodec.encode(m)))
    }

    @Test fun `bilinmeyen tip olumcul degil bilinmeyen alanlar yok sayilir`() {
        assertEquals(PeerMessage.Unknown("x.y", 3), PeerCodec.decode("""{"t":"x.y","id":3,"ek":[1,2]}"""))
        assertEquals(PeerMessage.Ping(null), PeerCodec.decode("""{"t":"ping","fazla":true}"""))
    }

    @Test fun `eksik zorunlu alan ve bozuk JSON olumculdur`() {
        assertThrows(PeerProtocolException::class.java) { PeerCodec.decode("""{"t":"call.dial"}""") }
        assertThrows(PeerProtocolException::class.java) { PeerCodec.decode("""{"id":1}""") }
        assertThrows(PeerProtocolException::class.java) { PeerCodec.decode("{bozuk") }
        assertThrows(PeerProtocolException::class.java) { PeerCodec.decode("[1,2]") }
        assertThrows(PeerProtocolException::class.java) { PeerCodec.decode("""{"t":"ping"} x""") }
    }

    @Test fun `kacis dizileri ve unicode`() {
        val m = PeerCodec.decode("""{"t":"contacts.search","sorgu":"aç\n\"b"}""") as PeerMessage.ContactsSearch
        assertEquals("aç\n\"b", m.sorgu)
        assertTrue(PeerCodec.encode(m).contains("\\n"))
    }

    @Test fun `arama numarasi normallestirme`() {
        assertEquals("+905321234512", normalizeDialNumber("+90 (532) 123-4512"))
        assertEquals(null, normalizeDialNumber("ayse"))
        assertEquals(null, normalizeDialNumber(""))
        assertEquals("*123#", normalizeDialNumber("*123#"))
    }

    @Test fun `ctl mesajlari sabit JSON dizgileri`() {
        val a = "AA:BB:CC:DD:EE:FF"
        assertEquals("""{"cihazAdresi":"AA:BB:CC:DD:EE:FF","sahip":true,"t":"ctl.owner"}""", PeerCodec.encode(PeerMessage.CtlOwner(a, true)))
        assertEquals("""{"bayt":"ff03fe0117","cihazAdresi":"AA:BB:CC:DD:EE:FF","t":"ctl.write"}""", PeerCodec.encode(PeerMessage.CtlWrite(a, "ff03fe0117")))
        assertEquals("""{"bayt":"0301","cihazAdresi":"AA:BB:CC:DD:EE:FF","kar":"000d","t":"ctl.write"}""", PeerCodec.encode(PeerMessage.CtlWrite(a, "0301", "000d")))
        assertEquals(PeerMessage.CtlWrite(a, "0301", "000d"), PeerCodec.decode("""{"bayt":"0301","cihazAdresi":"AA:BB:CC:DD:EE:FF","kar":"000d","t":"ctl.write"}"""))
        assertEquals(PeerMessage.CtlWrite(a, "ff03"), PeerCodec.decode("""{"bayt":"ff03","cihazAdresi":"AA:BB:CC:DD:EE:FF","t":"ctl.write"}"""))
        assertEquals("""{"bayt":"1c52","cihazAdresi":"AA:BB:CC:DD:EE:FF","t":"ctl.notify","tur":"reklam"}""", PeerCodec.encode(PeerMessage.CtlNotify(a, "reklam", "1c52")))
        assertEquals(PeerMessage.CtlOwner("AA:BB", false), PeerCodec.decode("""{"t":"ctl.owner","cihazAdresi":"AA:BB","sahip":false}"""))
        assertThrows(PeerProtocolException::class.java) { PeerCodec.decode("""{"t":"ctl.write","cihazAdresi":"AA:BB"}""") }
    }
}
