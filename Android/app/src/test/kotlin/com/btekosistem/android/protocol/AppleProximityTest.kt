package com.btekosistem.android.protocol

import com.btekosistem.android.ble.AppleSelector
import com.btekosistem.android.ble.AppleSighting
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Swift ProximityPairingTests ile ayni sentetik vektorler. */
class AppleProximityTest {
    private fun <T : Any> nn(v: T?): T { assertNotNull(v); return v!! }

    private fun frame(model: Int, status: Int, battery: Int, charge: Int, lid: Int = 0x31, color: Int = 0x00): ByteArray =
        bytesOf(0x4C, 0x00, 0x07, 0x19, 0x01, model shr 8, model and 0xFF, status, battery, charge, lid, color, 0x00) +
            ByteArray(16) { 0xAA.toByte() }

    private fun parse(model: Int, status: Int, battery: Int, charge: Int) =
        nn(ProximityPairingParser.parse(frame(model, status, battery, charge)))

    @Test fun temelAlanlar() {
        val i = parse(0x1420, 0x55, 0x89, 0x46)
        assertEquals("AirPods Pro (2. nesil, Lightning)", i.modelName)
        assertEquals(80, i.left); assertEquals(90, i.right); assertEquals(60, i.caseBattery)
        assertTrue(i.caseCharging); assertEquals(0x31, i.lidCounter)
    }

    @Test fun cevirmeBitiSolSagiDegistirir() {
        val i = parse(0x0E20, 0x75, 0x89, 0x2F)
        assertEquals(90, i.left); assertEquals(80, i.right)
        assertNull(i.caseBattery)
        assertTrue(i.rightCharging); assertFalse(i.leftCharging)
    }

    @Test fun bilinmeyenPilNibble() {
        val i = parse(0x1234, 0x01, 0xF5, 0x0F)
        assertNull(i.modelName); assertNull(i.left); assertEquals(50, i.right)
    }

    @Test fun baskaSirketVeKisaVeriReddedilir() {
        val d = frame(0x1420, 0x55, 0x89, 0x46); d[0] = 0x06
        assertNull(ProximityPairingParser.parse(d))
        assertNull(ProximityPairingParser.parse(bytesOf(0x4C, 0x00, 0x07, 0x19, 0x01)))
        assertNull(ProximityPairingParser.parse(bytesOf(0x4C)))
    }

    @Test fun onundeBaskaTlvOlanYuk() {
        val pp = frame(0x1420, 0x55, 0x77, 0x05).let { it.copyOfRange(2, it.size) }
        val d = bytesOf(0x4C, 0x00, 0x10, 0x02, 0x0B, 0x1C) + pp
        assertEquals(70, nn(ProximityPairingParser.parse(d)).left)
        // Android getManufacturerSpecificData cikti (sirket kimligi yok).
        assertEquals(70, nn(ProximityPairingParser.parsePayload(d.copyOfRange(2, d.size))).left)
    }

    @Test fun modelKimlikleriBenzersizVeAdli() {
        val ids = AppleModelCatalog.all.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertTrue(ids.size >= 30)
        assertTrue(AppleModelCatalog.all.all { it.name.isNotEmpty() })
    }

    @Test fun bilinmeyenModelAdsiz() {
        val i = parse(0x7F7F, 0x01, 0x55, 0x05)
        assertNull(i.modelInfo); assertNull(i.modelName)
    }

    @Test fun kulakBitleriVeKutuBiti() {
        var i = parse(0x0E20, 0x08, 0x55, 0x05)
        assertTrue(i.leftInEar && !i.rightInEar)
        i = parse(0x0E20, 0x28, 0x55, 0x05)
        assertTrue(!i.leftInEar && i.rightInEar)
        i = parse(0x0E20, 0x48, 0x55, 0x05)
        assertTrue(!i.leftInEar && i.rightInEar)
        i = parse(0x0E20, 0x14, 0x55, 0x05)
        assertTrue(i.onePodInCase && i.bothPodsInCase)
    }

    @Test fun tekParcaCihazPiliAltNibbledan() {
        val i = parse(0x0A20, 0x20, 0xF7, 0x1F)
        assertEquals(AppleForm.HEADSET, i.modelInfo?.form)
        assertEquals(70, i.headsetBattery); assertTrue(i.headsetCharging); assertTrue(i.headsetWorn)
    }

    private fun sighting(addr: String, model: Int, rssi: Int, at: Long = 0) =
        AppleSighting(addr, parse(model, 0x55, 0x89, 0x46), rssi, at)

    @Test fun secimEnGucluRssiKullanir() {
        val a = sighting("A", 0x0E20, -60); val b = sighting("B", 0x0E20, -50)
        assertEquals("B", AppleSelector.pick(listOf(a, b), emptyList(), 1000)?.address)
    }

    @Test fun secimBagliSesCihaziniTercihEder() {
        val pods = sighting("A", 0x0E20, -70); val beats = sighting("B", 0x1220, -50)
        assertEquals("A", AppleSelector.pick(listOf(pods, beats), listOf("Benim AirPods"), 1000)?.address)
        assertEquals("B", AppleSelector.pick(listOf(pods, beats), listOf("Beats Fit Pro"), 1000)?.address)
    }

    @Test fun uzakVeEskiElenir() {
        assertNull(AppleSelector.pick(listOf(sighting("A", 0x0E20, -90)), emptyList(), 1000))
        assertNull(AppleSelector.pick(listOf(sighting("A", 0x0E20, -40, at = 0)), emptyList(), AppleSelector.FRESH_MS + 1))
    }
}
