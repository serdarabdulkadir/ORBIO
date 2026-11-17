package com.btekosistem.android.audio

import org.junit.Assert.assertEquals
import org.junit.Test

class AudioLinkTest {
    @Test fun `profil ve eslesme sayilari esler`() {
        assertEquals(ProfileState.CONNECTED, AudioLinkMapper.profileFromInt(2))
        assertEquals(ProfileState.CONNECTING, AudioLinkMapper.profileFromInt(1))
        assertEquals(ProfileState.DISCONNECTING, AudioLinkMapper.profileFromInt(3))
        assertEquals(ProfileState.DISCONNECTED, AudioLinkMapper.profileFromInt(0))
        assertEquals(ProfileState.DISCONNECTED, AudioLinkMapper.profileFromInt(99))
        assertEquals(BondState.BONDED, AudioLinkMapper.bondFromInt(12))
        assertEquals(BondState.BONDING, AudioLinkMapper.bondFromInt(11))
        assertEquals(BondState.NONE, AudioLinkMapper.bondFromInt(10))
    }

    @Test fun `ses baglantisi durumu`() {
        val d = ProfileState.DISCONNECTED
        assertEquals(AudioLink.NOT_PAIRED, AudioLinkMapper.combine(BondState.NONE, ProfileState.CONNECTED, d))
        assertEquals(AudioLink.PAIRING, AudioLinkMapper.combine(BondState.BONDING, d, d))
        assertEquals(AudioLink.IDLE, AudioLinkMapper.combine(BondState.BONDED, d, ProfileState.DISCONNECTING))
        assertEquals(AudioLink.CONNECTING, AudioLinkMapper.combine(BondState.BONDED, ProfileState.CONNECTING, d))
        assertEquals(AudioLink.CONNECTED, AudioLinkMapper.combine(BondState.BONDED, ProfileState.CONNECTED, d))
        assertEquals(AudioLink.CONNECTED, AudioLinkMapper.combine(BondState.BONDED, d, ProfileState.CONNECTED))
        assertEquals(AudioLink.CONNECTED, AudioLinkMapper.combine(BondState.BONDED, ProfileState.CONNECTING, ProfileState.CONNECTED))
    }

    @Test fun `eslesme sonucu`() {
        assertEquals(BondOutcome.PAIRED, AudioLinkMapper.bondOutcome(11, 12))
        assertEquals(BondOutcome.FAILED, AudioLinkMapper.bondOutcome(11, 10))
        assertEquals(BondOutcome.NONE, AudioLinkMapper.bondOutcome(10, 11))
        assertEquals(BondOutcome.NONE, AudioLinkMapper.bondOutcome(12, 10))
    }

    @Test fun `anlik goruntu baglantiyi turetir`() {
        val s = AudioSnapshot("AA", BondState.BONDED, ProfileState.CONNECTED)
        assertEquals(AudioLink.CONNECTED, s.link)
        assertEquals(AudioLink.NOT_PAIRED, AudioSnapshot().link)
    }
}
