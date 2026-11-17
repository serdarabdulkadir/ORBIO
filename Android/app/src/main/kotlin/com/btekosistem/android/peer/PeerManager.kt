package com.btekosistem.android.peer

import android.annotation.SuppressLint
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.util.Log
import android.os.Build
import android.provider.CallLog
import android.provider.ContactsContract
import android.os.SystemClock
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom

enum class MacPhase { OFF, SEARCHING, CONNECTING, SAS, CONNECTED, BACKOFF, KEY_CHANGED }

data class MacUi(
    val phase: MacPhase = MacPhase.OFF,
    val macName: String? = null,
    val sas: String? = null,
    val found: List<MacService> = emptyList(),
    val pairedName: String? = null,
    val reason: MacReason? = null,
    /** Son basarili baglanti (epoch ms), 0 = hic. */
    val lastConnectedAt: Long = 0L,
    /** Bagli oturumun yolu (Wi-Fi / Bluetooth); bagli degilse null. */
    val path: PeerPath? = null,
)

/**
 * Mac baglantisinin sahibi (surec boyu tek): kesif, TCP istemci, el sikisma/SAS/pin, sifreli oturum, yeniden baglanma.
 * On plan servisi (PeerService) yalnizca surecin oldurulmemesi ve kalici bildirim icindir.
 */
class PeerManager private constructor(context: Context) {
    private val app = context.applicationContext
    val store = PeerStore(app)
    val phone = PhoneController.get(app)
    val earbud = EarbudBridge(app)
    val relay = ControlRelay()
    val media = MediaBridge(app)
    val volume = VolumeBridge(app)
    private val reader = ContactsReader(app)
    private val discovery = MacDiscovery(app)
    private val rfcomm = RfcommServer(app) { link -> onBluetoothLink(link) }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val _state = MutableStateFlow(MacUi(pairedName = store.pinned.value?.name, lastConnectedAt = store.lastConnected))
    val state: StateFlow<MacUi> = _state.asStateFlow()

    private var loop: Job? = null
    @Volatile private var selection: MacService? = null
    /** Mac'te uretilen 6 haneli eslesme kodu; yalniz ilk eslesme denemesinde kullanilir. */
    @Volatile private var pairCode: String? = null
    @Volatile private var inbox: Channel<Input>? = null
    private val kick = Channel<Unit>(Channel.CONFLATED)
    private val backoff = ReconnectBackoff()
    @Volatile private var resetRequested = false
    @Volatile private var lastTarget: MacService? = null
    private var netCallback: ConnectivityManager.NetworkCallback? = null

    private val pathLock = Any()
    private var wifiFound: List<MacService> = emptyList()
    private var btFound: List<MacService> = emptyList()
    /** Kullanicinin ilk eslesme icin sectigi Bluetooth cihazi (adres) ve pencere sonu; RFCOMM bu sure kabul modunda. */
    @Volatile private var btPairAddress: String? = null
    @Volatile private var btPairName: String = ""
    @Volatile private var btPairUntil = 0L
    /** Wi-Fi oturumu kuruldu / kuruluyor (Bluetooth gelirse reddedilir). */
    @Volatile private var wifiBusy = false
    /** Bluetooth (RFCOMM) oturumu acik / aciliyor. */
    @Volatile private var btActive = false
    private var btJob: Job? = null
    @Volatile private var activePath = PeerPath.WIFI

    private sealed interface Input {
        class Bytes(val data: ByteArray) : Input
        data object Eof : Input
        class Sas(val accepted: Boolean) : Input
        class Out(val message: PeerMessage) : Input
    }

    private enum class Outcome { ENDED, FAILED, KEY_CHANGED, REJECTED, PAIR_REFUSED }

    init {
        scope.launch { discovery.found.collect { f -> wifiFound = f; publishFound() } }
        scope.launch { store.pinned.collect { p -> _state.update { it.copy(pairedName = p?.name) } } }
    }

    // --- Arayuz API ---

    @Synchronized
    fun enable() {
        store.enabled = true
        startService()
        startLoop()
    }

