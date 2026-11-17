package com.btekosistem.android.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QcyAdvertisementTest {
    private val raw = bytesOf(
        0x1C, 0x52, 0x4D, 0x4A, 0xEA, 0x00, 0x6E, 0x64, 0x5F, 0x00, 0x85, 0xB8, 0x7C, 0xAC,
        0x84, 0x60, 0x3A, 0x9D, 0x20, 0x00, 0xAC, 0x84, 0x60, 0x59, 0xA2, 0x21,
    )

    @Test fun `test vektoru ham paketten cozulur`() {
        val a = QcyAdvertisement.parseRaw(raw)!!
        assertEquals(100, a.left)
        assertEquals(95, a.right)
        assertNull(a.caseLevel)
        assertFalse(a.leftCharging || a.rightCharging || a.caseCharging)
        assertEquals("84:AC:60:20:9D:3A", a.controlAddress)
    }

    @Test fun `sirket kimligi ayrilmis veri ayni sonucu verir`() {
        assertEquals(QcyAdvertisement.parseRaw(raw), QcyAdvertisement.parse(raw.copyOfRange(2, raw.size)))
    }

    @Test fun `yanlis sirket kimligi ve kisa veri reddedilir`() {
        assertNull(QcyAdvertisement.parseRaw(bytesOf(0x4C, 0x00) + raw.copyOfRange(2, raw.size)))
        assertNull(QcyAdvertisement.parse(ByteArray(7)))
    }

    @Test fun `bit7 sarj bayragi ve seviye ayrilir`() {
        val d = ByteArray(8)
        d[5] = (0x80 or 14).toByte(); d[6] = 20; d[7] = (0x80 or 100).toByte()
        val a = QcyAdvertisement.parse(d)!!
        assertEquals(14, a.left); assertTrue(a.leftCharging)
        assertEquals(20, a.right); assertFalse(a.rightCharging)
        assertEquals(100, a.caseLevel); assertTrue(a.caseCharging)
        assertNull(a.controlAddress)
    }

    @Test fun `seviye 100u asmaz ve sifir adres yok sayilir`() {
        val d = ByteArray(17); d[5] = 0x7F
        val a = QcyAdvertisement.parse(d)!!
        assertEquals(100, a.left)
        assertNull(a.controlAddress)
    }
}

class QcyPacketTest {
    @Test fun `cerceveleme`() {
        assertArrayEquals(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x02, 0x00, 0x00), QcyNoise.setMode(ListeningMode.KAPALI))
    }

    @Test fun `okuma istegi`() {
        assertArrayEquals(bytesOf(0xFF, 0x03, 0xFE, 0x01, 0x17), QcyPacket.request(0x17))
        assertArrayEquals(bytesOf(0xFF, 0x03, 0xFE, 0x01, 0x2C), QcyPacket.request(0x2C))
    }

    @Test fun `yanit ayristirma`() {
        val blocks = QcyPacket.parse(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x01, 0x05, 0x00))
        assertEquals(listOf(QcyBlock(0x17, bytesOf(0x01, 0x05, 0x00))), blocks)
    }

    @Test fun `bozuk paketler bos doner`() {
        assertTrue(QcyPacket.parse(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x01)).isEmpty())
        assertTrue(QcyPacket.parse(bytesOf(0xAA, 0x03, 0x17, 0x01, 0x01)).isEmpty())
        assertTrue(QcyPacket.parse(bytesOf(0xFF, 0x04, 0x17, 0x05, 0x01, 0x01)).isEmpty())
        assertTrue(QcyPacket.parse(ByteArray(0)).isEmpty())
    }
}

