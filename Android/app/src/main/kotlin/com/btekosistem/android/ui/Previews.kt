package com.btekosistem.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme
import com.btekosistem.android.audio.AudioSnapshot
import com.btekosistem.android.audio.BondState
import com.btekosistem.android.audio.ProfileState
import com.btekosistem.android.ble.Environment
import com.btekosistem.android.peer.CallInfo
import com.btekosistem.android.peer.MacPhase
import com.btekosistem.android.peer.MacService
import com.btekosistem.android.peer.MacUi
import com.btekosistem.android.peer.PeerCallLogEntry
import com.btekosistem.android.peer.PeerContact
import com.btekosistem.android.peer.PeerSettings
import com.btekosistem.android.peer.PhoneInfo
import com.btekosistem.android.protocol.ListeningMode
import com.btekosistem.android.protocol.NoiseScene
import com.btekosistem.android.protocol.QcyAdvertisement
import com.btekosistem.android.protocol.QcyDeviceState
import com.btekosistem.android.protocol.QcyWearing
import com.btekosistem.android.ui.theme.BtTheme
import com.btekosistem.android.ui.theme.bt
import java.net.InetAddress

// Sahte verili onizlemeler: acik, bos/dolu durumlar.

@Composable
private fun Frame(content: @Composable () -> Unit) {
    BtTheme { Box(Modifier.fillMaxSize().background(MaterialTheme.bt.bg)) { content() } }
}

private val pad = PaddingValues(top = 24.dp)

private fun device(left: Int? = 82, right: Int? = 15, case: Int? = null, charging: Boolean = false) = FoundDevice(
    "AA", "QCY MeloBuds Pro", true,
    QcyAdvertisement(left, right, case, charging, false, false, "84:AC:60:20:9D:3A"), 0L,
)

private fun connectedState() = HomeState(
    devices = listOf(device()), selectedKey = "AA", link = Link.CONNECTED, ready = true,
    device = QcyDeviceState(ListeningMode.GURULTU_ENGELLEME, NoiseScene.UYARLANIR, QcyWearing(true, 1, 1, null)),
)

private val audioOn = AudioSnapshot("84:AC:60:20:9D:3A", BondState.BONDED, ProfileState.CONNECTED, ProfileState.CONNECTED)

@Preview(name = "Kulaklik dolu", showBackground = true, heightDp = 1400)
@Composable
private fun HeadsetConnectedDark() = Frame() {
    HeadsetContent(connectedState(), audioOn, VolumeUi(), true, HeadsetActions(), pad)
}

@Preview(name = "Kulaklik dolu acik", showBackground = true, heightDp = 1400)
@Composable
private fun HeadsetConnectedLight() = Frame() {
    HeadsetContent(connectedState(), audioOn, VolumeUi(muted = true), false, HeadsetActions(), pad)
}

@Preview(name = "Kulaklik medya Mac", showBackground = true, heightDp = 1500)
@Composable
private fun HeadsetWithMedia() = Frame() {
    HeadsetContent(
        connectedState(), audioOn, VolumeUi(), true, HeadsetActions(), pad,
        media = com.btekosistem.android.peer.LocalMedia(true, true, "Muzik", "Dark Side of the Star", "Haruomi Hosono"),
        mediaAccess = true, macConnected = true,
    )
}

@Preview(name = "Kulaklik medya erisimi yok", showBackground = true, heightDp = 1500)
@Composable
private fun HeadsetNoMediaAccess() = Frame() {
    HeadsetContent(connectedState(), audioOn, VolumeUi(), true, HeadsetActions(), pad, mediaAccess = false)
}

@Preview(name = "Kulaklik tarama", showBackground = true, heightDp = 600)
@Composable
private fun HeadsetSearching() = Frame() {
    HeadsetContent(HomeState(), AudioSnapshot(), VolumeUi(), true, HeadsetActions(), pad)
}

