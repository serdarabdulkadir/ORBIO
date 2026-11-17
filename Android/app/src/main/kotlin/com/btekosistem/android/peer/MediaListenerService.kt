package com.btekosistem.android.peer

import android.service.notification.NotificationListenerService

/**
 * Bos bildirim dinleyici: tek amaci MediaSessionManager.getActiveSessions(ComponentName) icin
 * "bildirim erisimi" iznini almaktir. Bildirim icerigi okunmaz.
 */
class MediaListenerService : NotificationListenerService() {
    override fun onListenerConnected() {
        PeerManager.get(this).media.refresh()
    }

    override fun onListenerDisconnected() {
        PeerManager.get(this).media.refresh()
    }
}