class QcyNoiseTest {
    @Test fun `ses modu paketleri`() {
        assertArrayEquals(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x01, 0x05, 0x00), QcyNoise.setMode(ListeningMode.GURULTU_ENGELLEME))
        assertArrayEquals(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x04), QcyNoise.setMode(ListeningMode.SEFFAF))
    }

    @Test fun `sahne paketleri tabloyla eslesir`() {
        val expected = mapOf(
            NoiseScene.UYARLANIR to bytesOf(0x01, 0x05, 0x00),
            NoiseScene.KAPALI_ALAN to bytesOf(0x01, 0x01, 0x02),
            NoiseScene.YOLCULUK to bytesOf(0x01, 0x02, 0x02),
            NoiseScene.GURULTULU to bytesOf(0x01, 0x03, 0x02),
            NoiseScene.RUZGAR_KARSITI to bytesOf(0x01, 0x04, 0x00),
        )
        for ((scene, params) in expected) {
            assertArrayEquals(QcyPacket.pack(0x17, params), scene.packet)
            assertEquals(scene, NoiseScene.parse(params))
        }
    }

    @Test fun `bilinmeyen sahne null`() {
        assertNull(NoiseScene.parse(bytesOf(0x01, 0x09, 0x00)))
        assertNull(NoiseScene.parse(bytesOf(0x01, 0x05, 0x02)))
    }

    @Test fun `mod ayristirma`() {
        assertEquals(ListeningMode.GURULTU_ENGELLEME, QcyNoise.parseMode(bytesOf(0x01, 0x05, 0x00)))
        assertEquals(ListeningMode.KAPALI, QcyNoise.parseMode(bytesOf(0x02, 0x00, 0x00)))
        assertEquals(ListeningMode.SEFFAF, QcyNoise.parseMode(bytesOf(0x03, 0x01, 0x04)))
        assertNull(QcyNoise.parseMode(bytesOf(0x09)))
        assertNull(QcyNoise.parseMode(ByteArray(0)))
    }
}

class QcyWearingTest {
    @Test fun `okuma yaniti`() {
        val w = QcyWearing.parse(bytesOf(0x01, 0x02, 0x03, 0x01))!!
        assertTrue(w.enabled); assertEquals(2, w.music); assertEquals(3, w.anc); assertEquals(1, w.tone)
        assertFalse(QcyWearing.parse(bytesOf(0x00, 0x00, 0x00))!!.enabled)
        assertNull(QcyWearing.parse(bytesOf(0x05, 0x00, 0x00)))
        assertNull(QcyWearing.parse(bytesOf(0x01, 0x00)))
    }

    @Test fun `yazarken yalniz durum baytini degistirir`() {
        val w = QcyWearing.parse(bytesOf(0x01, 0x02, 0x03, 0x02))!!
        assertArrayEquals(bytesOf(0xFF, 0x06, 0x2C, 0x04, 0x02, 0x02, 0x03, 0x02), w.setEnabledPacket(false))
        val off = QcyWearing.parse(bytesOf(0x00, 0x07, 0x09))!!
        assertArrayEquals(bytesOf(0xFF, 0x05, 0x2C, 0x03, 0x01, 0x07, 0x09), off.setEnabledPacket(true))
    }
}

class QcyTransparencyTest {
    @Test fun `seviye paketi`() {
        assertArrayEquals(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x04), QcyNoise.transparencyLevel(4))
    }

    @Test fun `aralik 1 ile 8 arasina sinirlanir`() {
        assertArrayEquals(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x01), QcyNoise.transparencyLevel(0))
        assertArrayEquals(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x08), QcyNoise.transparencyLevel(99))
        assertArrayEquals(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x01), QcyNoise.transparencyLevel(-3))
    }

    @Test fun `yanit ayristirma`() {
        assertEquals(6, QcyNoise.parseTransparency(bytesOf(0x03, 0x01, 0x06)))
        assertNull(QcyNoise.parseTransparency(bytesOf(0x01, 0x02, 0x02)))
        assertNull(QcyNoise.parseTransparency(bytesOf(0x03, 0x01)))
        val s = QcyDeviceState().apply(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x06))
        assertEquals(ListeningMode.SEFFAF, s.mode)
        assertEquals(6, s.transparency)
        assertNull(s.apply(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x02, 0x00, 0x00)).transparency)
    }
}

