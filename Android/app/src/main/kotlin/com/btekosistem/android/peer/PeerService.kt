package com.btekosistem.android.peer

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.btekosistem.android.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/** Kalici "Mac'e bagli" bildirimi (foregroundServiceType connectedDevice). Mantik PeerManager'dadir. */
class PeerService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null
    private var started = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Notifs.ensureChannels(this)
        val n = build(R.string.svc_searching)
        if (started) return START_STICKY
        started = true
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIF_ID, n)
            }
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        android.util.Log.d("BTPeer", "servis basladi (intent=${intent != null})")
        val mgr = PeerManager.get(this)
        mgr.resumeIfEnabled(fromService = true)
        job?.cancel()
        job = scope.launch {
            var lastText = R.string.svc_searching
            mgr.state.map { it.phase }.distinctUntilChanged().collect { phase ->
                val text = when (phase) {
                    MacPhase.CONNECTED -> R.string.svc_connected
                    MacPhase.SAS -> R.string.svc_sas
                    MacPhase.CONNECTING, MacPhase.BACKOFF -> R.string.svc_reconnecting
                    MacPhase.KEY_CHANGED -> R.string.svc_key_changed
                    else -> R.string.svc_searching
                }
                if (text == lastText) return@collect
                lastText = text
                try { NotificationManagerCompat.from(this@PeerService).notify(NOTIF_ID, build(text)) } catch (_: SecurityException) { }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun build(text: Int): Notification =
        NotificationCompat.Builder(this, Notifs.CH_MAC)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle(getString(text))
            .setContentText(getString(R.string.svc_body))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(Notifs.openApp(this))
            .build()

    private companion object {
        const val NOTIF_ID = 1001
    }
}
