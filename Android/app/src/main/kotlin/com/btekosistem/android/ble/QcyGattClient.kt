package com.btekosistem.android.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.btekosistem.android.peer.IncomingKind
import com.btekosistem.android.peer.QcyIncoming
import com.btekosistem.android.peer.QcyTransport
import com.btekosistem.android.protocol.QcyChar
import com.btekosistem.android.protocol.QcyGatt
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.map
import java.util.UUID

sealed interface GattEvent {
    /** Servis bulundu ve yanit bildirimi acildi; komut gonderilebilir. */
    data object Ready : GattEvent
    data class Packet(val bytes: ByteArray) : GattEvent
    /** 000D (tus esleme) okumasi: ham baytlar. */
    data class KeyMap(val bytes: ByteArray) : GattEvent
    data object Disconnected : GattEvent
    data object ConnectFailed : GattEvent
    data object ServiceMissing : GattEvent
}

/** Dogrudan GATT aktarimi: yazmalar 1001 (ya da 000D / 000B), yanitlar 1002 bildiriminden, 000D okumasi ayri. */
class GattTransport(private val client: QcyGattClient) : QcyTransport {
    override suspend fun write(bytes: ByteArray, target: QcyChar): Boolean = client.write(bytes, target)
    override suspend fun readKeyMap(): Boolean = client.readKeyMap()
    override val incoming: Flow<QcyIncoming> = client.events.mapNotNull {
        when (it) {
            is GattEvent.Packet -> QcyIncoming(IncomingKind.RESPONSE, it.bytes)
            is GattEvent.KeyMap -> QcyIncoming(IncomingKind.KEYMAP, it.bytes)
            else -> null
        }
    }
}

/** A001 servisi: 1001'e writeNoResponse ile komut, 1002'den bildirim ile yanit. */
@SuppressLint("MissingPermission")
class QcyGattClient(private val context: Context) {
    private val _events = MutableSharedFlow<GattEvent>(extraBufferCapacity = 64)
    val events: SharedFlow<GattEvent> = _events.asSharedFlow()

    private var gatt: BluetoothGatt? = null
    private val chars = HashMap<QcyChar, BluetoothGattCharacteristic>()
    private var ready = false
    /** Anlasilan ATT MTU; varsayilan 23 (yuk 20 bayt). */
    @Volatile private var mtu = DEFAULT_MTU
    @Volatile private var pendingWrite: CompletableDeferred<Boolean>? = null
    /** Yazmalar (1001 / 000D / 000B) arasi en az ~150 ms: art arda yazma A2DP akisini bozabilir. */
    private val pacer = WritePacer(WRITE_GAP_MS)

    fun connect(device: BluetoothDevice) {
        close()
        Log.i(TAG, "connectGatt LE adres=${device.address}")
        try {
            gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            if (gatt == null) _events.tryEmit(GattEvent.ConnectFailed)
        } catch (_: SecurityException) {
            _events.tryEmit(GattEvent.ConnectFailed)
        }
    }

    fun close() {
        val g = gatt ?: return
        gatt = null; chars.clear(); ready = false
        try {
            g.disconnect()
            g.close()
        } catch (_: SecurityException) {
        }
    }

    /**
     * Hedef ozellige yazar. Paket MTU yukune sigmiyorsa (ornegin 77 bayt EQ) ya da ozellik yalniz yanitli yazmayi
     * destekliyorsa yanitli yazar ve sonucu bekler; aksi halde writeNoResponse. Mesgulse kisa araliklarla tekrar dener.
     */
    suspend fun write(bytes: ByteArray, target: QcyChar = QcyChar.COMMAND): Boolean {
        val g = gatt ?: return false
        val c = chars[target] ?: return false
        if (!ready) return false
        val gap = pacer.reserve(SystemClock.elapsedRealtime())
        if (gap > 0) delay(gap)
        val noResponse = c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0 &&
            bytes.size <= mtu - 3
        repeat(4) {
            if (noResponse) {
                if (writeOnce(g, c, bytes, BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)) return true
            } else {
                val done = CompletableDeferred<Boolean>()
                pendingWrite = done
                if (writeOnce(g, c, bytes, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)) {
                    val ok = withTimeoutOrNull(WRITE_TIMEOUT_MS) { done.await() } ?: false
                    pendingWrite = null
                    return ok
                }
                pendingWrite = null
            }
            delay(40)
        }
        return false
    }

    /** 000D okunmasini baslatir; deger `GattEvent.KeyMap` olarak gelir. Ozellik yoksa false. */
    suspend fun readKeyMap(): Boolean {
        val g = gatt ?: return false
        val c = chars[QcyChar.KEYMAP] ?: return false
        if (!ready) return false
        val gap = pacer.reserve(SystemClock.elapsedRealtime())
        if (gap > 0) delay(gap)
        repeat(4) {
            val started = try { g.readCharacteristic(c) } catch (_: SecurityException) { false }
            if (started) return true
            delay(40)
        }
        return false
    }

