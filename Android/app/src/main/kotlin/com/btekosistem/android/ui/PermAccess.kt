package com.btekosistem.android.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.ActivityCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.btekosistem.android.ble.BtEnvironment
import com.btekosistem.android.peer.PhoneController

/** Tek bir calisma zamani iznin durumu. `act`: izin penceresini acar; kalici reddedildiyse uygulama ayarlarini acar. */
class PermAccess(val granted: Boolean, val blocked: Boolean, val act: () -> Unit)

fun openAppSettings(ctx: Context) {
    ctx.startActivity(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", ctx.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
}

@Composable
fun rememberPerm(perm: String): PermAccess {
    val ctx = LocalContext.current
    val activity = LocalActivity.current
    var tick by remember { mutableIntStateOf(0) }
    var asked by rememberSaveable(perm) { mutableStateOf(false) }
    LifecycleResumeEffect(Unit) {
        tick++
        onPauseOrDispose { }
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        asked = true
        tick++
        PhoneController.get(ctx).refreshGrants()
    }
    val granted = remember(tick) { BtEnvironment.isGranted(ctx, perm) }
    val blocked = asked && !granted && activity != null && !ActivityCompat.shouldShowRequestPermissionRationale(activity, perm)
    return PermAccess(granted, blocked) { if (blocked) openAppSettings(ctx) else launcher.launch(perm) }
}
