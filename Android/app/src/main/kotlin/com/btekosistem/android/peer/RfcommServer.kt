package com.btekosistem.android.peer

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Build
import android.util.Log
import com.btekosistem.android.ble.BtEnvironment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

@SuppressLint("MissingPermission")
class BluetoothLink(private val socket: BluetoothSocket) : PeerLink {
    val address: String? = try { socket.remoteDevice?.address } catch (_: Exception) { null }
    override val path = PeerPath.BLUETOOTH
    override val input: InputStream get() = socket.inputStream
    override val output: OutputStream get() = socket.outputStream
    override fun close() { try { socket.close() } catch (_: Exception) { } }
}

/**
 * Yedek kanal: telefon RFCOMM SUNUCUDUR (guvenli/eslesmis), Mac SDP ile bu UUID'yi bulup baglanir.
 * Gelen her baglanti `onLink`e verilir; tek oturum kuralini ve Wi-Fi onceligini PeerManager uygular.
 */
@SuppressLint("MissingPermission")
class RfcommServer(private val context: Context, private val onLink: (BluetoothLink) -> Unit) {
    private var job: Job? = null
    @Volatile private var server: BluetoothServerSocket? = null

    @Synchronized
    fun start(scope: CoroutineScope) {
        if (job?.isActive == true) return
        job = scope.launch(Dispatchers.IO) { loop() }
    }

    @Synchronized
    fun stop() {
        job?.cancel(); job = null
        try { server?.close() } catch (_: Exception) { }
        server = null
    }

    private fun permitted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || BtEnvironment.isGranted(context, Manifest.permission.BLUETOOTH_CONNECT)

    private suspend fun loop() {
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        while (currentCoroutineContext().isActive) {
            if (adapter == null || !permitted() || !adapter.isEnabled) { delay(RETRY_MS); continue }
            val srv = try {
                adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, SERVICE_UUID)
            } catch (e: Exception) {
                Log.d(TAG, "RFCOMM dinleme acilamadi: $e")
                delay(RETRY_MS); continue
            }
            server = srv
            Log.d(TAG, "RFCOMM dinliyor")
            try {
                while (currentCoroutineContext().isActive) {
                    val s = srv.accept()
                    Log.d(TAG, "RFCOMM baglanti geldi")
                    onLink(BluetoothLink(s))
                }
            } catch (_: IOException) {
            } finally {
                try { srv.close() } catch (_: Exception) { }
                server = null
            }
            delay(3_000)
        }
    }

    companion object {
        private const val TAG = "BTPeer"
        private const val RETRY_MS = 10_000L
        const val SERVICE_NAME = "ORBIO Peer"
        val SERVICE_UUID: UUID = UUID.fromString("6f2a0b1e-4c1d-4e8a-9b3f-0a7c5e2d9b11")
    }
}
