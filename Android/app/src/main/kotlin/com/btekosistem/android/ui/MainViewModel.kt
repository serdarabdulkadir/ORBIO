package com.btekosistem.android.ui

import android.annotation.SuppressLint
import android.app.Application
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.os.SystemClock
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.btekosistem.android.ble.GattEvent
import com.btekosistem.android.ble.GattTransport
import com.btekosistem.android.ble.QcyGattClient
import com.btekosistem.android.ble.AppleSelector
import com.btekosistem.android.ble.AppleSighting
import com.btekosistem.android.ble.AutoConnect
import com.btekosistem.android.ble.LeAddressBook
import com.btekosistem.android.ble.LeDevices
import com.btekosistem.android.ble.PrefsKeyValueStore
import com.btekosistem.android.ble.ScanPolicy
import com.btekosistem.android.ble.QcyNames
import com.btekosistem.android.ble.QcyScanner
import com.btekosistem.android.ble.ScanHit
import com.btekosistem.android.ble.ScanProfile
import com.btekosistem.android.ble.ScanScheduler
import com.btekosistem.android.peer.IncomingKind
import com.btekosistem.android.peer.LocalMedia
import com.btekosistem.android.peer.OwnershipPolicy
import com.btekosistem.android.peer.PeerManager
import com.btekosistem.android.peer.QcyAdvCodec
import com.btekosistem.android.peer.QcyIncoming
import com.btekosistem.android.peer.QcyTransport
import com.btekosistem.android.peer.RelayedWrite
import com.btekosistem.android.peer.TransportPolicy
import com.btekosistem.android.protocol.ListeningMode
import com.btekosistem.android.protocol.NoiseScene
import com.btekosistem.android.protocol.QcyAdvertisement
import com.btekosistem.android.protocol.QcyDeviceState
import com.btekosistem.android.protocol.QcyEarDetection
import com.btekosistem.android.protocol.QcyChar
import com.btekosistem.android.protocol.QcyCustomEq
import com.btekosistem.android.protocol.QcyEqPreset
import com.btekosistem.android.protocol.QcyKeyFunction
import com.btekosistem.android.protocol.QcyTouchGesture
import com.btekosistem.android.protocol.QcyTouchKeys
import com.btekosistem.android.protocol.QcyTouchMap
import com.btekosistem.android.protocol.QcyTouchSide
import com.btekosistem.android.protocol.QcyGameMode
import com.btekosistem.android.protocol.QcyNoise
import com.btekosistem.android.protocol.QcyPacket
import com.btekosistem.android.protocol.QcyWearing
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class Link { IDLE, CONNECTING, CONNECTED }
/** Kontrol kanali nereden: dogrudan GATT ya da Mac uzerinden aktarim. */
enum class ControlVia { GATT, MAC }
enum class UiError { CONNECT, SERVICE, WRITE, KEYS_UNREAD }

data class FoundDevice(
    val key: String,
    val name: String?,
    val bonded: Boolean,
    val advertisement: QcyAdvertisement,
    val seenAt: Long,
    /** Reklam gelmedi; yalniz sistemde eslesmis olarak listelenir (pil bilinmez). */
    val bondedOnly: Boolean = false,
)

data class HomeState(
    val devices: List<FoundDevice> = emptyList(),
    val selectedKey: String? = null,
    val link: Link = Link.IDLE,
    /** Servis hazir ve 0x17 / 0x2C okumasi istendi. */
    val ready: Boolean = false,
    val device: QcyDeviceState = QcyDeviceState(),
    val busy: Boolean = false,
    val error: UiError? = null,
    val via: ControlVia = ControlVia.GATT,
    val now: Long = 0L,
    /** Yakindaki AirPods / Beats (Proximity Pairing reklami); yalniz okunur bilgi. */
    val apple: AppleSighting? = null,
    /** Mac ile peer oturumu (Wi-Fi ya da Bluetooth) acik: sahiplik dugmeleri yalniz bu durumda gorunur. */
    val macSession: Boolean = false,
) {
    val selected: FoundDevice? get() = devices.firstOrNull { it.key == selectedKey }
}