class QcyDeviceStateTest {
    @Test fun `yanitlar durumu gunceller`() {
        var s = QcyDeviceState()
        s = s.apply(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x01, 0x02, 0x02))
        assertEquals(ListeningMode.GURULTU_ENGELLEME, s.mode)
        assertEquals(NoiseScene.YOLCULUK, s.scene)
        s = s.apply(bytesOf(0xFF, 0x05, 0x2C, 0x03, 0x01, 0x01, 0x01))
        assertNotNull(s.wearing)
        s = s.apply(bytesOf(0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x04))
        assertEquals(ListeningMode.SEFFAF, s.mode)
        assertNull(s.scene)
        assertNotNull(s.wearing)
    }

    @Test fun `taninmayan opcode durumu degistirmez`() {
        val s = QcyDeviceState(mode = ListeningMode.KAPALI)
        assertEquals(s, s.apply(bytesOf(0xFF, 0x04, 0x99, 0x02, 0x01, 0x01)))
    }
}

class QcyExtraCommandsTest {
    @Test fun `oyun modu paketi ve cozum`() {
        assertArrayEquals(bytesOf(0xFF, 0x03, 0x09, 0x01, 0x01), QcyGameMode.packet(true))
        assertArrayEquals(bytesOf(0xFF, 0x03, 0x09, 0x01, 0x02), QcyGameMode.packet(false))
        assertEquals(true, QcyGameMode.parse(bytesOf(0x01)))
        assertEquals(false, QcyGameMode.parse(bytesOf(0x02)))
        assertNull(QcyGameMode.parse(bytesOf(0x07)))
        val s = QcyDeviceState().apply(QcyBlock(0x09, bytesOf(0x01)))
        assertEquals(true, s.gameMode)
    }

    @Test fun `kulak algilama ac kapa`() {
        assertArrayEquals(bytesOf(0xFF, 0x03, 0x06, 0x01, 0x01), QcyEarDetection.packet(true))
        assertArrayEquals(bytesOf(0xFF, 0x03, 0x06, 0x01, 0x02), QcyEarDetection.packet(false))
        val s = QcyDeviceState().apply(QcyBlock(0x06, bytesOf(0x02)))
        assertEquals(false, s.earDetection)
        assertNull(s.wearing)
    }

    @Test fun `eq hazir ayarlar Mac ile ayni`() {
        assertNull(QcyEqPreset.of(6))
        assertNull(QcyEqPreset.of(-1))
        assertEquals(6, QcyEqPreset.all.size)
        assertEquals(listOf("Varsayılan", "Pop", "Bas", "Rock", "Yumuşak", "Klasik"), QcyEqPreset.all.map { it.nameTr })
        assertEquals(listOf(8, 7, 5, 4, 0, 0, 0, 0, 0, 0), QcyEqPreset.of(2)!!.bands)
        val p = QcyEqPreset.of(2)!!.packet
        assertEquals(77, p.size)
        assertEquals(0x02, p[4].toInt())
        assertArrayEquals(bytesOf(0xFF, 0x4B, 0x22, 0x49, 0x02, 0x00, 0x00), p.copyOfRange(0, 7))
        assertArrayEquals(bytesOf(5, 6, 7, 1, 2, 0xFF, 1, 0xFC, 0xFA, 0xF9, 0xF8), QcyEqPreset.CLASSIC.legacyBytes)
        assertEquals(5, QcyEqPreset.parse(bytesOf(0x05) + ByteArray(142))!!.index)
        assertNull(QcyEqPreset.parse(bytesOf(0xFF)))
        assertNull(QcyEqPreset.parse(ByteArray(0)))
        assertEquals(2, QcyDeviceState().apply(QcyBlock(0x22, bytesOf(0x02))).eqPreset?.index)
    }

    @Test fun `yetenek dogrulamasi`() {
        assertEquals(listOf(QcyCapability.GAME_MODE, QcyCapability.EAR_DETECTION, QcyCapability.EQ_PRESET), QcyCapability.verified)
        assertFalse(QcyCapability.EQ_CUSTOM.isVerified)
        assertFalse(QcyCapability.TRANSPARENCY_LEVELS.isVerified)
        assertFalse(QcyCapability.MULTIPOINT.isVerified)
        assertTrue(QcyCapability.GAME_MODE.isVerifiedFor(tws = true))
        assertFalse(QcyCapability.GAME_MODE.isVerifiedFor(tws = false))
    }
}

