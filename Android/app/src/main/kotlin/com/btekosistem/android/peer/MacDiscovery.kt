package com.btekosistem.android.peer

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.net.InetAddress

data class MacService(val serviceName: String, val id: String, val name: String, val host: InetAddress, val port: Int)

/** `_btekosistem._tcp` Bonjour/NSD kesfi. TXT: ad, surum, id. */
@Suppress("DEPRECATION")
class MacDiscovery(context: Context) {
    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val _found = MutableStateFlow<List<MacService>>(emptyList())
    val found: StateFlow<List<MacService>> = _found.asStateFlow()

    private val lock = Any()
    private var listener: NsdManager.DiscoveryListener? = null
    private val queue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false

    fun start() {
        synchronized(lock) {
            if (listener != null) return
            val l = object : NsdManager.DiscoveryListener {
                override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {}
                override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {}
                override fun onDiscoveryStarted(serviceType: String?) {}
                override fun onDiscoveryStopped(serviceType: String?) {}
                override fun onServiceFound(info: NsdServiceInfo) {
                    if (!info.serviceType.startsWith("_btekosistem._tcp")) return
                    synchronized(lock) { queue.addLast(info) }
                    pump()
                }
                override fun onServiceLost(info: NsdServiceInfo) {
                    _found.update { list -> list.filterNot { it.serviceName == info.serviceName } }
                }
            }
            listener = l
            try {
                nsd.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, l)
            } catch (e: Exception) {
                listener = null
            }
        }
    }

    /** Kesfi bastan baslatir (Mac yeniden baslayinca port/adres degisir; eski cozum bayatlar). */
    fun restart() {
        stop()
        start()
    }

    /** Son bilinen hizmet adini yeniden cozumler (kesif duyurusunu beklemeden). */
    fun resolveKnown(serviceName: String) {
        val info = NsdServiceInfo().apply { this.serviceName = serviceName; serviceType = TYPE }
        synchronized(lock) { queue.addLast(info) }
        pump()
    }

    fun stop() {
        synchronized(lock) {
            val l = listener ?: return
            listener = null
            queue.clear()
            resolving = false
            try { nsd.stopServiceDiscovery(l) } catch (_: Exception) { }
        }
        _found.value = emptyList()
    }

    private fun pump() {
        val next: NsdServiceInfo
        synchronized(lock) {
            if (resolving || queue.isEmpty()) return
            resolving = true
            next = queue.removeFirst()
        }
        try {
            nsd.resolveService(next, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) { done() }
                override fun onServiceResolved(info: NsdServiceInfo) {
                    try { accept(info) } finally { done() }
                }
            })
        } catch (e: Exception) {
            done()
        }
    }

    private fun done() {
        synchronized(lock) { resolving = false }
        pump()
    }

    private fun accept(info: NsdServiceInfo) {
        fun txt(k: String): String? = info.attributes?.get(k)?.toString(Charsets.UTF_8)
        val id = txt("id") ?: return
        val host = info.host ?: return
        val svc = MacService(info.serviceName, id, txt("ad") ?: info.serviceName, host, info.port)
        _found.update { list -> list.filterNot { it.serviceName == svc.serviceName } + svc }
    }

    private companion object {
        const val TYPE = "_btekosistem._tcp."
    }
}
