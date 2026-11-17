package com.btekosistem.android.ui

import android.Manifest
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.btekosistem.android.R
import com.btekosistem.android.ble.BtEnvironment
import com.btekosistem.android.peer.PeerManager
import com.btekosistem.android.peer.PeerSettings
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt

@Composable
fun SettingsScreen(contentPadding: PaddingValues, bluetoothOn: Boolean, onOpenAppSettings: () -> Unit) {
    val ctx = LocalContext.current
    val mgr = remember { PeerManager.get(ctx) }
    val settings by mgr.store.settings.collectAsStateWithLifecycle()
    val mac by mgr.state.collectAsStateWithLifecycle()
    val endBlocked by mgr.phone.endBlocked.collectAsStateWithLifecycle()
    var batteryOk by remember { mutableStateOf(BackgroundAccess.batteryUnrestricted(ctx)) }
    LifecycleResumeEffect(Unit) {
        batteryOk = BackgroundAccess.batteryUnrestricted(ctx)
        onPauseOrDispose { }
    }
    val callPerm = rememberPerm(Manifest.permission.ANSWER_PHONE_CALLS)
    val dialPerm = rememberPerm(Manifest.permission.CALL_PHONE)
    val contactsPerm = rememberPerm(Manifest.permission.READ_CONTACTS)
    val logPerm = rememberPerm(Manifest.permission.READ_CALL_LOG)
    SettingsContent(
        contentPadding, bluetoothOn, settings, mac.pairedName, versionName(ctx),
        callGranted = callPerm.granted && dialPerm.granted, contactsGranted = contactsPerm.granted, logGranted = logPerm.granted,
        permissionRows = permissionRows(ctx),
        onOpenAppSettings = onOpenAppSettings,
        onCall = { on -> mgr.store.update { it.copy(callControl = on) }; if (on) { if (!callPerm.granted) callPerm.act() else if (!dialPerm.granted) dialPerm.act() } },
        onContacts = { on -> mgr.store.update { it.copy(contacts = on) }; if (on && !contactsPerm.granted) contactsPerm.act() },
        onLog = { on -> mgr.store.update { it.copy(callLog = on) }; if (on && !logPerm.granted) logPerm.act() },
        onUnpair = mgr::unpair,
        endBlocked = endBlocked,
        batteryUnrestricted = batteryOk,
        onBattery = { BackgroundAccess.requestBattery(ctx) },
        onAutostart = { BackgroundAccess.openAutostart(ctx) },
    )
}