@SuppressLint("MissingPermission")
class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val scanner = QcyScanner(app)
    /** Tarama pencereleri: kanal hazirken seyrek, degilken 4 sn acik / 20 sn kapali (surekli tarama cizirti yapar). */
    private val scanScheduler = ScanScheduler()
    private val gatt = QcyGattClient(app)
    /** Klasik -> LE adresi (kalici): kayitliysa taramadan dogrudan GATT. */
    private val leBook = LeAddressBook(PrefsKeyValueStore(app))
    /** Otomatik baglanma kapisi (ustel geri cekilme 5 sn..2 dk; elle kesince oturum boyunca kapali). */
    private val autoConnect = AutoConnect()
    private val relay = PeerManager.get(app).relay
    /** Telefondaki calan parca (mini oynatici); komutlar PeerManager.media.command ile gider. */
    val media: StateFlow<LocalMedia> = PeerManager.get(app).media.local
    /** Mac'in ses durumu (Mac bagli degilse null) ve Mac sesi komutlari. */
    val volumeMac: StateFlow<com.btekosistem.android.peer.VolState?> = PeerManager.get(app).volume.mac
    fun setMacVolume(level: Int?, muted: Boolean?) = PeerManager.get(getApplication()).volume.setMac(level, muted)
    private val gattTransport = GattTransport(gatt)
    /** Komut yazma ve gelen yanit/reklam akisi bu aktarimdan gecer. */
    private var transport: QcyTransport = gattTransport
    private var incomingJob: Job? = null
    private var connectTimeoutJob: Job? = null
    /** Su an baglanilan/baglanan kulakligin klasik adresi (buyuk harf). */
    private var ctlAddress: String? = null
    private val handles = HashMap<String, BluetoothDevice>()
    private var bondedByAddress: Map<String, String?> = emptyMap()
    private val writeLock = Mutex()
    private var busyJob: Job? = null
    private var tickJob: Job? = null
    /** Yazilan opcode -> bu ana kadar gelen eski durum bildirimleri arayuze uygulanmaz (son yazilan kazanir). */
    private val ignoreUntil = HashMap<Int, Long>()
    /** Opcode -> cihazdan gelen son TAZE (yazma penceresi disi) yanit zamani; yazma dogrulamasi icin. */
    private val lastSeen = HashMap<Int, Long>()
    private var hintedAddress: String? = null
    /** Kullanici "Kontrolu telefona al" dedi: Mac sahip olsa da telefon GATT'te kalir. */
    private var forcePhone = false
    /** Kullanici "Kontrolu Mac'e ver" dedi: GATT kapali, Mac sahip olunca relay ile gosterilir. */
    private var givenToMac = false
    /** Bu Mac oturumunda kullanici telefondan yonetmeye basladi (baglandi / ayar yazdi). */
    private var phoneEngaged = false
    private val lastAdvert = HashMap<String, QcyAdvertisement>()
    private val forgotten = HashSet<String>()

    private val _state = MutableStateFlow(HomeState(now = SystemClock.elapsedRealtime()))
    val state: StateFlow<HomeState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            gatt.events.collect(::onGatt)
        }
        viewModelScope.launch { relay.writesFromMac.collect(::onMacWrite) }
        // Mac sahipligi degisti: telefon GATT'te ise Mac kazanir; Mac biraktiysa relay'den GATT'e don.
        viewModelScope.launch {
            var prev = emptySet<String>()
            relay.macOwned.collect { cur ->
                val added = cur - prev
                val removed = prev - cur
                prev = cur
                // Mac "kontrolu al" (owner=true): telefon birakir, otomatik baglanmayi durdurur, owner=false ile yanitlar.
                if (added.isNotEmpty()) { forcePhone = false; phoneEngaged = false }
                // Mac "telefona ver" (owner=false, oturum acik): telefon GATT'e baglanir; Ready'de owner=true bildirilir.
                if (removed.isNotEmpty() && relay.sessionOpen.value) {
                    forcePhone = false; givenToMac = false; phoneEngaged = true
                    autoConnect.enable()
                    val s = _state.value
                    if (s.link == Link.IDLE) {
                        val key = removed.firstNotNullOfOrNull { a -> handles.keys.firstOrNull { addressOf(it) == a } }
                        if (key != null) startConnect(key)
                    }
                }
                onMacOwnership()
                added.forEach { relay.ackOwner(it, false) }
            }
        }
        // Oturum (Wi-Fi ya da Bluetooth) acilinca telefon sahipse Mac'e tam durumu yolla: okumalar yeniden istenir, yanitlar relay'e gider.
        viewModelScope.launch {
            relay.sessionOpen.collect { open ->
                _state.update { it.copy(macSession = open) }
                if (!open) phoneEngaged = false
                val s = _state.value
                val addr = ctlAddress
                if (open && addr != null && s.via == ControlVia.GATT && s.ready && s.link == Link.CONNECTED) {
                    lastAdvert[addr]?.let { relay.sendNotify(addr, IncomingKind.ADVERT, QcyAdvCodec.encode(it)) }
                    initialReads()
                }
            }
        }
    }

    /** Ortam hazirsa taramayi baslatir, degilse durdurur. */
    fun setScanning(enabled: Boolean) {
        if (enabled) {
            refreshBonded()
            scanTick()
            if (tickJob == null) tickJob = viewModelScope.launch {
                var n = 0
                while (true) {
                    delay(1_000)
                    scanTick()
                    if (++n % 2 == 0) {
                        refreshBonded()
                        prune()
                    }
                }
            }
        } else {
            Log.i(TAG, "tarama durduruldu")
            scanner.stop()
            scanScheduler.reset()
            tickJob?.cancel(); tickJob = null
            if (_state.value.link == Link.IDLE) _state.update { it.copy(devices = emptyList(), selectedKey = null) }
        }
    }

    private fun scanTick() {
        val qcy = bondedByAddress.filter { QcyNames.isQcy(it.value) && it.key !in forgotten }.keys
        val unresolved = qcy.count { leBook.leFor(it) == null }
        val profile = ScanPolicy.profile(_state.value.link == Link.CONNECTED, qcy.size, unresolved)
        val intensity = ScanPolicy.intensity(profile, unresolved)
        when (scanScheduler.tick(SystemClock.elapsedRealtime(), profile)) {
            ScanScheduler.Action.START -> {
                val ok = scanner.start(::onHit, { code -> Log.i(TAG, "tarama basarisiz kod=$code") }, ::onApple, intensity)
                Log.i(TAG, "tarama penceresi acik ok=$ok profil=$profile guc=$intensity")
            }
            ScanScheduler.Action.STOP -> scanner.stop()
            ScanScheduler.Action.NONE -> {}
        }
        autoConnectTick()
    }

    /** Eslesmis QCY A2DP/HFP ile bagliysa ve Mac sahip degilse kontrol kanalini kullanici dokunmadan acar. */
    private fun autoConnectTick() {
        val s = _state.value
        if (s.link != Link.IDLE) return
        val now = SystemClock.elapsedRealtime()
        if (!autoConnect.mayAttempt(now)) return
        val audio = connectedAudio()
        val cand = s.devices.firstOrNull { d ->
            d.bonded && d.key !in forgotten && (!d.bondedOnly || leBook.leFor(d.key) != null) && handles[d.key] != null &&
                audio.any { (a, n) -> if (a.isNullOrBlank()) n != null && n == d.name else a.uppercase() == addressOf(d.key) }
        } ?: return
        val addr = addressOf(cand.key)
        if (!OwnershipPolicy.autoGattAllowed(relay.sessionOpen.value, relay.macOwns(addr), phoneEngaged)) return
        Log.i(TAG, "otomatik baglanma adres=$addr")
        startConnect(cand.key)
    }

    /** Bagli A2DP/SCO cikislari: (adres, ad). */
    private fun connectedAudio(): List<Pair<String?, String?>> = try {
        (getApplication<Application>().getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager)
            .getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
            .filter { it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
            .map { (if (android.os.Build.VERSION.SDK_INT >= 28) it.address else null) to it.productName?.toString() }
    } catch (_: Exception) {
        emptyList()
    }

    private fun refreshBonded() {
        val bt = getApplication<Application>().getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val bonded = try {
            bt?.adapter?.bondedDevices.orEmpty().toList()
        } catch (_: SecurityException) {
            emptyList()
        }
        bondedByAddress = bonded.associate { it.address.uppercase() to it.name }
        val now = SystemClock.elapsedRealtime()
        val qcy = bonded.filter { QcyNames.isQcy(it.name) && it.address !in forgotten }
        _state.update { s ->
            // Reklamla gorunen cihaz ayni klasik adrese sahipse eslesmis kaydi ekleme (birlestirme).
            val advertised = s.devices.filter { !it.bondedOnly }
                .mapNotNull { it.advertisement.controlAddress?.uppercase() }.toSet()
            var list = s.devices.filter { d -> !d.bondedOnly || bonded.any { it.address == d.key } }
            for (b in qcy) {
                val addr = b.address.uppercase()
                if (addr in advertised) { list = list.filterNot { it.key == b.address && it.bondedOnly }; continue }
                val leDev = leBook.leFor(addr)?.let { LeDevices.remote(bt?.adapter, it) }
                if (leDev != null) { if (handles[b.address]?.address != leDev.address) handles[b.address] = leDev }
                else handles.getOrPut(b.address) { b }
                val existing = list.firstOrNull { it.key == b.address }
                if (existing == null) Log.i(TAG, "eslesmis QCY bulundu ad=${b.name} adres=${b.address}")
                val found = FoundDevice(
                    b.address, b.name, true,
                    QcyAdvertisement(null, null, null, false, false, false, addr), now, bondedOnly = true,
                )
                list = list.filterNot { it.key == b.address } + found
            }
            s.copy(devices = list.sortedBy { it.key }, now = now)
        }
    }

    private val appleSightings = HashMap<String, AppleSighting>()

    private fun onApple(s: AppleSighting) {
        appleSightings[s.address] = s
        refreshApple()
    }

    /** Bagli ses cihazlarinin adlari (A2DP cikislari); izin gerektirmez. */
    private fun connectedAudioNames(): List<String?> = try {
        (getApplication<Application>().getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager)
            .getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
            .filter { it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
            .map { it.productName?.toString() }
    } catch (_: Exception) {
        emptyList()
    }

    private fun refreshApple() {
        val now = SystemClock.elapsedRealtime()
        appleSightings.values.removeAll { now - it.seenAtMs > AppleSelector.FRESH_MS * 2 }
        val pick = AppleSelector.pick(appleSightings.values, connectedAudioNames(), now)
        if (pick != _state.value.apple) _state.update { it.copy(apple = pick) }
    }

    private fun onHit(hit: ScanHit) {
        val key = hit.device.address
        if (key in forgotten) return
        if (key !in handles) Log.i(TAG, "QCY reklami goruldu adres=$key ctrl=${hit.advertisement.controlAddress} rssi=${hit.rssi}")
        handles[key] = hit.device
        hit.advertisement.controlAddress?.let { if (leBook.remember(it, key)) Log.i(TAG, "LE adresi kaydedildi klasik=$it le=$key") }
        val bondedName = hit.advertisement.controlAddress?.let { bondedByAddress[it.uppercase()] }
        val bonded = hit.advertisement.controlAddress?.uppercase() in bondedByAddress
        val found = FoundDevice(key, bondedName ?: hit.localName, bonded, hit.advertisement, SystemClock.elapsedRealtime())
        hit.advertisement.controlAddress?.let { addr ->
            if (hintedAddress == null || state.value.selectedKey == key) {
                if (hintedAddress != addr) {
                    hintedAddress = addr
                    PeerManager.get(getApplication()).earbud.hint(addr)
                }
            }
        }
        hit.advertisement.controlAddress?.let { a ->
            lastAdvert[a.uppercase()] = hit.advertisement
            if (relay.phoneOwns(a)) relay.sendNotify(a, IncomingKind.ADVERT, QcyAdvCodec.encode(hit.advertisement))
        }
        _state.update { s ->
            val list = s.devices.filterNot { it.key == key } + found
            val ctrl = found.advertisement.controlAddress?.uppercase()
            val merged = if (ctrl == null) list else list.filterNot { it.bondedOnly && it.key.uppercase() == ctrl }
            s.copy(
                devices = merged.sortedBy { it.key },
                selectedKey = if (s.selectedKey != null && merged.none { it.key == s.selectedKey } && s.link == Link.IDLE) null else s.selectedKey,
                now = found.seenAt,
            )
        }
    }

    private fun prune() {
        val now = SystemClock.elapsedRealtime()
        refreshApple()
        _state.update { s ->
            s.copy(
                devices = s.devices.filter { it.bondedOnly || it.key == s.selectedKey && s.link != Link.IDLE || now - it.seenAt < STALE_MS },
                now = now,
            )
        }
    }

    /** Kullanici baglantisi: otomatik baglanma yeniden acilir. */
    fun connect(key: String) {
        phoneEngaged = true
        autoConnect.enable()
        startConnect(key)
    }

    private fun startConnect(key: String) {
        val device = handles[key] ?: return
        val addr = addressOf(key)
        ctlAddress = addr
        _state.update { it.copy(selectedKey = key, link = Link.CONNECTING, ready = false, device = QcyDeviceState(), error = null, via = ControlVia.GATT) }
        if (!forcePhone && !TransportPolicy.shouldTryGatt(relay.sessionOpen.value, relay.macOwns(addr))) {
            Log.i(TAG, "Mac sahip, GATT denenmiyor; relay adres=$addr")
            startRelay(addr)
            return
        }
        Log.i(TAG, "GATT baglaniliyor adres=$key")
        gatt.connect(device)
        connectTimeoutJob?.cancel()
        connectTimeoutJob = viewModelScope.launch {
            delay(CONNECT_TIMEOUT_MS)
            if (_state.value.link == Link.CONNECTING && _state.value.via == ControlVia.GATT) {
                Log.i(TAG, "GATT zaman asimi")
                gatt.close()
                onGatt(GattEvent.ConnectFailed)
            }
        }
    }

    private fun addressOf(key: String): String =
        (_state.value.devices.firstOrNull { it.key == key }?.advertisement?.controlAddress ?: key).uppercase()

    fun disconnect() {
        autoConnect.disable()
        forcePhone = false; givenToMac = false
        gatt.close()
        releaseOwnership()
        incomingJob?.cancel(); incomingJob = null
        connectTimeoutJob?.cancel()
        _state.update { it.copy(link = Link.IDLE, ready = false, device = QcyDeviceState(), busy = false, selectedKey = null) }
    }

    fun dismissError() = _state.update { it.copy(error = null) }

    private fun onGatt(event: GattEvent) {
        Log.i(TAG, "GATT olayi: ${event::class.simpleName}")
        when (event) {
            GattEvent.Ready -> {
                connectTimeoutJob?.cancel()
                val addr = ctlAddress
                if (!forcePhone && addr != null && relay.macOwns(addr) && relay.sessionOpen.value) {
                    // Sahiplik cakismasi: Mac sahip kalir, telefon birakir.
                    Log.i(TAG, "sahiplik cakismasi: telefon birakiyor adres=$addr")
                    gatt.close()
                    startRelay(addr)
                    return
                }
                transport = gattTransport
                autoConnect.succeeded(SystemClock.elapsedRealtime())
                if (addr != null) relay.setPhoneOwns(addr, true)
                _state.update { it.copy(link = Link.CONNECTED, ready = true, busy = true, via = ControlVia.GATT) }
                startIncoming()
                initialReads()
            }
            is GattEvent.Packet, is GattEvent.KeyMap -> {} // gattTransport.incoming uzerinden islenir
            GattEvent.Disconnected -> reset(null)
            GattEvent.ConnectFailed -> {
                val addr = ctlAddress
                if (addr != null && TransportPolicy.useRelayAfterGattFailure(relay.sessionOpen.value, relay.macOwns(addr))) {
                    Log.i(TAG, "GATT basarisiz, Mac sahip: relay'e geciliyor adres=$addr")
                    startRelay(addr)
                } else reset(UiError.CONNECT)
            }
            GattEvent.ServiceMissing -> reset(UiError.SERVICE)
        }
    }

    private fun initialReads() {
        viewModelScope.launch {
            writeLock.withLock {
                transport.write(QcyPacket.request(QcyNoise.OPCODE))
                delay(80)
                transport.write(QcyPacket.request(QcyWearing.OPCODE))
                // Mac'teki requestQcyReads gibi: oyun modu, kulak algilama, EQ on ayari.
                for (opcode in intArrayOf(QcyGameMode.OPCODE, QcyEarDetection.OPCODE, QcyEqPreset.OPCODE)) {
                    delay(150)
                    transport.write(QcyPacket.request(opcode))
                }
                // Tus eslemesi: yerel GATT'te 000D dogrudan okunur (Mac gibi); yoksa / relay'de 0x2B istegi.
                delay(150)
                if (!transport.readKeyMap()) transport.write(QcyPacket.request(QcyTouchMap.OPCODE))
            }
            releaseBusyLater()
        }
    }

    private fun startRelay(addr: String) {
        connectTimeoutJob?.cancel()
        releaseOwnership()
        transport = relay.transportFor(addr)
        _state.update { it.copy(link = Link.CONNECTED, ready = true, busy = true, via = ControlVia.MAC, error = null) }
        startIncoming()
        initialReads()
    }

    private fun startIncoming() {
        incomingJob?.cancel()
        val t = transport
        val addr = ctlAddress
        incomingJob = viewModelScope.launch {
            t.incoming.collect { onIncoming(it, t === gattTransport && addr != null, addr) }
        }
    }

    /** Telefon sahipken Mac'e iletilen yanit ve reklam; sahip degilken Mac'ten gelen aynilari. */
    private fun onIncoming(inc: QcyIncoming, forward: Boolean, addr: String?) {
        if (forward && addr != null && inc.kind == IncomingKind.RESPONSE) relay.sendNotify(addr, IncomingKind.RESPONSE, inc.bytes)
        when (inc.kind) {
            IncomingKind.RESPONSE -> applyResponse(inc.bytes)
            IncomingKind.KEYMAP -> applyKeyMapRead(inc.bytes)
            IncomingKind.ADVERT -> {
                val ad = QcyAdvCodec.decode(inc.bytes) ?: return
                _state.update { s ->
                    s.copy(devices = s.devices.map { d -> if (d.key == s.selectedKey) d.copy(advertisement = ad, seenAt = SystemClock.elapsedRealtime()) else d })
                }
            }
        }
    }

    private fun releaseOwnership() {
        ctlAddress?.let { relay.setPhoneOwns(it, false) }
    }

    /** Mac'ten gelen ctl.write: telefon GATT'i tutuyorsa `kar`a gore dogrulanip dogru ozelligine yazilir. */
    private suspend fun onMacWrite(w: RelayedWrite) {
        val s = _state.value
        if (w.address != ctlAddress || s.via != ControlVia.GATT || !s.ready) return
        val valid = when (w.target) {
            QcyChar.COMMAND -> QcyPacket.parse(w.bytes).isNotEmpty()
            QcyChar.KEYMAP -> w.bytes.size == 20
            QcyChar.LEGACY_EQ -> w.bytes.size == 11
        }
        if (!valid) { Log.i(TAG, "ctl.write gecersiz ${w.target} atildi"); return }
        writeLock.withLock { gatt.write(w.bytes, w.target) }
    }

    /** "Kontrolu Mac'e ver": telefon GATT'i birakir, otomatik baglanma kapanir; Mac alinca kart relay ile gosterilir. */
    fun giveControlToMac() {
        val s = _state.value
        if (!s.macSession || s.via != ControlVia.GATT || s.link == Link.IDLE) return
        autoConnect.disable()
        givenToMac = true; forcePhone = false
        gatt.close(); releaseOwnership()
        incomingJob?.cancel(); incomingJob = null
        connectTimeoutJob?.cancel()
        _state.update { it.copy(link = Link.IDLE, ready = false, device = QcyDeviceState(), busy = false) }
        onMacOwnership()
    }

    /** "Kontrolu telefona al": Mac sahip olsa da GATT'e baglanilir; ctl.owner(sahip=true) Mac'e bildirilir. */
    fun takeControlFromMac() {
        val s = _state.value
        val key = s.selectedKey ?: return
        if (!s.macSession || s.via != ControlVia.MAC) return
        forcePhone = true; givenToMac = false; phoneEngaged = true
        autoConnect.enable()
        incomingJob?.cancel(); incomingJob = null
        startConnect(key)
    }

    private fun onMacOwnership() {
        val addr = ctlAddress ?: return
        val s = _state.value
        val macOwns = relay.macOwns(addr) && relay.sessionOpen.value
        if (!relay.macOwns(addr)) forcePhone = false
        if (macOwns && givenToMac && s.link == Link.IDLE && s.selectedKey != null) {
            Log.i(TAG, "Mac sahipligi aldi (telefon verdi): relay adres=$addr")
            startRelay(addr)
        } else if (forcePhone) {
            return
        } else if (macOwns && s.via == ControlVia.GATT && s.link != Link.IDLE) {
            Log.i(TAG, "Mac sahipligi aldi: telefon birakiyor adres=$addr")
            gatt.close()
            startRelay(addr)
        } else if (!macOwns && s.via == ControlVia.MAC && s.link == Link.CONNECTED && OwnershipPolicy.returnToGattAfterMacRelease(autoConnect.isEnabled, forcePhone)) {
            val key = s.selectedKey ?: return
            val device = handles[key] ?: return
            Log.i(TAG, "Mac sahipligi biraktı: GATT deneniyor adres=$addr")
            incomingJob?.cancel(); incomingJob = null
            transport = gattTransport
            _state.update { it.copy(link = Link.CONNECTING, ready = false, device = QcyDeviceState(), via = ControlVia.GATT) }
            gatt.connect(device)
        }
    }

    /** 000D okumasi; yazma sonrasi ~700 ms icindeki eski okuma uygulanmaz. */
    private fun applyKeyMapRead(bytes: ByteArray) {
        if ((ignoreUntil[QcyTouchMap.OPCODE] ?: 0L) > SystemClock.elapsedRealtime()) return
        _state.update { s -> s.copy(device = s.device.applyKeyMap(bytes), busy = false) }
    }

    private fun applyResponse(bytes: ByteArray) {
        val now = SystemClock.elapsedRealtime()
        val blocks = QcyPacket.parse(bytes)
        // Yazdiktan sonraki ~700 ms icinde gelen eski durum bildirimini uygulama.
        val fresh = blocks.filter { (ignoreUntil[it.opcode] ?: 0L) <= now }
        if (fresh.isNotEmpty()) {
            fresh.forEach { lastSeen[it.opcode] = now }
            _state.update { s -> s.copy(device = fresh.fold(s.device) { d, b -> d.apply(b) }, busy = false) }
        }
        // Kutuya girip cikinca cihaz 0x28 bildirir ve modu gecici Kapali yapip geri alir: guncel modu oku.
        if (blocks.any { it.opcode == 0x28 }) {
            viewModelScope.launch { writeLock.withLock { transport.write(QcyPacket.request(QcyNoise.OPCODE)) } }
        }
    }

    private var transparencyJob: kotlinx.coroutines.Job? = null

    private fun reset(error: UiError?) {
        autoConnect.failed(SystemClock.elapsedRealtime())
        connectTimeoutJob?.cancel()
        incomingJob?.cancel(); incomingJob = null
        releaseOwnership()
        _state.update { it.copy(link = Link.IDLE, ready = false, device = QcyDeviceState(), busy = false, selectedKey = null, error = error) }
    }

    fun setMode(mode: ListeningMode) {
        if (_state.value.device.mode == mode) return
        send(QcyNoise.setMode(mode), QcyNoise.OPCODE) {
            it.copy(
                mode = mode, scene = if (mode == ListeningMode.GURULTU_ENGELLEME) NoiseScene.UYARLANIR else null,
                transparency = if (mode == ListeningMode.SEFFAF) QcyNoise.TRANSPARENCY_DEFAULT else null,
            )
        }
    }

    fun setScene(scene: NoiseScene) =
        send(scene.packet, QcyNoise.OPCODE) { it.copy(mode = ListeningMode.GURULTU_ENGELLEME, scene = scene) }

    /** Seffaflik seviyesi (deneysel): 350 ms debounce ile yazar, son deger kazanir. */
    fun setTransparency(level: Int) {
        val l = level.coerceIn(QcyNoise.TRANSPARENCY_MIN, QcyNoise.TRANSPARENCY_MAX)
        transparencyJob?.cancel()
        transparencyJob = viewModelScope.launch {
            delay(350)
            if (_state.value.device.mode != ListeningMode.SEFFAF) return@launch
            send(QcyNoise.transparencyLevel(l), QcyNoise.OPCODE) { it.copy(transparency = l) }
        }
    }

    /** Durum cihazdan okunmadiysa yazmaz. */
    fun setWearing(enabled: Boolean) {
        val wearing = _state.value.device.wearing ?: return
        send(wearing.setEnabledPacket(enabled), QcyWearing.OPCODE) { d -> d.copy(wearing = d.wearing?.copy(enabled = enabled)) }
    }

    fun setGameMode(enabled: Boolean) =
        send(QcyGameMode.packet(enabled), QcyGameMode.OPCODE) { it.copy(gameMode = enabled) }

    fun setEarDetection(enabled: Boolean) =
        send(QcyEarDetection.packet(enabled), QcyEarDetection.OPCODE) { it.copy(earDetection = enabled) }

    fun setEqPreset(preset: QcyEqPreset) =
        send(preset.packet, QcyEqPreset.OPCODE) { it.copy(eqPreset = preset) }

    /**
     * Dokunmatik islev (Mac ile ayni): cihazdan okunan 20 baytlik 000D eslemesinin ilgili yuvasi degistirilir ve
     * TUM esleme 000D'ye yazilir (diger tuslar korunur), sonra geri okunur. Esleme okunmadiysa yazmaz.
     */
    fun setTouch(side: QcyTouchSide, gesture: QcyTouchGesture, function: QcyKeyFunction) {
        val s = _state.value
        if (!s.ready) return
        val map = s.device.touchKeys?.setting(side, gesture, function)
        if (map == null) {
            _state.update { it.copy(error = UiError.KEYS_UNREAD) }
            return
        }
        _state.update { it.copy(busy = true) }
        viewModelScope.launch {
            writeLock.withLock {
                if (!transport.write(map.bytes, QcyChar.KEYMAP)) {
                    _state.update { it.copy(busy = false, error = UiError.WRITE) }
                    return@launch
                }
                ignoreUntil[QcyTouchMap.OPCODE] = SystemClock.elapsedRealtime() + STALE_WINDOW_MS
                delay(READ_BACK_MS)
                if (!transport.readKeyMap()) transport.write(QcyPacket.request(QcyTouchMap.OPCODE))
            }
            releaseBusyLater()
        }
    }

    /** Ozel EQ (ya da hazir ayarin bantlari): 1001 uzerinden 0x22 bant paketi; geri okuma yolu belgede yok. */
    fun applyEq(gainsDb: List<Int>) {
        if (!_state.value.ready) return
        _state.update { it.copy(busy = true) }
        viewModelScope.launch {
            writeLock.withLock {
                for (p in QcyCustomEq.packets(gainsDb)) {
                    if (!transport.write(p)) {
                        _state.update { it.copy(busy = false, error = UiError.WRITE) }
                        return@launch
                    }
                    delay(80)
                }
            }
            releaseBusyLater()
        }
    }

    /** Cihazi uygulamadan kaldirir: kontrol kanali kapanir, bu oturumda listede gosterilmez. Sistem eslemesi silinmez. */
    fun forget(key: String) {
        forgotten += key
        if (_state.value.selectedKey == key) { gatt.close(); releaseOwnership(); incomingJob?.cancel(); incomingJob = null }
        _state.update { s ->
            s.copy(
                devices = s.devices.filterNot { it.key == key },
                link = if (s.selectedKey == key) Link.IDLE else s.link,
                ready = if (s.selectedKey == key) false else s.ready,
                device = if (s.selectedKey == key) QcyDeviceState() else s.device,
                busy = false,
                selectedKey = if (s.selectedKey == key) null else s.selectedKey,
            )
        }
    }

    /**
     * Yaz; arayuzu hemen yazilan degerle guncelle (son yazilan kazanir), ~700 ms eski bildirimleri yok say,
     * sonra ayni opcode'u oku ve gelen okumayi uygula.
     */
    private fun send(packet: ByteArray, readOpcode: Int, optimistic: (QcyDeviceState) -> QcyDeviceState) {
        if (!_state.value.ready) return
        phoneEngaged = true
        _state.update { it.copy(busy = true) }
        viewModelScope.launch {
            val before = _state.value.device
            var shown: QcyDeviceState? = null
            var sentAt = 0L
            writeLock.withLock {
                if (!transport.write(packet)) {
                    _state.update { it.copy(busy = false, error = UiError.WRITE) }
                    return@launch
                }
                sentAt = SystemClock.elapsedRealtime()
                ignoreUntil[readOpcode] = sentAt + STALE_WINDOW_MS
                _state.update { it.copy(device = optimistic(it.device)) }
                shown = _state.value.device
                delay(READ_BACK_MS)
                transport.write(QcyPacket.request(readOpcode))
            }
            releaseBusyLater()
            confirmOrRollback(readOpcode, sentAt, before, shown)
        }
    }

    /**
     * Iyimser deger KESIN degildir: cihazdan taze yanit gelmezse bir kez daha okunur; yine yoksa arayuz yazmadan onceki
     * duruma doner (arada baska bir sey degismediyse) ve uyari cikar.
     */
    private suspend fun confirmOrRollback(readOpcode: Int, sentAt: Long, before: QcyDeviceState, shown: QcyDeviceState?) {
        delay(CONFIRM_MS)
        if ((lastSeen[readOpcode] ?: 0L) >= sentAt) return
        writeLock.withLock { transport.write(QcyPacket.request(readOpcode)) }
        delay(CONFIRM_MS)
        if ((lastSeen[readOpcode] ?: 0L) >= sentAt) return
        _state.update { s -> if (s.device == shown) s.copy(device = before, error = UiError.WRITE) else s.copy(error = UiError.WRITE) }
    }

    private fun releaseBusyLater() {
        busyJob?.cancel()
        busyJob = viewModelScope.launch {
            delay(1_000)
            _state.update { it.copy(busy = false) }
        }
    }

    override fun onCleared() {
        scanner.stop()
        releaseOwnership()
        gatt.close()
    }

    private companion object {
        const val TAG = "BTrack"
        /** Tarama penceresi 4 sn acik / 20 sn kapali: cihaz bir donguden uzun gorunmezse bayat sayilir. */
        const val STALE_MS = 45_000L
        const val STALE_WINDOW_MS = 700L
        const val READ_BACK_MS = 750L
        const val CONFIRM_MS = 2_500L
        const val CONNECT_TIMEOUT_MS = 15_000L
    }
}
