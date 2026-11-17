package com.btekosistem.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MediaBridgeTest {
    // Swift tarafi (PeerMessageTests.peerMediaJSONBelgeylePirebir) ile ayni dizgiler.
    @Test fun `media JSON ornekleri Swift ile birebir`() {
        assertEquals("""{"caliyor":false,"oturum":false,"t":"media.state"}""", PeerCodec.encode(PeerMessage.MediaState(false, false)))
        assertEquals(
            """{"baslik":"Sarki","caliyor":true,"oturum":true,"sanatci":"Ali","t":"media.state","uygulama":"Spotify"}""",
            PeerCodec.encode(PeerMessage.MediaState(true, true, "Spotify", "Sarki", "Ali")),
        )
        assertEquals("""{"komut":"oynat_duraklat","t":"media.cmd"}""", PeerCodec.encode(PeerMessage.MediaCommand("oynat_duraklat")))
    }

    @Test fun `media mesajlari geri okunur`() {
        val s = PeerMessage.MediaState(true, true, "Spotify", "Sarki", "Ali")
        assertEquals(s, PeerCodec.decode(PeerCodec.encode(s)))
        assertEquals(PeerMessage.MediaCommand("sonraki"), PeerCodec.decode("""{"komut":"sonraki","t":"media.cmd"}"""))
    }

    @Test fun `komut eslemesi`() {
        assertEquals(listOf("oynat_duraklat", "oynat", "duraklat", "sonraki", "onceki"), MediaCmd.entries.map { it.wire })
        MediaCmd.entries.forEach { assertEquals(it, MediaCmd.fromWire(it.wire)) }
        assertNull(MediaCmd.fromWire("bilinmeyen"))
    }

    @Test fun `oturum secimi calani one alir`() {
        assertEquals(-1, pickSessionIndex(emptyList()))
        assertEquals(0, pickSessionIndex(listOf(false, false)))
        assertEquals(1, pickSessionIndex(listOf(false, true)))
    }

    @Test fun `oturum yoksa durum mesaji`() {
        assertEquals(PeerMessage.MediaState(false, false), LocalMedia().toMessage())
        assertEquals(PeerMessage.MediaState(true, true, "A", "B", "C"), LocalMedia(true, true, "A", "B", "C").toMessage())
    }
}
