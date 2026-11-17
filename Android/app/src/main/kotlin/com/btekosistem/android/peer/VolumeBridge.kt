package com.btekosistem.android.peer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch

/** Medya sesi: seviye 0..100, sessiz bayragi. */
data class VolState(val level: Int, val muted: Boolean)

/** Sistem ses katmani (testte sahte). */
internal interface VolumePort {
    fun read(): VolState
    /** null alanlar degismez. */
    fun apply(level: Int?, muted: Boolean?)
    /** Sistem sesi degisince cagrilir. */
    fun setOnChange(cb: (() -> Unit)?)
}

internal class AndroidVolumePort(context: Context) : VolumePort {
    private val app = context.applicationContext
    private val am = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
    private var receiver: BroadcastReceiver? = null

    override fun read() = VolState(
        (am.getStreamVolume(AudioManager.STREAM_MUSIC) * 100f / max).toInt().coerceIn(0, 100),
        am.isStreamMute(AudioManager.STREAM_MUSIC),
    )

    override fun apply(level: Int?, muted: Boolean?) {
        try {
            if (level != null) am.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(level.coerceIn(0, 100) * max / 100f), 0)
            if (muted != null && muted != am.isStreamMute(AudioManager.STREAM_MUSIC)) {
                am.adjustStreamVolume(AudioManager.STREAM_MUSIC, if (muted) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE, 0)
            }
        } catch (_: SecurityException) { }
    }

    override fun setOnChange(cb: (() -> Unit)?) {
        receiver?.let { try { app.unregisterReceiver(it) } catch (_: Exception) { } }
        receiver = null
        if (cb == null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) = cb()
        }
        val f = IntentFilter().apply { addAction("android.media.VOLUME_CHANGED_ACTION"); addAction("android.media.STREAM_MUTE_CHANGED_ACTION") }
        if (Build.VERSION.SDK_INT >= 33) app.registerReceiver(r, f, Context.RECEIVER_NOT_EXPORTED) else app.registerReceiver(r, f)
        receiver = r
    }
}

/**
 * Telefon medya sesi <-> Mac ses kopurusu. Yerel degisim (200 ms debounce) `vol.state(telefon)` olarak gider;
 * Mac'ten gelen `vol.set(telefon)` uygulanir ve geri yayinlanmaz.
 */
class VolumeBridge internal constructor(
    private val port: VolumePort,
    private val scope: CoroutineScope,
    private val debounceMs: Long,
) {
    constructor(context: Context) : this(AndroidVolumePort(context), CoroutineScope(SupervisorJob() + Dispatchers.Default), 200)

    private val _local = MutableStateFlow(port.read())
    val local: StateFlow<VolState> = _local.asStateFlow()
    private val _mac = MutableStateFlow<VolState?>(null)
    val mac: StateFlow<VolState?> = _mac.asStateFlow()

    @Volatile private var sender: ((PeerMessage) -> Unit)? = null
    /** Mac'e son bildirilen (ya da Mac'in zaten bildigi) durum; ayni durum tekrar yollanmaz. */
    @Volatile private var lastSent: VolState? = null
    private var sendJob: Job? = null

    init { port.setOnChange { _local.value = port.read() } }

    /** Yerel ses (UI kadrani). Degisim normal yoldan Mac'e de bildirilir. */
    fun setLocal(level: Int?, muted: Boolean?) {
        port.apply(level, muted)
        _local.value = port.read()
    }

    fun setMac(level: Int?, muted: Boolean?) {
        val s = sender ?: return
        s(PeerMessage.VolSet("mac", level?.coerceIn(0, 100), muted))
        _mac.value?.let { cur -> _mac.value = VolState(level?.coerceIn(0, 100) ?: cur.level, muted ?: cur.muted) }
    }

    @OptIn(FlowPreview::class)
    fun attachMac(send: (PeerMessage) -> Unit) {
        sender = send
        sendJob?.cancel()
        lastSent = null
        _local.value = port.read()
        sendJob = scope.launch {
            _local.debounce(debounceMs).collect { s ->
                if (s != lastSent) { lastSent = s; send(PeerMessage.VolState("telefon", s.level, s.muted)) }
            }
        }
    }

    fun detachMac() {
        sender = null
        sendJob?.cancel(); sendJob = null
        _mac.value = null
    }

    fun onMacState(m: PeerMessage.VolState) {
        if (m.cihaz == "mac") _mac.value = VolState(m.seviye.coerceIn(0, 100), m.sessiz)
    }

    /** Mac'ten gelen `vol.set`: uygular, sonucu Mac zaten bildigi icin geri yayinlamaz. */
    fun onRemoteSet(m: PeerMessage.VolSet) {
        if (m.hedef != "telefon") return
        port.apply(m.seviye, m.sessiz)
        val s = port.read()
        lastSent = s
        _local.value = s
    }
}