class QcyTouchKeysTest {
    @Test fun `olay kimlikleri`() {
        assertEquals(1, QcyTouchKeys.eventId(QcyTouchSide.LEFT, QcyTouchGesture.SINGLE))
        assertEquals(2, QcyTouchKeys.eventId(QcyTouchSide.RIGHT, QcyTouchGesture.SINGLE))
        assertEquals(3, QcyTouchKeys.eventId(QcyTouchSide.LEFT, QcyTouchGesture.DOUBLE))
        assertEquals(4, QcyTouchKeys.eventId(QcyTouchSide.RIGHT, QcyTouchGesture.DOUBLE))
        assertEquals(5, QcyTouchKeys.eventId(QcyTouchSide.LEFT, QcyTouchGesture.TRIPLE))
        assertEquals(6, QcyTouchKeys.eventId(QcyTouchSide.RIGHT, QcyTouchGesture.TRIPLE))
    }

    @Test fun `000D yazma ciftleri belge ornekleriyle ayni`() {
        assertArrayEquals(bytesOf(0x03, 0x01), QcyTouchKeys.packet(QcyTouchSide.LEFT, QcyTouchGesture.DOUBLE, QcyKeyFunction.PLAY_PAUSE))
        assertArrayEquals(bytesOf(0x06, 0x04), QcyTouchKeys.packet(QcyTouchSide.RIGHT, QcyTouchGesture.TRIPLE, QcyKeyFunction.ASSISTANT))
        assertArrayEquals(bytesOf(0x01, 0x07), QcyTouchKeys.packet(QcyTouchSide.LEFT, QcyTouchGesture.SINGLE, QcyKeyFunction.GAME_MODE))
    }

    @Test fun `setting yalniz ilgili cifti degistirir ve kalan baytlari korur`() {
        // Mac testindeki gibi: 20 bayt, taninmayan anahtar ve dolgu korunur.
        val raw = bytesOf(1, 0, 2, 0, 3, 1, 4, 1, 5, 7, 6, 4, 9, 9, 0, 0, 0, 0, 0, 0)
        val m = QcyTouchMap.parse(raw)!!
        val n = m.setting(QcyTouchSide.RIGHT, QcyTouchGesture.DOUBLE, QcyKeyFunction.NEXT)!!
        assertArrayEquals(bytesOf(1, 0, 2, 0, 3, 1, 4, 3, 5, 7, 6, 4, 9, 9, 0, 0, 0, 0, 0, 0), n.bytes)
        assertEquals(20, n.bytes.size)
        assertArrayEquals(raw, m.bytes) // orijinal degismez
        assertNull(QcyTouchMap.parse(bytesOf(3, 1))!!.setting(QcyTouchSide.LEFT, QcyTouchGesture.SINGLE, QcyKeyFunction.NONE))
    }

    @Test fun `islev kodlari`() {
        assertEquals(listOf(0, 1, 2, 3, 4, 5, 6, 7), QcyKeyFunction.entries.map { it.code })
        assertNull(QcyKeyFunction.of(8))
    }

    @Test fun `varsayilan esleme okunur`() {
        // controlpan_default.json: tek 0/0, cift 1/1, uc L=7 R=4
        val m = QcyTouchMap.parse(bytesOf(1, 0, 2, 0, 3, 1, 4, 1, 5, 7, 6, 4))!!
        assertEquals(QcyKeyFunction.NONE, m.function(QcyTouchSide.LEFT, QcyTouchGesture.SINGLE))
        assertEquals(QcyKeyFunction.PLAY_PAUSE, m.function(QcyTouchSide.RIGHT, QcyTouchGesture.DOUBLE))
        assertEquals(QcyKeyFunction.GAME_MODE, m.function(QcyTouchSide.LEFT, QcyTouchGesture.TRIPLE))
        assertEquals(QcyKeyFunction.ASSISTANT, m.function(QcyTouchSide.RIGHT, QcyTouchGesture.TRIPLE))
    }

