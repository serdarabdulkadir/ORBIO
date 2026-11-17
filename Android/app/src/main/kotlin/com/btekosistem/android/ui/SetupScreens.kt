package com.btekosistem.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.btekosistem.android.R
import com.btekosistem.android.ble.BtEnvironment
import com.btekosistem.android.ble.Environment
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt

/** Tarama baslamadan once gereken adim: izin, Bluetooth, konum servisi ya da desteksiz cihaz. */
@Composable
fun SetupScreen(
    env: Environment,
    permanentlyDenied: Boolean,
    contentPadding: PaddingValues,
    onRequestPermission: () -> Unit,
    onOpenAppSettings: () -> Unit,
    onEnableBluetooth: () -> Unit,
    onOpenLocationSettings: () -> Unit,
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
        Text(stringResource(R.string.home_title), style = BtType.pageTitle, color = c.text)
        val icon = when (env) {
            Environment.NEEDS_PERMISSION -> Icons.Rounded.Lock
            Environment.BLUETOOTH_OFF -> BtIcons.Bluetooth
            else -> Icons.Rounded.Info
        }
        val (title, body) = when (env) {
            Environment.NEEDS_PERMISSION ->
                if (permanentlyDenied) R.string.perm_denied_title to R.string.perm_denied_body
                else R.string.perm_title to (if (BtEnvironment.needsLocationService) R.string.perm_body_legacy else R.string.perm_body_new)
            Environment.BLUETOOTH_OFF -> R.string.env_bt_off_title to R.string.env_bt_off_body
            Environment.LOCATION_OFF -> R.string.env_loc_off_title to R.string.env_loc_off_body
            else -> R.string.env_unsupported_title to R.string.env_unsupported_body
        }
        val (action, onAction) = when (env) {
            Environment.NEEDS_PERMISSION ->
                if (permanentlyDenied) R.string.perm_open_settings to onOpenAppSettings
                else R.string.perm_allow to onRequestPermission
            Environment.BLUETOOTH_OFF -> R.string.env_bt_on to onEnableBluetooth
            Environment.LOCATION_OFF -> R.string.env_loc_on to onOpenLocationSettings
            else -> null to {}
        }
        BtCard {
            EmptyState(
                icon, stringResource(title), stringResource(body),
                action = action?.let { stringResource(it) }, onAction = onOnActionSafe(onAction),
            )
        }
        if (env == Environment.NEEDS_PERMISSION && !permanentlyDenied) {
            BtCard { PermissionRows() }
        }
    }
}

private fun onOnActionSafe(f: () -> Unit): () -> Unit = f

@Composable
private fun PermissionRows() {
    val c = MaterialTheme.bt
    val rows: List<Pair<Int, Int>> = if (BtEnvironment.needsLocationService)
        listOf(R.string.perm_location_title to R.string.perm_location_body)
    else listOf(
        R.string.perm_scan_title to R.string.perm_scan_body,
        R.string.perm_connect_title to R.string.perm_connect_body,
    )
    rows.forEach { (t, b) ->
        Column(verticalArrangement = Arrangement.spacedBy(Space.xs)) {
            Text(stringResource(t), style = BtType.rowTitle, color = c.text)
            Text(stringResource(b), style = BtType.caption, color = c.textSecondary)
        }
    }
}