    private fun writeOnce(g: BluetoothGatt, c: BluetoothGattCharacteristic, bytes: ByteArray, type: Int): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(c, bytes, type) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                c.writeType = type
                c.value = bytes
                g.writeCharacteristic(c)
            }
        }
    } catch (_: SecurityException) {
        false
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            Log.i(TAG, "GATT durum status=$status yeni=$newState")
            if (g !== gatt) { g.close(); return }
            when (newState) {
                BluetoothProfile.STATE_CONNECTED ->
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        // Yuksek oncelik (HIGH) istemiyoruz: A2DP ile ayni 2.4 GHz'te yukun artmasi cizirti yapar.
                        try { g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_BALANCED) } catch (_: SecurityException) { }
                        // 77 baytlik EQ paketi icin buyuk MTU iste; olmazsa dogrudan servis kesfi.
                        val asked = try { g.requestMtu(REQUEST_MTU) } catch (_: SecurityException) { false }
                        if (!asked) g.discoverServices()
                    } else fail(g, GattEvent.ConnectFailed)
                BluetoothProfile.STATE_DISCONNECTED ->
                    fail(g, if (ready) GattEvent.Disconnected else GattEvent.ConnectFailed)
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, newMtu: Int, status: Int) {
            if (g !== gatt) return
            if (status == BluetoothGatt.GATT_SUCCESS) mtu = newMtu
            Log.i(TAG, "MTU status=$status mtu=$mtu")
            g.discoverServices()
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            pendingWrite?.complete(status == BluetoothGatt.GATT_SUCCESS)
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            if (g === gatt && status == BluetoothGatt.GATT_SUCCESS && c.uuid == QcyChar.KEYMAP.uuid) {
                _events.tryEmit(GattEvent.KeyMap(value))
            }
        }

        @Deprecated("Android 12 ve oncesi")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            @Suppress("DEPRECATION")
            val v = c.value ?: return
            onCharacteristicRead(g, c, v, status)
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (g !== gatt) return
            Log.i(TAG, "servisler status=$status: " + g.services.joinToString { it.uuid.toString().take(8) })
            val service = g.getService(QcyGatt.SERVICE)
            val cmd = service?.getCharacteristic(QcyGatt.COMMAND)
            val resp = service?.getCharacteristic(QcyGatt.RESPONSE)
            val cccd = resp?.getDescriptor(CCCD)
            if (status != BluetoothGatt.GATT_SUCCESS || cmd == null || resp == null || cccd == null) {
                Log.i(TAG, "A001 servisi/ozellikleri bulunamadi: Kontrol kanali bulunamadi")
                fail(g, GattEvent.ServiceMissing); return
            }
            Log.i(TAG, "A001 servisi bulundu")
            chars.clear()
            chars[QcyChar.COMMAND] = cmd
            service.getCharacteristic(QcyChar.KEYMAP.uuid)?.let { chars[QcyChar.KEYMAP] = it }
            service.getCharacteristic(QcyChar.LEGACY_EQ.uuid)?.let { chars[QcyChar.LEGACY_EQ] = it }
            Log.i(TAG, "000D ${if (QcyChar.KEYMAP in chars) "var" else "yok"}, 000B ${if (QcyChar.LEGACY_EQ in chars) "var" else "yok"}")
            g.setCharacteristicNotification(resp, true)
            val value = if (resp.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0)
                BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            else BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeDescriptor(cccd, value) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run { cccd.value = value; g.writeDescriptor(cccd) }
            }
            if (!started) fail(g, GattEvent.ServiceMissing)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (g !== gatt || descriptor.uuid != CCCD) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                ready = true
                Log.i(TAG, "kontrol kanali hazir")
                _events.tryEmit(GattEvent.Ready)
            } else fail(g, GattEvent.ServiceMissing)
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            if (g === gatt && c.uuid == QcyGatt.RESPONSE) _events.tryEmit(GattEvent.Packet(value))
        }

        @Deprecated("Android 12 ve oncesi")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            val v = c.value ?: return
            onCharacteristicChanged(g, c, v)
        }
    }

    private fun fail(g: BluetoothGatt, event: GattEvent) {
        if (g !== gatt) return
        gatt = null; chars.clear(); ready = false
        try { g.close() } catch (_: SecurityException) { }
        _events.tryEmit(event)
    }

    private companion object {
        const val TAG = "BTrack"
        const val DEFAULT_MTU = 23
        const val REQUEST_MTU = 247
        const val WRITE_TIMEOUT_MS = 2_000L
        const val WRITE_GAP_MS = 150L
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
