package com.btekosistem.android.audio

// Kulakligin SES (klasik Bluetooth: A2DP / HFP) baglantisi. BLE GATT kontrol kanalindan ayri bir katman.
// Saf Kotlin: Android sabitleri (BluetoothDevice.BOND_*, BluetoothProfile.STATE_*) sayi olarak eslenir; birim testlenir.

enum class BondState { NONE, BONDING, BONDED }
enum class ProfileState { DISCONNECTED, CONNECTING, CONNECTED, DISCONNECTING }
enum class AudioLink { NOT_PAIRED, PAIRING, IDLE, CONNECTING, CONNECTED }
enum class BondOutcome { NONE, PAIRED, FAILED }

object AudioLinkMapper {
    /** BluetoothDevice.BOND_NONE=10, BOND_BONDING=11, BOND_BONDED=12 */
    fun bondFromInt(v: Int): BondState = when (v) {
        12 -> BondState.BONDED
        11 -> BondState.BONDING
        else -> BondState.NONE
    }

    /** BluetoothProfile.STATE_DISCONNECTED=0, CONNECTING=1, CONNECTED=2, DISCONNECTING=3 */
    fun profileFromInt(v: Int): ProfileState = when (v) {
        2 -> ProfileState.CONNECTED
        1 -> ProfileState.CONNECTING
        3 -> ProfileState.DISCONNECTING
        else -> ProfileState.DISCONNECTED
    }

    /** Ses "bagli" sayilmasi icin A2DP ya da HFP'den birinin bagli olmasi yeter. */
    fun combine(bond: BondState, a2dp: ProfileState, hfp: ProfileState): AudioLink = when {
        bond == BondState.NONE -> AudioLink.NOT_PAIRED
        bond == BondState.BONDING -> AudioLink.PAIRING
        a2dp == ProfileState.CONNECTED || hfp == ProfileState.CONNECTED -> AudioLink.CONNECTED
        a2dp == ProfileState.CONNECTING || hfp == ProfileState.CONNECTING -> AudioLink.CONNECTING
        else -> AudioLink.IDLE
    }

    /** ACTION_BOND_STATE_CHANGED: onceki ve yeni durumdan eslesme sonucu. */
    fun bondOutcome(previous: Int, current: Int): BondOutcome = when {
        previous == 11 && current == 12 -> BondOutcome.PAIRED
        previous == 11 && current == 10 -> BondOutcome.FAILED
        else -> BondOutcome.NONE
    }
}

data class AudioSnapshot(
    val address: String? = null,
    val bond: BondState = BondState.NONE,
    val a2dp: ProfileState = ProfileState.DISCONNECTED,
    val hfp: ProfileState = ProfileState.DISCONNECTED,
    val pairFailed: Boolean = false,
    val connectFailed: Boolean = false,
) {
    val link: AudioLink get() = AudioLinkMapper.combine(bond, a2dp, hfp)
}
