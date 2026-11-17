package com.btekosistem.android.ble

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat

/** Ekranin gosterecegi ortam durumu; Ready degilse tarama baslamaz. */
enum class Environment { UNSUPPORTED, NEEDS_PERMISSION, BLUETOOTH_OFF, LOCATION_OFF, READY }

object BtEnvironment {
    /** Surume gore gereken calisma zamani izinleri. */
    val requiredPermissions: Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    val needsLocationService: Boolean get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S

    fun isGranted(context: Context, permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    fun allGranted(context: Context) = requiredPermissions.all { isGranted(context, it) }

    fun bluetoothEnabled(context: Context): Boolean =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter?.isEnabled == true

    fun locationEnabled(context: Context): Boolean {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        return LocationManagerCompat.isLocationEnabled(lm)
    }

    fun current(context: Context): Environment = when {
        !context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) -> Environment.UNSUPPORTED
        !allGranted(context) -> Environment.NEEDS_PERMISSION
        !bluetoothEnabled(context) -> Environment.BLUETOOTH_OFF
        needsLocationService && !locationEnabled(context) -> Environment.LOCATION_OFF
        else -> Environment.READY
    }
}