@Preview(name = "Kulaklik eslesmemis", showBackground = true, heightDp = 900)
@Composable
private fun HeadsetNotPaired() = Frame() {
    HeadsetContent(
        HomeState(devices = listOf(device(case = 60, charging = true))),
        AudioSnapshot("84:AC:60:20:9D:3A", BondState.NONE, pairFailed = true), VolumeUi(), true, HeadsetActions(), pad,
    )
}

@Preview(name = "Ses baglanamadi", showBackground = true, heightDp = 1000)
@Composable
private fun HeadsetAudioHelp() = Frame() {
    HeadsetContent(
        HomeState(devices = listOf(device())),
        AudioSnapshot("84:AC:60:20:9D:3A", BondState.BONDED, connectFailed = true), VolumeUi(), true, HeadsetActions(), pad,
    )
}

@Preview(name = "Bluetooth kapali", showBackground = true, heightDp = 600)
@Composable
private fun SetupBluetoothOff() = Frame() { SetupScreen(Environment.BLUETOOTH_OFF, false, pad, {}, {}, {}, {}) }

@Preview(name = "Izin yok", showBackground = true, heightDp = 800)
@Composable
private fun SetupPermission() = Frame() { SetupScreen(Environment.NEEDS_PERMISSION, false, pad, {}, {}, {}, {}) }

private val info = PhoneInfo("Pixel 8", "Pixel 8", 64, true, 3, "wifi")
private val granted = PermAccess(true, false) {}
private val missing = PermAccess(false, false) {}
private val allGranted = PhonePerms(granted, granted, granted, granted, granted)
private val noneGranted = PhonePerms(missing, missing, missing, missing, missing)

private val recents = listOf(
    PeerCallLogEntry("+905321234512", "Ayşe Yılmaz", "gelen", System.currentTimeMillis() / 1000 - 600, 180),
    PeerCallLogEntry("+905551112233", null, "cevapsiz", System.currentTimeMillis() / 1000 - 4000, 0),
    PeerCallLogEntry("+905079998877", "Mehmet", "giden", System.currentTimeMillis() / 1000 - 90000, 45),
)

@Preview(name = "Telefon gelen arama", showBackground = true, heightDp = 2200)
@Composable
private fun PhoneRinging() = Frame() {
    PhoneContent(
        PhoneUiModel(
            call = CallInfo("caliyor", "gelen", "+905321234512", "Ayşe Yılmaz"), info = info, perms = allGranted, recents = recents,
            suggestions = listOf(PeerContact("Ayşe Yılmaz", listOf("+905321234512"))), number = "Ay",
            mac = MacUi(MacPhase.CONNECTED, "MacBook Pro", null, emptyList(), "MacBook Pro"),
        ),
        PhoneActions(), pad,
    )
}

@Preview(name = "Telefon gorusme acik", showBackground = true, heightDp = 2200)
@Composable
private fun PhoneActive() = Frame() {
    PhoneContent(
        PhoneUiModel(
            call = CallInfo("acik", "gelen", "+905321234512", "Ayşe Yılmaz", 0L), now = 134_000L, info = info,
            perms = allGranted, recents = recents, missedOnly = false,
            mac = MacUi(MacPhase.SEARCHING, found = listOf(MacService("a", "id", "MacBook Pro", InetAddress.getLoopbackAddress(), 1))),
        ),
        PhoneActions(), pad,
    )
}

@Preview(name = "Telefon izinler yok", showBackground = true, heightDp = 2200)
@Composable
private fun PhoneNoPermissions() = Frame() {
    PhoneContent(PhoneUiModel(info = info, perms = noneGranted), PhoneActions(), pad)
}

@Preview(name = "Ayarlar", showBackground = true, heightDp = 1500)
@Composable
private fun SettingsPreview() = Frame() {
    SettingsContent(
        pad, true, PeerSettings(callControl = true), "MacBook Pro", "0.2.0", callGranted = false, contactsGranted = true, logGranted = false,
        permissionRows = listOf(com.btekosistem.android.R.string.perm_scan_title to true, com.btekosistem.android.R.string.perm_connect_title to false),
        onOpenAppSettings = {}, onCall = {}, onContacts = {}, onLog = {}, onUnpair = {},
    )
}
