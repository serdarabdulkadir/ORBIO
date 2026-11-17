package com.btekosistem.android.peer

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

enum class MediaCmd(val wire: String) {
    PLAY_PAUSE("oynat_duraklat"), PLAY("oynat"), PAUSE("duraklat"), NEXT("sonraki"), PREVIOUS("onceki");

    companion object {
        fun fromWire(s: String): MediaCmd? = entries.firstOrNull { it.wire == s }
    }
}

enum class MediaTarget { PHONE, MAC }

data class LocalMedia(
    val hasSession: Boolean = false,
    val playing: Boolean = false,
    val app: String? = null,
    val title: String? = null,
    val artist: String? = null,
    val art: Bitmap? = null,
)

/** LocalMedia -> `media.state` (kapak yollanmaz). */
internal fun LocalMedia.toMessage() = PeerMessage.MediaState(playing && hasSession, hasSession, app, title, artist)

/** Calan oturum oncelikli, yoksa ilk (sistemin sirasi). Bos listede -1. */
internal fun pickSessionIndex(playing: List<Boolean>): Int =
    playing.indexOfFirst { it }.let { if (it >= 0) it else if (playing.isEmpty()) -1 else 0 }

/** Telefon medya oturumunu izler (bildirim erisimi gerekir) ve Mac ile komut/durum koprusu kurar. */
class MediaBridge(context: Context) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val component = ComponentName(app, MediaListenerService::class.java)

    private val _local = MutableStateFlow(LocalMedia())
    val local: StateFlow<LocalMedia> = _local.asStateFlow()

    @Volatile private var controller: MediaController? = null
    @Volatile private var sender: ((PeerMessage) -> Unit)? = null
    private var sendJob: Job? = null
    private var watching: List<MediaController> = emptyList()
    private var registered = false

    private val sessionsListener = MediaSessionManager.OnActiveSessionsChangedListener { list -> rebuild(list.orEmpty()) }

    private val cb = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = refresh()
        override fun onMetadataChanged(metadata: MediaMetadata?) = refresh()
        override fun onSessionDestroyed() = refresh()
    }

    init { main.post { refresh() } }

    /** Erisim durumunu yeniden okur, oturumlara baglanir. Ana is parcaciginda calisir. */
    fun refresh() {
        if (Looper.myLooper() != Looper.getMainLooper()) { main.post { refresh() }; return }
        if (!hasAccess(app)) {
            Log.i("BTrack", "medya: bildirim erisimi yok")
            detach()
            _local.value = LocalMedia()
            return
        }
        val msm = app.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        try {
            if (!registered) { msm.addOnActiveSessionsChangedListener(sessionsListener, component, main); registered = true }
            rebuild(msm.getActiveSessions(component))
        } catch (e: SecurityException) {
            Log.i("BTrack", "medya: erisim reddedildi")
            registered = false
            _local.value = LocalMedia()
        }
    }

    private fun detach() {
        if (registered) {
            try {
                (app.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager).removeOnActiveSessionsChangedListener(sessionsListener)
            } catch (_: Exception) { }
            registered = false
        }
        watching.forEach { try { it.unregisterCallback(cb) } catch (_: Exception) { } }
        watching = emptyList()
        controller = null
    }

    private fun rebuild(list: List<MediaController>) {
        if (list.map { it.sessionToken } != watching.map { it.sessionToken }) {
            watching.forEach { try { it.unregisterCallback(cb) } catch (_: Exception) { } }
            list.forEach { it.registerCallback(cb, main) }
            watching = list
        }
        val i = pickSessionIndex(list.map { it.playbackState?.state == PlaybackState.STATE_PLAYING })
        val c = list.getOrNull(i)
        controller = c
        _local.value = if (c == null) LocalMedia() else {
            val md = c.metadata
            LocalMedia(
                hasSession = true,
                playing = c.playbackState?.state == PlaybackState.STATE_PLAYING,
                app = appLabel(c.packageName),
                title = md?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: md?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE),
                artist = md?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: md?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST),
                art = md?.let { smallArt(it) },
            )
        }
    }

    private fun appLabel(pkg: String): String? = try {
        app.packageManager.getApplicationLabel(app.packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { null }

    private fun smallArt(md: MediaMetadata): Bitmap? {
        val b = md.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART) ?: md.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: md.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON) ?: return null
        val max = 256
        if (b.width <= max && b.height <= max) return b
        val k = max.toFloat() / maxOf(b.width, b.height)
        return try { Bitmap.createScaledBitmap(b, (b.width * k).toInt().coerceAtLeast(1), (b.height * k).toInt().coerceAtLeast(1), true) } catch (_: Exception) { b }
    }

    /** Mac oturumu kuruldu: durum degisimleri (500 ms debounce) `media.state` olarak gider. */
    @OptIn(FlowPreview::class)
    fun attachMac(send: (PeerMessage) -> Unit) {
        sender = send
        sendJob?.cancel()
        main.post { refresh() }
        sendJob = scope.launch {
            _local.map { it.toMessage() }.distinctUntilChanged().debounce(500).collect { send(it) }
        }
    }

    fun detachMac() {
        sender = null
        sendJob?.cancel(); sendJob = null
    }

    fun command(target: MediaTarget, cmd: MediaCmd) {
        when (target) {
            MediaTarget.MAC -> sender?.invoke(PeerMessage.MediaCommand(cmd.wire))
            MediaTarget.PHONE -> main.post { applyLocal(cmd) }
        }
    }

    private fun applyLocal(cmd: MediaCmd) {
        val c = controller
        if (c != null) {
            try {
                val t = c.transportControls
                when (cmd) {
                    MediaCmd.PLAY_PAUSE -> if (c.playbackState?.state == PlaybackState.STATE_PLAYING) t.pause() else t.play()
                    MediaCmd.PLAY -> t.play()
                    MediaCmd.PAUSE -> t.pause()
                    MediaCmd.NEXT -> t.skipToNext()
                    MediaCmd.PREVIOUS -> t.skipToPrevious()
                }
                return
            } catch (e: Exception) { Log.i("BTrack", "medya: kontrol basarisiz, tusa dusuluyor") }
        }
        val code = when (cmd) {
            MediaCmd.PLAY_PAUSE -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            MediaCmd.PLAY -> KeyEvent.KEYCODE_MEDIA_PLAY
            MediaCmd.PAUSE -> KeyEvent.KEYCODE_MEDIA_PAUSE
            MediaCmd.NEXT -> KeyEvent.KEYCODE_MEDIA_NEXT
            MediaCmd.PREVIOUS -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
        }
        val am = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
    }

    companion object {
        fun hasAccess(context: Context): Boolean {
            val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
            val me = ComponentName(context, MediaListenerService::class.java)
            return flat.split(':').any { ComponentName.unflattenFromString(it) == me }
        }

        fun accessSettingsIntent(): Intent =
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