    @Test fun `eksik anahtar ve bilinmeyen kod null, gecersiz uzunluk reddedilir`() {
        val m = QcyTouchMap.parse(bytesOf(3, 1, 4, 9))!!
        assertNull(m.function(QcyTouchSide.LEFT, QcyTouchGesture.SINGLE))
        assertNull(m.function(QcyTouchSide.RIGHT, QcyTouchGesture.DOUBLE))
        assertNull(QcyTouchMap.parse(ByteArray(0)))
        assertNull(QcyTouchMap.parse(bytesOf(3, 1, 4)))
    }

    @Test fun `durum 0x2B yanitini ve 000D okumasini isler`() {
        val s = QcyDeviceState().apply(QcyBlock(0x2B, bytesOf(3, 1)))
        assertEquals(QcyKeyFunction.PLAY_PAUSE, s.touchKeys?.function(QcyTouchSide.LEFT, QcyTouchGesture.DOUBLE))
        assertEquals(s.touchKeys, QcyDeviceState().applyKeyMap(bytesOf(3, 1)).touchKeys)
        assertNull(QcyDeviceState().applyKeyMap(bytesOf(3)).touchKeys)
    }

    @Test fun `kapi APK okumasi etkin dogrulanmis degil`() {
        assertFalse(QcyCapability.TOUCH_KEYS.isVerified)
        assertTrue(QcyCapability.TOUCH_KEYS.isEnabledFor(tws = true))
        assertTrue(QcyCapability.EQ_CUSTOM.isEnabledFor(tws = true))
        assertFalse(QcyCapability.MULTIPOINT.isEnabledFor(tws = true))
        assertFalse(QcyCapability.EQ_CUSTOM.isEnabledFor(tws = false))
    }
}

class QcyCustomEqTest {
    @Test fun `sifir EQ 0x22 paketi`() {
        val p = QcyCustomEq.packets(List(10) { 0 }).single()
        assertEquals(77, p.size)
        // FF N=75 cmd=22 len=73 eqIndex=255 master=0
        assertArrayEquals(bytesOf(0xFF, 0x4B, 0x22, 0x49, 0xFF, 0x00, 0x00), p.copyOfRange(0, 7))
        // ilk bant: 31 Hz, 0 dB, Q=100, tur 255
        assertArrayEquals(bytesOf(0x1F, 0x00, 0x00, 0x00, 0x64, 0x00, 0xFF), p.copyOfRange(7, 14))
        // son bant: 16000 Hz = 0x3E80
        assertArrayEquals(bytesOf(0x80, 0x3E, 0x00, 0x00, 0x64, 0x00, 0xFF), p.copyOfRange(70, 77))
        assertTrue(QcyPacket.parse(p).single().opcode == 0x22)
    }

    @Test fun `kazanc dB*100 int16 LE ve sinirlama`() {
        val p = QcyCustomEq.packets(listOf(8, -6, 20, -20)).single()
        assertArrayEquals(bytesOf(0x20, 0x03), p.copyOfRange(7 + 2, 7 + 4))   // +8 dB = 800
        assertArrayEquals(bytesOf(0xA8, 0xFD), p.copyOfRange(14 + 2, 14 + 4)) // -6 dB = -600
        assertArrayEquals(bytesOf(0x20, 0x03), p.copyOfRange(21 + 2, 21 + 4)) // 20 -> +8
        assertArrayEquals(bytesOf(0xE0, 0xFC), p.copyOfRange(28 + 2, 28 + 4)) // -20 -> -800
        assertArrayEquals(bytesOf(0, 0), p.copyOfRange(35 + 2, 35 + 4))       // eksik deger 0
    }

    @Test fun `0x20 paketi 6 bayt bant`() {
        val p = QcyCustomEq.packets(List(10) { 0 }, opcode = 0x20).single()
        assertEquals(4 + 3 + 60, p.size)
        assertArrayEquals(bytesOf(0xFF, 0x41, 0x20, 0x3F, 0xFF, 0x00, 0x00), p.copyOfRange(0, 7))
        assertArrayEquals(bytesOf(0x1F, 0x00, 0x00, 0x00, 0x64, 0x00), p.copyOfRange(7, 13))
    }
}
