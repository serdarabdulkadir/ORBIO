package com.btekosistem.android.peer

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import com.btekosistem.android.audio.AudioLinkMapper
import com.btekosistem.android.audio.AudioLink
import com.btekosistem.android.audio.AudioSnapshot
import com.btekosistem.android.audio.BondOutcome
import com.btekosistem.android.ble.BtEnvironment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

data class EarbudInfo(val address: String, val name: String, val connected: Boolean)

enum class EarbudResult(val wire: String) { OK("tamam"), UNSUPPORTED("desteklenmiyor"), FAILED("hata") }

/**
 * Kulakligin SES baglantisi (klasik Bluetooth: eslesme, A2DP, HFP). BLE GATT kontrol kanalindan ayri.
 * Mac'e `earbud.state` bilgisi ve `earbud.release/connect` istekleri de buradan gecer.
 */
@SuppressLint("MissingPermission")
class EarbudBridge(context: Context) {
    private val app = context.applicationContext
    private val adapter: BluetoothAdapter? = (app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val _state = MutableStateFlow<EarbudInfo?>(null)
    val state: StateFlow<EarbudInfo?> = _state.asStateFlow()
    private val _audio = MutableStateFlow(AudioSnapshot())
    val audio: StateFlow<AudioSnapshot> = _audio.asStateFlow()

    @Volatile private var hintAddress: String? = null
    private var started = false

    @Synchronized
    fun start() {
        if (started) return
        started = true
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        ContextCompat.registerReceiver(app, object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                    val dev = IntentCompat.getParcelableExtra(intent, BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    val prev = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, 10)
                    val now = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, 10)
                    if (dev?.address.equals(hintAddress, ignoreCase = true)) {
                        when (AudioLinkMapper.bondOutcome(prev, now)) {
                            BondOutcome.FAILED -> _audio.update { it.copy(pairFailed = true) }
                            BondOutcome.PAIRED -> _audio.update { it.copy(pairFailed = false) }
                            BondOutcome.NONE -> {}
                        }
                    }
                }
                scope.launch { refresh() }
            }
        }, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        scope.launch { refresh() }
    }

    /** Kontrol edilen kulakligin klasik Bluetooth adresi (reklamdaki controlAddress). */
    fun hint(address: String?) {
        val a = address?.uppercase()
        if (a == hintAddress) return
        hintAddress = a
        _audio.value = AudioSnapshot(address = a)
        scope.launch { refresh() }
    }

    private fun isEarbud(d: BluetoothDevice): Boolean =
        d.address.equals(hintAddress, ignoreCase = true) || (d.name?.contains("QCY", ignoreCase = true) == true)

    private class ProfInfo(val connected: List<BluetoothDevice>, val targetState: Int)

    suspend fun refresh() {
        val ad = adapter ?: return
        if (!BtEnvironment.allGranted(app) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        try {
            if (!ad.isEnabled) {
                _state.value = _state.value?.copy(connected = false)
                _audio.update { it.copy(a2dp = AudioLinkMapper.profileFromInt(0), hfp = AudioLinkMapper.profileFromInt(0)) }
                return
            }
            val bondedEarbuds = ad.bondedDevices.orEmpty().filter(::isEarbud)
            val target: BluetoothDevice? = hintAddress?.let { a -> runCatching { ad.getRemoteDevice(a) }.getOrNull() }
                ?: bondedEarbuds.firstOrNull()
            val a2 = profInfo(BluetoothProfile.A2DP, target)
            val hs = profInfo(BluetoothProfile.HEADSET, target)
            val connectedEarbud = (a2?.connected.orEmpty() + hs?.connected.orEmpty()).firstOrNull(::isEarbud)
            val dev = connectedEarbud ?: bondedEarbuds.firstOrNull()
            _state.value = dev?.let { EarbudInfo(it.address, it.name ?: "QCY", connectedEarbud != null) }

            if (target != null) {
                _audio.update { prev ->
                    val next = prev.copy(
                        address = target.address,
                        bond = AudioLinkMapper.bondFromInt(target.bondState),
                        a2dp = AudioLinkMapper.profileFromInt(a2?.targetState ?: 0),
                        hfp = AudioLinkMapper.profileFromInt(hs?.targetState ?: 0),
                    )
                    next.copy(
                        pairFailed = next.pairFailed && next.link == AudioLink.NOT_PAIRED,
                        connectFailed = next.connectFailed && next.link != AudioLink.CONNECTED,
                    )
                }
            }
        } catch (_: SecurityException) {
        }
    }

    private suspend fun profInfo(profile: Int, target: BluetoothDevice?): ProfInfo? = withProxy(profile) { p ->
        ProfInfo(p.connectedDevices.orEmpty(), target?.let { p.getConnectionState(it) } ?: 0)
    }

    private suspend fun <T> withProxy(profile: Int, block: (BluetoothProfile) -> T): T? {
        val ad = adapter ?: return null
        val proxy = withTimeoutOrNull(3000) {
            suspendCancellableCoroutine<BluetoothProfile?> { cont ->
                val l = object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(p: Int, proxy: BluetoothProfile) { if (cont.isActive) cont.resume(proxy) }
                    override fun onServiceDisconnected(p: Int) {}
                }
                if (!ad.getProfileProxy(app, l, profile) && cont.isActive) cont.resume(null)
            }
        } ?: return null
        try {
            return block(proxy)
        } finally {
            try { ad.closeProfileProxy(profile, proxy) } catch (_: Exception) { }
        }
    }

    // --- Eylemler (arayuz) ---

    /** Eslesmemis kulakligi eslestirir (createBond); sonuc ACTION_BOND_STATE_CHANGED ile gelir. */
    fun pair() {
        val a = hintAddress ?: return
        scope.launch {
            try {
                _audio.update { it.copy(pairFailed = false) }
                val ok = adapter?.getRemoteDevice(a)?.createBond() == true
                if (!ok) _audio.update { it.copy(pairFailed = true) }
            } catch (_: Exception) {
                _audio.update { it.copy(pairFailed = true) }
            }
            refresh()
        }
    }

    /** Eslesmis kulakligi ses icin baglamayi dener; olmazsa connectFailed (arayuz Bluetooth ayarlarina yonlendirir). */
    fun connectAudio() {
        val a = hintAddress ?: return
        scope.launch {
            _audio.update { it.copy(connectFailed = false) }
            val r = invoke("connect", a)
            if (r != EarbudResult.OK) {
                _audio.update { it.copy(connectFailed = true) }
            } else {
                delay(4000)
                refresh()
                if (_audio.value.link != AudioLink.CONNECTED) _audio.update { it.copy(connectFailed = true) }
            }
            refresh()
        }
    }

    // --- Eylemler (Mac istekleri) ---

    suspend fun release(address: String): EarbudResult = invoke("disconnect", address)

    private var focusRequest: android.media.AudioFocusRequest? = null

    /**
     * Mac "telefona gonder / geri al": ses profili telefonda bagliysa ses sahipligini al (ses odagi iste);
     * degilse gizli connect'i dene (olmazsa "desteklenmiyor").
     */
    suspend fun connect(address: String): EarbudResult {
        refresh()
        val snap = _audio.value
        if (snap.address.equals(address, ignoreCase = true) && snap.link == AudioLink.CONNECTED) {
            return if (takeAudioFocus()) EarbudResult.OK else EarbudResult.FAILED
        }
        return invoke("connect", address)
    }

    private fun takeAudioFocus(): Boolean = try {
        val am = app.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        val req = android.media.AudioFocusRequest.Builder(android.media.AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            .setOnAudioFocusChangeListener { }
            .build()
        focusRequest?.let { am.abandonAudioFocusRequest(it) }
        focusRequest = req
        am.requestAudioFocus(req) == android.media.AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    } catch (_: Exception) {
        false
    }

    /** Gizli BluetoothA2dp/BluetoothHeadset yontemlerini yansimayla dener; cokmez. */
    private suspend fun invoke(method: String, address: String): EarbudResult {
        val ad = adapter ?: return EarbudResult.FAILED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !BtEnvironment.isGranted(app, Manifest.permission.BLUETOOTH_CONNECT)) {
            return EarbudResult.FAILED
        }
        val dev = try { ad.getRemoteDevice(address.uppercase()) } catch (e: IllegalArgumentException) { return EarbudResult.FAILED }
        var supported = false
        var ok = false
        for (profile in intArrayOf(BluetoothProfile.A2DP, BluetoothProfile.HEADSET)) {
            val r: Boolean? = withProxy(profile) { proxy ->
                if (method == "connect") {
                    try {
                        val m = proxy.javaClass.getMethod("setConnectionPolicy", BluetoothDevice::class.java, Int::class.javaPrimitiveType)
                        m.invoke(proxy, dev, 100)
                    } catch (_: Throwable) { }
                }
                try {
                    val m = proxy.javaClass.getMethod(method, BluetoothDevice::class.java)
                    m.invoke(proxy, dev) as? Boolean
                } catch (_: Throwable) {
                    null
                }
            }
            if (r != null) {
                supported = true
                if (r) ok = true
            }
        }
        scope.launch { delay(1500); refresh() }
        return when {
            ok -> EarbudResult.OK
            supported -> EarbudResult.FAILED
            else -> EarbudResult.UNSUPPORTED
        }
    }
}
