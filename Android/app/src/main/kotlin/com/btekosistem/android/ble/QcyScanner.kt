package com.btekosistem.android.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.SystemClock
import com.btekosistem.android.protocol.ProximityPairingParser
import com.btekosistem.android.protocol.QcyAdvertisement
import com.btekosistem.android.protocol.bytesOf

class ScanHit(val device: BluetoothDevice, val advertisement: QcyAdvertisement, val localName: String?, val rssi: Int)

/** Uretici verisi sirket kimligi 0x521C olan QCY reklamlarini ve (istenirse) Apple 0x004C Proximity Pairing reklamlarini yakalar. */
@SuppressLint("MissingPermission")
class QcyScanner(private val context: Context) {
    private var callback: ScanCallback? = null

    val isScanning: Boolean get() = callback != null

    fun start(onHit: (ScanHit) -> Unit, onFailed: (Int) -> Unit, onApple: ((AppleSighting) -> Unit)? = null, intensity: ScanIntensity = ScanIntensity.BALANCED): Boolean {
        if (callback != null) return true
        val scanner = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
            .adapter?.bluetoothLeScanner ?: return false
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) = handle(result)
            override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach(::handle)
            override fun onScanFailed(errorCode: Int) {
                callback = null
                onFailed(errorCode)
            }

            fun handle(r: ScanResult) {
                val record = r.scanRecord ?: return
                if (onApple != null) {
                    record.getManufacturerSpecificData(ProximityPairingParser.APPLE_COMPANY_ID)?.let { d ->
                        ProximityPairingParser.parsePayload(d)?.let { info ->
                            onApple(AppleSighting(r.device.address, info, r.rssi, SystemClock.elapsedRealtime()))
                        }
                    }
                }
                val data = record.getManufacturerSpecificData(QcyAdvertisement.COMPANY_ID) ?: return
                val adv = QcyAdvertisement.parse(data) ?: return
                onHit(ScanHit(r.device, adv, record.deviceName, r.rssi))
            }
        }
        // Varsayilan BALANCED (surekli LOW_LATENCY A2DP'de cizirti yapar) + yalniz QCY uretici verisi (0x521C) filtresi;
        // kayitli LE adresi yokken ACTIVE pencerede LOW_LATENCY (pencere kisa ve seyrek). Pencereleri ScanScheduler yonetir.
        val mode = if (intensity == ScanIntensity.LOW_LATENCY) ScanSettings.SCAN_MODE_LOW_LATENCY else ScanSettings.SCAN_MODE_BALANCED
        val settings = ScanSettings.Builder().setScanMode(mode).build()
        val filters = buildList {
            add(ScanFilter.Builder().setManufacturerData(QcyAdvertisement.COMPANY_ID, ByteArray(0)).build())
            // Apple: yalniz Proximity Pairing (tip 0x07, uzunluk 0x19) onekli yukler; diger Continuity trafigi donanimda elenir.
            if (onApple != null) add(
                ScanFilter.Builder().setManufacturerData(
                    ProximityPairingParser.APPLE_COMPANY_ID, bytesOf(0x07, 0x19), bytesOf(0xFF, 0xFF),
                ).build()
            )
        }
        return try {
            scanner.startScan(filters, settings, cb)
            callback = cb
            true
        } catch (_: SecurityException) {
            false
        } catch (_: IllegalStateException) {
            false
        }
    }

    fun stop() {
        val cb = callback ?: return
        callback = null
        try {
            (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
                .adapter?.bluetoothLeScanner?.stopScan(cb)
        } catch (_: SecurityException) {
        } catch (_: IllegalStateException) {
        }
    }
}