@Composable
fun SettingsContent(
    contentPadding: PaddingValues, bluetoothOn: Boolean, settings: PeerSettings, pairedName: String?, version: String,
    callGranted: Boolean, contactsGranted: Boolean, logGranted: Boolean, permissionRows: List<Pair<Int, Boolean>>,
    onOpenAppSettings: () -> Unit, onCall: (Boolean) -> Unit, onContacts: (Boolean) -> Unit, onLog: (Boolean) -> Unit, onUnpair: () -> Unit,
    batteryUnrestricted: Boolean = false, onBattery: () -> Unit = {}, onAutostart: () -> Unit = {},
    endBlocked: Boolean = false,
) {
    val c = MaterialTheme.bt
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(
                start = Space.lg, end = Space.lg,
                top = contentPadding.calculateTopPadding() + Space.lg,
                bottom = contentPadding.calculateBottomPadding() + Space.lg,
            ),
        verticalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        Text(stringResource(R.string.settings_title), style = BtType.pageTitle, color = c.text)

        SectionLabel(stringResource(R.string.set_mac_title))
        BtCard {
            Text(stringResource(R.string.set_mac_body), style = BtType.body, color = c.textSecondary)
            SwitchRow(R.string.set_call_title, R.string.set_call_body, settings.callControl, callGranted, onCall)
            if (endBlocked) Text(stringResource(R.string.set_end_blocked), style = BtType.caption, color = c.down)
            if (pairedName != null) {
                HorizontalDivider(color = c.separator)
                Text(stringResource(R.string.mac_paired_with, pairedName), style = BtType.body, color = c.textSecondary)
                BtButton(stringResource(R.string.mac_unpair), onUnpair, Modifier.fillMaxWidth(), primary = false)
            }
        }

        SectionLabel(stringResource(R.string.share_title))
        BtCard {
            Text(stringResource(R.string.share_body), style = BtType.body, color = c.textSecondary)
            SwitchRow(R.string.set_contacts_title, R.string.set_contacts_body, settings.contacts, contactsGranted, onContacts)
            Text(stringResource(R.string.share_contacts_privacy), style = BtType.caption, color = c.textSecondary)
            HorizontalDivider(color = c.separator)
            SwitchRow(R.string.set_log_title, R.string.set_log_body, settings.callLog, logGranted, onLog)
            Text(stringResource(R.string.share_log_privacy), style = BtType.caption, color = c.textSecondary)
        }

        SectionLabel(stringResource(R.string.bg_title))
        BtCard {
            Text(stringResource(R.string.bg_body), style = BtType.body, color = c.textSecondary)
            ValueRow(stringResource(R.string.bg_battery_row), stringResource(if (batteryUnrestricted) R.string.bg_ok else R.string.bg_restricted), batteryUnrestricted)
            if (!batteryUnrestricted) BtButton(stringResource(R.string.bg_battery_btn), onBattery, Modifier.fillMaxWidth())
            BtButton(stringResource(R.string.bg_autostart_btn), onAutostart, Modifier.fillMaxWidth(), primary = false)
        }

        SectionLabel(stringResource(R.string.settings_permissions))
        BtCard {
            permissionRows.forEachIndexed { i, (label, granted) ->
                if (i > 0) HorizontalDivider(color = c.separator)
                ValueRow(stringResource(label), stringResource(if (granted) R.string.perm_granted else R.string.perm_missing), granted)
            }
            HorizontalDivider(color = c.separator)
            ValueRow(stringResource(R.string.settings_bluetooth), stringResource(if (bluetoothOn) R.string.settings_on else R.string.settings_off), bluetoothOn)
            BtButton(stringResource(R.string.perm_open_settings), onOpenAppSettings, Modifier.fillMaxWidth(), primary = false)
        }

        SectionLabel(stringResource(R.string.settings_about))
        BtCard {
            ValueRow(stringResource(R.string.about_version), version, null)
            HorizontalDivider(color = c.separator)
            Text(stringResource(R.string.about_devices), style = BtType.rowTitle, color = c.text)
            Text(stringResource(R.string.about_devices_body), style = BtType.body, color = c.textSecondary)
            HorizontalDivider(color = c.separator)
            Text(stringResource(R.string.about_privacy), style = BtType.rowTitle, color = c.text)
            Text(stringResource(R.string.about_privacy_body), style = BtType.body, color = c.textSecondary)
        }
    }
}

private fun permissionRows(ctx: Context): List<Pair<Int, Boolean>> =
    (if (BtEnvironment.needsLocationService)
        listOf(android.Manifest.permission.ACCESS_FINE_LOCATION to R.string.perm_location_title)
    else listOf(
        android.Manifest.permission.BLUETOOTH_SCAN to R.string.perm_scan_title,
        android.Manifest.permission.BLUETOOTH_CONNECT to R.string.perm_connect_title,
    )).map { (perm, label) -> label to BtEnvironment.isGranted(ctx, perm) }

@Composable
private fun SwitchRow(title: Int, body: Int, checked: Boolean, androidGranted: Boolean, onChange: (Boolean) -> Unit) {
    val c = MaterialTheme.bt
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
            Text(stringResource(title), style = BtType.rowTitle, color = c.text)
            Text(stringResource(body), style = BtType.caption, color = c.textSecondary)
            if (checked && !androidGranted) Text(stringResource(R.string.set_android_missing), style = BtType.caption, color = c.down)
        }
        Switch(
            checked = checked, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = c.navy, checkedThumbColor = c.onNavy, uncheckedTrackColor = c.fill, uncheckedBorderColor = c.textTertiary),
        )
    }
}

@Composable
private fun ValueRow(label: String, value: String, good: Boolean?) {
    val c = MaterialTheme.bt
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
        Text(label, Modifier.weight(1f), style = BtType.rowTitle, color = c.text)
        Text(
            value, style = BtType.body, textAlign = TextAlign.End,
            color = when (good) { true -> c.up; false -> c.down; null -> c.textSecondary },
        )
    }
}

private fun versionName(ctx: Context): String =
    runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "-"