    @Synchronized
    fun resumeIfEnabled(fromService: Boolean = false) {
        if (store.enabled) {
            // Servisin kendi onStartCommand'indan tekrar startService cagrilirsa sonsuz bildirim dongusu olusur.
            if (!fromService) startService()
            startLoop()
        }
    }

    @Synchronized
    fun disable() {
        store.enabled = false
        loop?.cancel(); loop = null
        btJob?.cancel()
        rfcomm.stop()
        discovery.stop()
        unregisterNetwork()
        try { app.stopService(Intent(app, PeerService::class.java)) } catch (_: Exception) { }
        _state.update { it.copy(phase = MacPhase.OFF, sas = null) }
    }

    /** Ilk eslesme: `code` null ise kodsuz denenir; Mac kod isterse (hs_red kod_gerekli) arayuz kodu sorup yeniden cagirir. Sonuc/hata `state.reason` ile gorunur. */
    fun pair(mac: MacService, code: String?) {
        setReason(null)
        pairCode = code
        if (PeerPathPolicy.isProvisionalId(mac.id)) {
            // Bluetooth ile eslesme: Bonjour yok; Mac RFCOMM ile baglanacak, o adresten gelen baglanti kabul edilir.
            btPairAddress = mac.id.removePrefix(PeerPathPolicy.BT_ID_PREFIX)
            btPairName = mac.name
            btPairUntil = SystemClock.elapsedRealtime() + BT_PAIR_WINDOW_MS
            selection = null
            return
        }
        selection = mac
    }

    /** "Yeniden baglan": geri cekilmeyi sifirlar ve hemen dener (dongu yoksa baslatir). */
    @Synchronized
    fun reconnectNow() {
        Log.d(TAG, "reconnectNow")
        if (!store.enabled) store.enabled = true
        startService()
        startLoop()
        resetRequested = true
        kick.trySend(Unit)
    }

    fun confirmSas(accepted: Boolean) { inbox?.trySend(Input.Sas(accepted)) }

    @Synchronized
    fun unpair() {
        store.unpin()
        selection = null
        btJob?.cancel()
        if (store.enabled) {
            loop?.cancel(); loop = null
            startLoop()
        } else {
            _state.update { it.copy(phase = MacPhase.OFF) }
        }
    }

    private fun startService() {
        try {
            ContextCompat.startForegroundService(app, Intent(app, PeerService::class.java))
        } catch (_: Exception) { }
    }

    private fun startLoop() {
        if (loop?.isActive == true) return
        loop = scope.launch { try { runLoop() } finally { rfcomm.stop() } }
    }

    private fun setPhase(phase: MacPhase, name: String? = null) {
        // Bluetooth oturumu aciksa Wi-Fi arama dongusu durumu ezmez.
        if (btActive && phase in BT_GUARDED) return
        if (_state.value.phase != phase) Log.d(TAG, "durum ${_state.value.phase} -> $phase")
        _state.update { it.copy(phase = phase, macName = name ?: it.macName, sas = if (phase == MacPhase.SAS) it.sas else null) }
    }

    private fun publishFound() { _state.update { it.copy(found = wifiFound + btFound) } }

