package com.btekosistem.android.ui

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Phone
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.btekosistem.android.R
import com.btekosistem.android.ble.BtEnvironment
import com.btekosistem.android.ble.Environment
import com.btekosistem.android.peer.PeerManager
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt

private enum class Tab(val label: Int, val icon: ImageVector) {
    HEADSET(R.string.nav_headset, BtIcons.Headphones),
    PHONE(R.string.nav_phone, Icons.Rounded.Phone),
    SETTINGS(R.string.nav_settings, Icons.Rounded.Settings),
}

@Composable
fun BtApp(vm: MainViewModel = viewModel()) {
    val ctx = LocalContext.current
    val c = MaterialTheme.bt
    val reduce = rememberReduceMotion()
    val state by vm.state.collectAsStateWithLifecycle()
    var env by remember { mutableStateOf(BtEnvironment.current(ctx)) }
    var tab by rememberSaveable { mutableStateOf(Tab.HEADSET) }
    var requested by rememberSaveable { mutableStateOf(false) }

    LifecycleResumeEffect(Unit) {
        env = BtEnvironment.current(ctx)
        val mgr = PeerManager.get(ctx)
        mgr.phone.ensureStarted()
        mgr.resumeIfEnabled()
        onPauseOrDispose { }
    }
    // Bluetooth / konum servisi acilip kapaninca ortami yeniden hesapla
    DisposableEffect(Unit) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) { env = BtEnvironment.current(ctx) }
        }
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(LocationManager.MODE_CHANGED_ACTION)
        }
        ContextCompat.registerReceiver(ctx, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        onDispose { ctx.unregisterReceiver(receiver) }
    }
    LaunchedEffect(env) { vm.setScanning(env == Environment.READY) }

    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        requested = true
        env = BtEnvironment.current(ctx)
    }
    val btLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        env = BtEnvironment.current(ctx)
    }
    val activity = LocalActivity.current
    val permanentlyDenied = requested && env == Environment.NEEDS_PERMISSION && activity != null &&
        BtEnvironment.requiredPermissions.none { ActivityCompat.shouldShowRequestPermissionRationale(activity, it) }

    Column(Modifier.fillMaxSize().background(c.bg)) {
        val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
        Box(Modifier.weight(1f)) {
            val pad = PaddingValues(top = top)
            Crossfade(tab, animationSpec = motion(reduce, 200), label = "tabs") { t ->
                when (t) {
                    Tab.HEADSET ->
                        if (env == Environment.READY) HomeScreen(state, vm, pad)
                        else SetupScreen(
                            env, permanentlyDenied, pad,
                            onRequestPermission = { permLauncher.launch(BtEnvironment.requiredPermissions) },
                            onOpenAppSettings = { openAppSettings(ctx) },
                            onEnableBluetooth = { btLauncher.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)) },
                            onOpenLocationSettings = { ctx.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) },
                        )
                    Tab.PHONE -> PhoneScreen(pad)
                    Tab.SETTINGS -> SettingsScreen(pad, BtEnvironment.bluetoothEnabled(ctx)) { openAppSettings(ctx) }
                }
            }
        }
        BottomBar(tab) { tab = it }
    }
}

@Composable
private fun BottomBar(current: Tab, onSelect: (Tab) -> Unit) {
    val c = MaterialTheme.bt
    val reduce = rememberReduceMotion()
    Box(Modifier.background(c.bg).navigationBarsPadding().padding(horizontal = Space.lg, vertical = Space.sm)) {
        androidx.compose.material3.Surface(
            Modifier.fillMaxWidth(), shape = RoundedCornerShape(32.dp), color = c.card, shadowElevation = 4.dp,
        ) {
            Row(Modifier.padding(6.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Tab.entries.forEach { t ->
                    val selected = t == current
                    val w by androidx.compose.animation.core.animateFloatAsState(if (selected) 1.9f else 1f, motion(reduce, 200), label = "tabW")
                    val label = stringResource(t.label)
                    Box(
                        Modifier.weight(w).height(52.dp).clip(CircleShape)
                            .background(if (selected) c.navy else c.card)
                            .selectable(selected, role = Role.Tab) { onSelect(t) }
                            .semantics { contentDescription = label },
                        contentAlignment = Alignment.Center,
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(t.icon, null, Modifier.size(22.dp), tint = if (selected) c.onNavy else c.textSecondary)
                            if (selected) Text(label, style = BtType.rowTitle, color = c.onNavy, maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}