    /** Eslesmis Bluetooth cihazlarindan bilgisayar sinifindakiler ("Bluetooth ile" listesi). */
    @SuppressLint("MissingPermission")
    private fun refreshBtCandidates() {
        val list = try {
            (app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter?.bondedDevices.orEmpty()
                .filter { it.bluetoothClass?.majorDeviceClass == BluetoothClass.Device.Major.COMPUTER }
                .map { MacService(PeerPathPolicy.BT_ID_PREFIX + it.address, PeerPathPolicy.BT_ID_PREFIX + it.address, it.name ?: it.address, InetAddress.getLoopbackAddress(), 0) }
        } catch (_: SecurityException) { emptyList() }
        if (list.map { it.id } != btFound.map { it.id }) { btFound = list; publishFound() }
    }

    private fun setReason(r: MacReason?) = _state.update { it.copy(reason = r) }

    private fun registerNetwork() {
        if (netCallback != null) return
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(TAG, "ag geldi/degisti: geri cekilme sifirlandi")
                if (_state.value.phase != MacPhase.CONNECTED || btActive) reconnectSignal()
            }

            override fun onLost(network: Network) { Log.d(TAG, "ag kayboldu") }
        }
        try {
            cm.registerDefaultNetworkCallback(cb)
            netCallback = cb
        } catch (e: Exception) {
            Log.d(TAG, "ag izleme baslamadi: $e")
        }
    }

    private fun unregisterNetwork() {
        val cb = netCallback ?: return
        netCallback = null
        try { (app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(cb) } catch (_: Exception) { }
    }

    private fun reconnectSignal() {
        resetRequested = true
        kick.trySend(Unit)
    }

    private suspend fun pause(ms: Long) { withTimeoutOrNull(ms) { kick.receive() } }

    private suspend fun awaitTarget(id: String): MacService? {
        val deadline = SystemClock.elapsedRealtime() + DISCOVERY_WAIT_MS
        while (SystemClock.elapsedRealtime() < deadline) {
            discovery.found.value.firstOrNull { it.id == id }?.let { return it }
            delay(250)
        }
        return null
    }

    // --- Dongu ---

    private suspend fun runLoop() {
        registerNetwork()
        rfcomm.start(scope)
        discovery.start()
        phone.ensureStarted()
        earbud.start()
        while (currentCoroutineContext().isActive) {
            if (resetRequested) { resetRequested = false; backoff.reset() }
            val pinned = store.pinned.value
            var target: MacService?
            if (pinned != null) {
                // Her denemede kesfi yeniden baslat: Mac yeniden baslayinca port degisir, eski adres bayatlar.
                setPhase(MacPhase.SEARCHING, pinned.name)
                discovery.restart()
                lastTarget?.takeIf { it.id == pinned.id }?.let { discovery.resolveKnown(it.serviceName) }
                target = awaitTarget(pinned.id)
                Log.d(TAG, "kesif: " + (target?.let { "${it.host}:${it.port}" } ?: "bulunamadi") + " (bulunan=${discovery.found.value.size})")
                if (target == null && !btActive) target = lastTarget?.takeIf { it.id == pinned.id }?.also { Log.d(TAG, "son bilinen adres deneniyor ${it.host}:${it.port}") }
            } else {
                refreshBtCandidates()
                target = selection
                if (target == null) {
                    setPhase(MacPhase.SEARCHING)
                    delay(1000)
                    continue
                }
            }
            var outcome: Outcome? = null
            if (target != null) {
                selection = null
                lastTarget = target
                setPhase(MacPhase.CONNECTING, target.name)
                outcome = try {
                    connectOnce(target, pinned, if (pinned == null) pairCode else null)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.d(TAG, "baglanma hatasi: $e")
                    setReason(MacReason.from(e))
                    Outcome.FAILED
                }
                if (pinned == null) pairCode = null   // kod tek denemelik; yeniden denemek icin yeni kod girilir
                Log.d(TAG, "sonuc: $outcome")
                when (outcome) {
                    Outcome.KEY_CHANGED -> { setPhase(MacPhase.KEY_CHANGED, target.name); return }
                    Outcome.REJECTED -> setReason(MacReason.HANDSHAKE)
                    Outcome.PAIR_REFUSED -> {}   // neden connectOnce icinde yazildi
                    Outcome.ENDED -> { backoff.reset(); setReason(MacReason.LOST) }
                    Outcome.FAILED -> if (_state.value.reason == null) setReason(MacReason.HANDSHAKE)
                }
            } else {
                setReason(MacReason.NOT_FOUND)
            }
            if (store.pinned.value == null) { setPhase(MacPhase.SEARCHING); continue }
            setPhase(MacPhase.BACKOFF, store.pinned.value?.name)
            val wait = backoff.next()
            Log.d(TAG, "geri cekilme: $wait ms (neden=${_state.value.reason})")
            pause(wait)
        }
    }

    /** Wi-Fi: once TCP baglanir; basariliysa varsa Bluetooth oturumu kapatilir (oncelik Wi-Fi) ve ortak oturum kodu calisir. */
    private suspend fun connectOnce(target: MacService, pinned: PinnedMac?, code: String?): Outcome {
        val socket = Socket()
        try {
            withContext(Dispatchers.IO) {
                socket.connect(InetSocketAddress(target.host, target.port), CONNECT_TIMEOUT_MS)
                socket.tcpNoDelay = true
            }
            val bt = synchronized(pathLock) { wifiBusy = true; btJob }
            if (PeerPathPolicy.switchToWifi(btActive, true)) Log.d(TAG, "Wi-Fi'de Mac bulundu: Bluetooth kapatiliyor")
            bt?.cancelAndJoin()
            return runSession(SocketLink(socket), target.id, target.name, pinned, code)
        } finally {
            wifiBusy = false
            try { socket.close() } catch (_: Exception) { }
        }
    }

    /** Gelen RFCOMM baglantisi: yalniz eslesmis Mac, Wi-Fi oturumu yokken, tek oturum. */
    private fun onBluetoothLink(link: BluetoothLink) {
        val pinned = store.pinned.value
        val pairingOpen = pinned == null && SystemClock.elapsedRealtime() < btPairUntil &&
            PeerPathPolicy.pairingAddressMatches(btPairAddress, link.address)
        val ok = synchronized(pathLock) {
            if (PeerPathPolicy.acceptBluetooth(wifiBusy, btActive, pinned != null, pairingOpen)) { btActive = true; true } else false
        }
        if (!ok) { Log.d(TAG, "RFCOMM reddedildi"); link.close(); return }
        val id = pinned?.id ?: (PeerPathPolicy.BT_ID_PREFIX + link.address)
        val name = pinned?.name ?: btPairName
        val code = if (pinned == null) pairCode else null
        btJob = scope.launch {
            try {
                if (runSession(link, id, name, pinned, code) == Outcome.KEY_CHANGED) {
                    btActive = false
                    setPhase(MacPhase.KEY_CHANGED, name)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.d(TAG, "RFCOMM oturum hatasi: $e")
            } finally {
                synchronized(pathLock) { btActive = false }
                link.close()
                if (pinned == null) { pairCode = null; if (store.pinned.value != null) btPairUntil = 0L }   // kod tek denemelik
                if (_state.value.phase == MacPhase.CONNECTED || _state.value.phase == MacPhase.CONNECTING) setPhase(MacPhase.SEARCHING, store.pinned.value?.name)
                if (!wifiBusy) reconnectSignal()
            }
        }
    }

    private suspend fun runSession(link: PeerLink, targetId: String, targetName: String, pinned: PinnedMac?, code: String?): Outcome = coroutineScope {
        val identity = store.identity()
        val box = Channel<Input>(Channel.UNLIMITED)
        var broadcasters: Job? = null
        activePath = link.path
        try {
            val out = link.output
            val nonce = ByteArray(16).also { SecureRandom().nextBytes(it) }
            val info = phone.info.value
            val session = PeerSession(
                PeerRole.TELEFON, identity.privateKey, identity.publicBytes, info.ad, pinned?.pub, nonce,
                PeerMessage.Hello(info.ad, VERSION, 1, store.deviceId, "android"), code,
            )
            inbox = box
            launch(Dispatchers.IO) {
                val buf = ByteArray(16 * 1024)
                try {
                    val ins = link.input
                    while (true) {
                        val n = ins.read(buf)
                        if (n < 0) break
                        box.trySend(Input.Bytes(buf.copyOf(n)))
                    }
                } catch (_: Exception) { }
                box.trySend(Input.Eof)
            }

            var established = false
            var outcome: Outcome? = null
            val started = SystemClock.elapsedRealtime()
            var sasDeadline = Long.MAX_VALUE
            var lastRx = started
            var lastPing = started
            var nextId = 1L

            suspend fun write(bytes: ByteArray) = withContext(Dispatchers.IO) { out.write(bytes); out.flush() }

            suspend fun apply(events: List<PeerEvent>) {
                for (e in events) {
                    when (e) {
                        is PeerEvent.Send -> write(e.bytes)
                        is PeerEvent.SasRequired -> {
                            _state.update { it.copy(phase = MacPhase.SAS, sas = e.code) }
                            sasDeadline = SystemClock.elapsedRealtime() + SAS_TIMEOUT_MS
                        }
                        is PeerEvent.Paired -> { store.pin(PinnedMac(targetId, targetName, e.peerPub)); pairCode = null }
                        is PeerEvent.Ready -> {
                            established = true
                            backoff.reset()
                            val nowMs = System.currentTimeMillis()
                            store.lastConnected = nowMs
                            _state.update { it.copy(reason = null, lastConnectedAt = nowMs, path = link.path) }
                            sasDeadline = Long.MAX_VALUE
                            setPhase(MacPhase.CONNECTED, targetName)
                            relay.sessionStarted { m -> box.trySend(Input.Out(m)) }
                            media.attachMac { m -> box.trySend(Input.Out(m)) }
                            volume.attachMac { m -> box.trySend(Input.Out(m)) }
                            broadcasters = launch { broadcast(box) }
                        }
                        is PeerEvent.Received -> {
                            for (reply in handle(e.message)) {
                                for (se in session.send(reply)) if (se is PeerEvent.Send) write(se.bytes)
                            }
                        }
                        is PeerEvent.Closed -> outcome = when (e.reason) {
                            CloseReason.PAIR_REFUSED -> {
                                setReason(when (session.refusal) {
                                    "kod_yanlis" -> MacReason.PAIR_WRONG
                                    "kilitli" -> MacReason.PAIR_LOCKED
                                    else -> MacReason.PAIR_NEED_CODE
                                })
                                Outcome.PAIR_REFUSED
                            }
                            CloseReason.KEY_CHANGED -> Outcome.KEY_CHANGED
                            CloseReason.SAS_REJECTED -> Outcome.REJECTED
                            else -> if (established) Outcome.ENDED else Outcome.FAILED
                        }
                    }
                }
            }

            try {
                apply(session.start())
                while (outcome == null) {
                    val input = withTimeoutOrNull(1000) { box.receive() }
                    val now = SystemClock.elapsedRealtime()
                    when (input) {
                        null -> {}
                        is Input.Bytes -> { lastRx = now; apply(session.receive(input.data)) }
                        Input.Eof -> outcome = if (established) Outcome.ENDED else Outcome.FAILED
                        is Input.Sas -> apply(session.confirmSas(input.accepted))
                        is Input.Out -> if (established) apply(session.send(input.message))
                    }
                    if (outcome != null) break
                    if (session.phase == PeerSession.Phase.HANDSHAKE && now - started > HANDSHAKE_TIMEOUT_MS) outcome = Outcome.FAILED
                    if (now > sasDeadline) outcome = Outcome.FAILED
                    if (established) {
                        if (now - lastRx > IDLE_TIMEOUT_MS) {
                            outcome = Outcome.ENDED
                        } else if (now - lastPing > PING_MS) {
                            lastPing = now
                            apply(session.send(PeerMessage.Ping(nextId++)))
                        }
                    }
                }
            } catch (e: IOException) {
                outcome = if (established) Outcome.ENDED else Outcome.FAILED
            }
            outcome ?: Outcome.FAILED
        } finally {
            inbox = null
            media.detachMac()
            volume.detachMac()
            relay.sessionEnded()
            broadcasters?.cancel()
            _state.update { it.copy(path = null) }
            link.close()
        }
    }

    /** Oturum kurulunca: perm.state, phone.state, call.state, earbud.state; sonra degisiklikler. */
    private suspend fun broadcast(box: Channel<Input>) = coroutineScope {
        fun out(m: PeerMessage) { box.trySend(Input.Out(m)) }
        earbud.start()
        launch { earbud.refresh() }
        launch(start = CoroutineStart.UNDISPATCHED) {
            combine(store.settings, phone.grants) { s, g ->
                PeerMessage.PermState(
                    cagriYonetimi = s.callControl && (g.answer || g.call),
                    kisiler = s.contacts && g.contacts,
                    aramaGecmisi = s.callLog && g.callLog,
                )
            }.distinctUntilChanged().collect { out(it) }
        }
        launch(start = CoroutineStart.UNDISPATCHED) {
            phone.info.collect { out(PeerMessage.PhoneState(it.ad, it.model, it.pil, it.sarj, it.sinyal, it.ag)) }
        }
        launch(start = CoroutineStart.UNDISPATCHED) {
            phone.call.collect { c ->
                val sure = c.startedAt?.let { ((SystemClock.elapsedRealtime() - it) / 1000).toInt() }
                Log.d(TAG, "call.state gonder: ${c.durum} sure=$sure")
                out(PeerMessage.CallState(c.durum, c.yon, c.numara, c.kisiAdi, sure))
            }
        }
        // Arama surerken sure saniyede bir guncellenir (Mac balonu sureyi gosterir).
        launch(start = CoroutineStart.UNDISPATCHED) {
            while (true) {
                delay(1000)
                val c = phone.call.value
                val st = c.startedAt
                if ((c.durum == "acik" || c.durum == "araniyor") && st != null) {
                    out(PeerMessage.CallState(c.durum, c.yon, c.numara, c.kisiAdi, ((SystemClock.elapsedRealtime() - st) / 1000).toInt()))
                }
            }
        }
        // Rehber / arama kaydi degisti: Mac artimli yeniden senkron ister (izin aciksa).
        launch(start = CoroutineStart.UNDISPATCHED) {
            reader.changes(ContactsContract.Contacts.CONTENT_URI).collect {
                if (store.settings.value.contacts && phone.grants.value.contacts) out(PeerMessage.ContactsChanged())
            }
        }
        launch(start = CoroutineStart.UNDISPATCHED) {
            reader.changes(CallLog.Calls.CONTENT_URI).collect {
                if (store.settings.value.callLog && phone.grants.value.callLog) out(PeerMessage.CallLogChanged())
            }
        }
        launch(start = CoroutineStart.UNDISPATCHED) {
            earbud.state.collect { e ->
                if (e != null) out(PeerMessage.EarbudState(e.address, e.name, if (e.connected) "telefon" else "bos"))
            }
        }
    }

    // --- Mac isteklerini isleme ---

    private fun denied(id: Long?, key: String) = listOf<PeerMessage>(PeerMessage.Err("izin_yok", key, id))

    private fun result(id: Long?, r: ActionResult): List<PeerMessage> = when (r) {
        ActionResult.OK -> emptyList()
        ActionResult.NO_PERMISSION -> denied(id, "cagriYonetimi")
        ActionResult.UNSUPPORTED -> listOf(PeerMessage.Err("desteklenmiyor", "Bu telefon aramayı uygulamadan sonlandırmaya izin vermiyor", id))
        ActionResult.INVALID -> listOf(PeerMessage.Err("gecersiz_istek", "numara", id))
        ActionResult.FAILED -> listOf(PeerMessage.Err("hata", "Arama sonlandırılamadı", id))
    }

    private suspend fun handle(m: PeerMessage): List<PeerMessage> {
        val s = store.settings.value
        return when (m) {
            is PeerMessage.Ping -> listOf(PeerMessage.Pong(m.id))
            is PeerMessage.Hello -> {
                _state.update { it.copy(macName = m.ad) }
                // Bluetooth ile ilk eslesmede gecici kimlik ("bt:adres") Mac'in gercek cihaz kimligiyle degistirilir (Bonjour TXT id ile ayni).
                store.pinned.value?.let { p -> if (PeerPathPolicy.isProvisionalId(p.id) && m.cihazId.isNotBlank()) store.pin(PinnedMac(m.cihazId, p.name, p.pub)) }
                emptyList()
            }
            is PeerMessage.CallAnswer -> if (!s.callControl) denied(m.id, "cagriYonetimi") else result(m.id, phone.answer())
            is PeerMessage.CallReject, is PeerMessage.CallHangup ->
                if (!s.callControl) denied(m.id, "cagriYonetimi") else result(m.id, phone.endCall())
            is PeerMessage.CallDial -> if (!s.callControl) denied(m.id, "cagriYonetimi") else result(m.id, phone.dial(m.numara))
            is PeerMessage.ContactsSearch ->
                if (!s.contacts || !phone.grants.value.contacts) denied(m.id, "kisiler")
                else listOf(PeerMessage.ContactsResult(phone.searchContacts(m.sorgu), m.id))
            is PeerMessage.CallLogRecent ->
                if (!s.callLog || !phone.grants.value.callLog) denied(m.id, "aramaGecmisi")
                else listOf(PeerMessage.CallLogResult(phone.recentCalls((m.adet ?: 20).coerceIn(1, 100)), m.id))
            is PeerMessage.ContactsSync ->
                if (!s.contacts || !phone.grants.value.contacts) denied(m.id, "kisiler")
                else {
                    val page = reader.contactsPage(m.ofset, m.adet)
                    listOf(PeerMessage.ContactsPage(m.ofset.coerceAtLeast(0), page.toplam, ContactPaging.isLast(m.ofset.coerceAtLeast(0), page.kisiler.size, page.toplam), page.kisiler, m.id))
                }
            is PeerMessage.CallLogSync ->
                if (!s.callLog || !phone.grants.value.callLog) denied(m.id, "aramaGecmisi")
                else {
                    val page = reader.callLogPage(m.ofset, m.adet)
                    listOf(PeerMessage.CallLogPage(m.ofset.coerceAtLeast(0), page.toplam, ContactPaging.isLast(m.ofset.coerceAtLeast(0), page.kayitlar.size, page.toplam), page.kayitlar, m.id))
                }
            is PeerMessage.EarbudRelease -> {
                val r = if (!s.autoSwitch) EarbudResult.FAILED else earbud.release(m.cihazAdresi)
                listOf(PeerMessage.EarbudReleaseResult(r.wire, m.cihazAdresi, m.id))
            }
            is PeerMessage.EarbudConnect -> {
                val r = if (!s.autoSwitch) EarbudResult.FAILED else earbud.connect(m.cihazAdresi)
                listOf(PeerMessage.EarbudConnectResult(r.wire, m.cihazAdresi, m.id))
            }
            is PeerMessage.CtlOwner, is PeerMessage.CtlWrite, is PeerMessage.CtlNotify -> { relay.onMessage(m); emptyList() }
            is PeerMessage.MediaCommand -> { MediaCmd.fromWire(m.komut)?.let { media.command(MediaTarget.PHONE, it) }; emptyList() }
            is PeerMessage.VolState -> { volume.onMacState(m); emptyList() }
            is PeerMessage.VolSet -> { volume.onRemoteSet(m); emptyList() }
            is PeerMessage.Unknown ->
                if (!PeerPathPolicy.fileTransferAllowed(activePath) && PeerPathPolicy.isTransferType(m.type))
                    listOf(PeerMessage.Err("bt_dosya_kapali", "Yalnız Bluetooth, dosya aktarımı kapalı", m.id))
                else listOf(PeerMessage.Err("bilinmeyen_tip", m.type, m.id))
            else -> emptyList()
        }
    }

    companion object {
        private const val TAG = "BTPeer"
        private const val DISCOVERY_WAIT_MS = 6_000L
        private const val BT_PAIR_WINDOW_MS = 120_000L
        private val BT_GUARDED = setOf(MacPhase.SEARCHING, MacPhase.CONNECTING, MacPhase.BACKOFF)
        private const val VERSION = "0.2.0"
        private const val CONNECT_TIMEOUT_MS = 5_000
        private const val HANDSHAKE_TIMEOUT_MS = 10_000L
        private const val SAS_TIMEOUT_MS = 60_000L
        private const val IDLE_TIMEOUT_MS = 45_000L
        private const val PING_MS = 15_000L

        @Volatile private var instance: PeerManager? = null

        fun get(context: Context): PeerManager =
            instance ?: synchronized(this) { instance ?: PeerManager(context).also { instance = it } }
    }
}
