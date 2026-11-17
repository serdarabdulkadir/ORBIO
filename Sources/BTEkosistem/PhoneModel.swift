// Telefon kanalinin arayuz modeli: eslesme, baglanti, telefon durumu, arama komutlari.
// Sahte veri yok: eslesme/baglanti yokken alanlar bos kalir.
import Foundation
import Observation
import EkosistemCore

@MainActor
@Observable
final class PhoneModel {
    private(set) var listenerStatus: PeerServer.Status = .durdu
    private(set) var pin: PeerPin?
    private(set) var snapshot = PhoneSnapshot()
    /// Rehber arama dizini: yalniz bellekte; baglanti kopunca, izin kapaninca ve eslesme kalkinca bosalir.
    private(set) var contactIndex = ContactsIndex()
    /// Ilk eslesmede iki ekranda karsilastirilacak kod.
    private(set) var sasCode: String?
    /// "Telefonu esle" ile uretilen tek kullanimlik kod ve bitis zamani (yalniz eslesme modundayken dolu).
    private(set) var pairingCode: String?
    private(set) var pairingExpiresAt: Date?
    /// Son eslesme denemesinin sonucu (gorunur uyari); yeni kod uretince silinir.
    private(set) var pairingNote: String?
    @ObservationIgnored let pairingGate = PairingGate()
    @ObservationIgnored private var pairingTimer: Task<Void, Never>?
    private(set) var isConnected = false
    /// Aktif oturumun yolu: Wi-Fi ya da Bluetooth (RFCOMM yedek); oturum yokken nil.
    private(set) var connectionPath: PeerPath?
    /// Sabitlenen anahtar ile gelen anahtar farkli: kullanici uyarilir.
    private(set) var keyMismatch = false
    private(set) var storageWarning: String?
    /// Acik aramanin baslangic zamani (sure sayaci icin).
    private(set) var callStartedAt: Date?
    var isEnabled: Bool
    /// Arama baloncugu (panel kapaliyken yuzen arama kapsulu); varsayilan acik.
    var bubbleEnabled: Bool = UserDefaults.standard.object(forKey: PhoneModel.bubbleKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(bubbleEnabled, forKey: Self.bubbleKey) }
    }
    static let bubbleKey = "aramaBaloncugu"

    /// "Kapat" istegi: bosta ya da telefondan sonuc bekleniyor.
    enum HangupPhase: Equatable { case bosta, kapatiliyor }
    private(set) var hangupPhase: HangupPhase = .bosta
    /// Kapatma / arama komutu hatasi (gorunur serit); arama bitince ya da kapatilinca silinir.
    private(set) var callError: String?
    @ObservationIgnored private var hangupTask: Task<Void, Never>?
    @ObservationIgnored private static let verbose = CommandLine.arguments.contains("--verbose")
    private func log(_ text: String) { if Self.verbose { print("[telefon] \(text)"); fflush(stdout) } }

    /// Anahtar Zinciri erisim durumu (okuma arka planda; UI beklemez).
    enum KeychainState: Equatable { case bosta, bekleniyor, yavasBekleniyor, reddedildi, hazir }
    private(set) var keychainState: KeychainState = .bosta

    /// Motorun kullandigi gercek kanal (kulaklik birakma / baglanma istekleri).
    @ObservationIgnored let channel: PeerEarbudChannel
    @ObservationIgnored var onCallTransition: (@MainActor (CallTransition, PhoneSnapshot) -> Void)?
    @ObservationIgnored var onSASChange: (@MainActor (String?) -> Void)?
    /// ctl.* mesajlari (kanal sahibi + aktarim) ve oturum durumu (kuruldu / koptu).
    @ObservationIgnored var onControl: (@MainActor (PeerMessage) -> Void)?
    @ObservationIgnored var onSessionChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private let server: PeerServer
    @ObservationIgnored private let broker: PeerRequestBroker
    /// Bluetooth yedek kanali (RFCOMM istemcisi) ve yol secim mantigi.
    @ObservationIgnored private let rfcomm = RfcommPeerClient()
    @ObservationIgnored private var pathPolicy = PeerPathPolicy(now: Date())
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    /// Mac'in Bluetooth'u acik mi (CoreBluetooth durumundan; AppModel besler). Kapaliyken RFCOMM denenmez.
    @ObservationIgnored var bluetoothAvailable = true
    @ObservationIgnored private var started = false
    @ObservationIgnored private var keychainReady = false
    @ObservationIgnored private var keychainAttempt = 0
    @ObservationIgnored private var pendingPairing = false
    /// Mac cikis sesi (varsayilan cikis aygiti); telefonla senkron icin.
    @ObservationIgnored private let macVolume = SystemVolume()
    @ObservationIgnored private var volumeDebounce: Task<Void, Never>?
    @ObservationIgnored private var phoneVolumeDebounce: Task<Void, Never>?

    init() {
        let server = PeerServer()
        self.server = server
        let broker = PeerRequestBroker(sender: { envelope in await server.send(envelope) })
        self.broker = broker
        channel = PeerEarbudChannel(transport: broker)
        isEnabled = UserDefaults.standard.object(forKey: PeerStore.enabledKey) as? Bool ?? true
    }

    var isPaired: Bool { pin != nil }
    var phoneName: String { snapshot.phone?.ad ?? pin?.name ?? "Telefon" }
    /// Gelen arama caliyor mu (menu cubugu simgesi ve rozet icin).
    var isRinging: Bool { isConnected && snapshot.isRinging }

    func start() {
        guard !started else { return }
        started = true
        server.onStatus = { [weak self] in self?.listenerStatus = $0 }
        server.onSAS = { [weak self] code in
            self?.pairingCode = nil; self?.pairingExpiresAt = nil
            self?.sasCode = code
            self?.onSASChange?(code)
        }
        server.onEstablished = { [weak self] key, name in self?.established(key: key, name: name) }
        server.onMessage = { [weak self] in self?.receive($0) }
        server.onClosed = { [weak self] reason, wasActive in self?.closed(reason, wasActive: wasActive) }
        server.onPath = { [weak self] in self?.connectionPath = $0 }
        server.onLinkEnded = { [weak self] path, establishedAt in
            guard path == .bluetooth, let self else { return }
            self.pathPolicy.bluetoothEnded(now: Date(), establishedAt: establishedAt, jitter: Double.random(in: 0...0.2))
        }
        rfcomm.onTransport = { [weak self] transport in
            guard let self else { transport.close(); return }
            self.log("Bluetooth (RFCOMM) kanalı açıldı")
            self.server.adopt(transport)
        }
        rfcomm.onFailed = { [weak self] in
            self?.pathPolicy.bluetoothEnded(now: Date(), establishedAt: nil, jitter: Double.random(in: 0...0.2))
            self?.log("Bluetooth (RFCOMM) bağlanamadı; sonra yeniden denenecek")
        }
        startPathLoop()
        macVolume.onChange = { [weak self] in self?.scheduleMacVolumeSend() }
        macVolume.start()

        if isEnabled { loadKeychain() }
    }

    /// Telefon sekmesi / ayarlar / "Telefonu esle" acilinca cagrilir; ilk seferde sunucuyu baslatir (idempotent).
    func ensureStarted() {
        start()
        if isEnabled && !keychainReady && keychainState == .bosta { loadKeychain() }
    }

    /// Anahtar Zinciri izni reddedildi / zaman asimi sonrasi "Tekrar dene".
    func retryKeychain() {
        guard started, !keychainReady else { return }
        loadKeychain()
    }

    private func loadKeychain() {
        guard !keychainReady, keychainState != .bekleniyor else { return }
        keychainAttempt += 1
        let attempt = keychainAttempt
        keychainState = .bekleniyor
        Task { [weak self] in   // 5 sn icinde yanit yoksa aciklayici durum; okuma arkada surer
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.keychainAttempt == attempt, self.keychainState == .bekleniyor else { return }
            self.keychainState = .yavasBekleniyor
        }
        Task { [weak self] in
            let result = await PeerStore.load()
            self?.keychainLoaded(result)
        }
    }

    private func keychainLoaded(_ result: PeerStore.LoadResult) {
        guard !keychainReady else { return }
        switch result {
        case .reddedildi:
            keychainState = .reddedildi
        case .ok(let identity, let persisted, let storedPin):
            keychainReady = true
            keychainState = .hazir
            if pin == nil { pin = storedPin }
            if !persisted { storageWarning = "Mac kimlik anahtarı diske yazılamadı; yeniden başlatınca telefonla yeniden eşleşmeniz gerekebilir." }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let name = Host.current().localizedName ?? "Mac"
            server.configure(identity: identity,
                             hello: PeerHello(ad: name, surum: version, cihazId: PeerStore.deviceID(), platform: "mac"),
                             pinned: pin?.key, pairingGate: pairingGate)
            if isEnabled { server.start() }
            if pendingPairing { pendingPairing = false; beginPairing() }
        }
    }

    /// Wi-Fi oncelikli yol secimi: ~10 sn Wi-Fi gelmezse ya da Wi-Fi oturumu koparsa Bluetooth denenir
    /// (ustel geri cekilmeyle); Wi-Fi gelince Bluetooth kapanir. Ayni anda tek oturum.
    private func startPathLoop() {
        pathPolicy = PeerPathPolicy(now: Date())
        pathTask?.cancel()
        pathTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.pathTick()
            }
        }
    }

    private func pathTick() {
        guard keychainReady, isEnabled else { return }
        let wifi = server.activePath == .wifi
        let busy = server.bluetoothBusy || rfcomm.isBusy
        let canTry = bluetoothAvailable && (isPaired || pairingCode != nil) && rfcomm.hasCandidates
        switch pathPolicy.evaluate(now: Date(), wifiActive: wifi, bluetoothBusy: busy, canTry: canTry) {
        case .none: break
        case .tryBluetooth: log("Bluetooth (RFCOMM) deneniyor"); rfcomm.connect()
        case .dropBluetooth: log("Wi-Fi bulundu; Bluetooth kapatılıyor"); rfcomm.cancel(); server.dropBluetooth()
        }
    }

    /// "Yenile": Bluetooth geri cekilmesini sifirlar.
    func refreshPath() { pathPolicy.reset(now: Date()) }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        UserDefaults.standard.set(value, forKey: PeerStore.enabledKey)
        guard started else { return }
        if value { keychainReady ? server.start() : loadKeychain() } else {
            rfcomm.cancel()
            server.stop()
            resetLive()
        }
    }

    // MARK: Eslesme

    /// "Telefonu esle": 6 haneli, 5 dk gecerli, tek kullanimlik kod uretir; telefonda girilmeli.
    func beginPairing() {
        guard !isPaired else { return }
        if !isEnabled { setEnabled(true) }
        ensureStarted()
        guard keychainReady else { pendingPairing = true; return }   // kimlik yuklenince devam eder
        let state = pairingGate.open()
        pairingCode = state.code
        pairingExpiresAt = state.expiresAt
        pairingNote = nil
        pairingTimer?.cancel()
        pairingTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PairingGate.lifetime + 0.5))
            guard !Task.isCancelled else { return }
            self?.refreshPairing()
        }
    }

    func cancelPairing() {
        pendingPairing = false
        pairingGate.close()
        pairingTimer?.cancel()
        pairingCode = nil; pairingExpiresAt = nil
    }

    /// Kapinin gercek durumunu arayuze yansitir (suresi doldu / kilitlendi).
    private func refreshPairing() {
        let st = pairingGate.state
        if st.code == nil && pairingCode != nil {
            pairingCode = nil; pairingExpiresAt = nil
            if pairingNote == nil { pairingNote = st.locked ? Self.lockedNote : "Kodun süresi doldu. Yeni kod üretin." }
        }
    }

    private static let lockedNote = "Üç kez yanlış kod girildi; eşleştirme kilitlendi. Yeni kod üretin."

    func confirmSAS(accepted: Bool) {
        sasCode = nil
        onSASChange?(nil)
        server.confirmSAS(accepted: accepted)
    }

    func unpair() {
        rfcomm.cancel()
        server.disconnectAll()
        server.setPinned(nil)
        Task { await PeerStore.clearPin() }
        pin = nil
        keyMismatch = false
        sasCode = nil
        onSASChange?(nil)
        snapshot.reset()
        contactIndex.reset()
        ContactPhotoCache.clear()
        resetLive()
    }

    func dismissKeyMismatch() { keyMismatch = false }

    // MARK: Komutlar (izinler telefonda uygulanir; izin yoksa telefon `izin_yok` doner)

    func answer() { server.send(PeerEnvelope(.callAnswer)) }
    func reject() { server.send(PeerEnvelope(.callReject)) }
    func dismissCallError() { callError = nil }

    /// Aramayi kapatir: aninda "Kapatiliyor", 4 sn icinde `call.state` bosta gelmezse hata gosterilir.
    func hangup() {
        guard hangupPhase == .bosta else { return }
        callError = nil
        hangupPhase = .kapatiliyor
        let sent = server.send(PeerEnvelope(.callHangup))
        log(sent ? "call.hangup gönderildi" : "call.hangup gönderilemedi (oturum kurulu değil)")
        guard sent else { failHangup("telefon bağlantısı yok"); return }
        hangupTask?.cancel()
        hangupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.hangupPhase == .kapatiliyor, self.snapshot.isInCall else { return }
            self.log("call.hangup: 4 sn içinde call.state bosta gelmedi")
            self.failHangup("telefon 4 saniye içinde aramayı bitirmedi")
        }
    }

    private func failHangup(_ reason: String) {
        hangupTask?.cancel()
        hangupPhase = .bosta
        callError = "Arama sonlandırılamadı: \(reason)"
    }

    private func endHangup() {
        hangupTask?.cancel()
        hangupPhase = .bosta
        callError = nil
    }

    /// Yalnizca arama tusu karakterleri (0-9 + * #) gonderilir.
    func dial(_ raw: String) {
        let number = Self.dialable(raw)
        guard !number.isEmpty else { return }
        server.send(PeerEnvelope(.callDial(CallDial(numara: number))))
    }

    static func dialable(_ raw: String) -> String { raw.filter { "0123456789+*#".contains($0) } }

    /// Numaradan rehber kisisi (gelen arama karti, son aramalar).
    func contact(for number: String?) -> ContactRecord? { contactIndex.match(number: number) }

    /// Rehberi bastan, sayfa sayfa yeniden ister (devam eden senkron varsa dokunmaz).
    func refreshContacts() {
        guard snapshot.allows(.kisiler), !snapshot.contactsLoading else { return }
        snapshot.contactsLoading = true
        if !server.send(PeerEnvelope(.contactsSync(ContactsSync(ofset: 0, adet: PhoneSnapshot.contactPageSize)))) {
            snapshot.contactsLoading = false
        }
    }

    func refreshCallLog() {
        guard snapshot.allows(.aramaGecmisi), !snapshot.callLogLoading else { return }
        snapshot.callLogLoading = true
        if !server.send(PeerEnvelope(.callLogSync(CallLogSync(ofset: 0, adet: PhoneSnapshot.callLogPageSize)))) {
            snapshot.callLogLoading = false
        }
    }

    // MARK: Ic

    private func established(key: Data, name: String) {
        pairingGate.close()
        pairingTimer?.cancel()
        pairingCode = nil; pairingExpiresAt = nil; pairingNote = nil
        if pin?.key != key || pin?.name != name {
            let newPin = PeerPin(key: key, name: name)
            pin = newPin
            server.setPinned(key)
            Task { [weak self] in
                if await !PeerStore.savePin(newPin) {
                    self?.storageWarning = "Eşleşme diske yazılamadı; uygulama yeniden başlayınca telefonla yeniden eşleşmeniz gerekir."
                }
            }
        }
        keyMismatch = false
        sasCode = nil
        onSASChange?(nil)
        isConnected = true
        let broker = broker
        Task { await broker.setConnected(true) }
        onSessionChange?(true)
        sendMacVolume()
    }

    // MARK: Ses senkronu

    private func scheduleMacVolumeSend() {
        guard isConnected else { return }
        volumeDebounce?.cancel()
        volumeDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.sendMacVolume()
        }
    }

    private func sendMacVolume() {
        guard isConnected, macVolume.isSupported else { return }
        let state = VolState(cihaz: "mac", seviye: Int((macVolume.level * 100).rounded()), sessiz: macVolume.muted)
        _ = server.send(PeerEnvelope(.volState(state)))
    }

    /// Telefon medya sesini ayarlar (kaydirici: 200 ms debounce); sessiz: hemen.
    func setPhoneVolume(_ percent: Int) {
        let level = min(max(percent, 0), 100)
        snapshot.phoneVolume = VolState(cihaz: "telefon", seviye: level, sessiz: snapshot.phoneVolume?.sessiz ?? false)
        phoneVolumeDebounce?.cancel()
        phoneVolumeDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            _ = self?.server.send(PeerEnvelope(.volSet(VolSet(hedef: "telefon", seviye: level))))
        }
    }

    func setPhoneMuted(_ muted: Bool) {
        if let v = snapshot.phoneVolume { snapshot.phoneVolume = VolState(cihaz: "telefon", seviye: v.seviye, sessiz: muted) }
        _ = server.send(PeerEnvelope(.volSet(VolSet(hedef: "telefon", sessiz: muted))))
    }

    private func applyVolSet(_ s: VolSet) {
        guard s.hedef == "mac", macVolume.isSupported else { return }
        if let l = s.seviye { macVolume.set(Double(l) / 100) }
        if let m = s.sessiz { macVolume.setMuted(m) }
    }

    /// Kurulu oturuma mesaj yollar (ctl.*); oturum yoksa false.
    @discardableResult
    func sendMedia(_ command: String) { _ = server.send(PeerEnvelope(.mediaCmd(MediaCmd(komut: command)))) }

    func sendPeer(_ message: PeerMessage) -> Bool { server.send(PeerEnvelope(message)) }

    private func receive(_ envelope: PeerEnvelope) {
        switch envelope.message {
        case .ctlOwner, .ctlWrite, .ctlNotify:
            onControl?(envelope.message)
            return
        default: break
        }
        if case .mediaCmd(let c) = envelope.message {
            MediaKeys.perform(c.komut)   // telefondan gelen komut: Mac medya tusu
            return
        }
        if case .volSet(let s) = envelope.message {
            applyVolSet(s)
            return
        }
        let before = snapshot.call
        for reply in snapshot.apply(envelope) { server.send(reply) }
        if case .contactsPage(let page) = envelope.message, page.ofset == 0 { contactIndex.reset() }
        contactIndex.sync(with: snapshot.contactBook)
        let broker = broker
        Task { await broker.handle(envelope) }

        switch envelope.message {
        case .callState(let new):
            log("call.state durum=\(new.durum.rawValue) sureSn=\(new.sureSn.map(String.init) ?? "-")")
            if new.durum == .bosta { endHangup() }
            updateCallClock(old: before, new: new)
            let t = PhoneSnapshot.transition(from: before, to: new)
            if t != .yok { onCallTransition?(t, snapshot) }
        case .error(let e):
            log("hata yanıtı kod=\(e.kod) mesaj=\(e.mesaj)")
            if hangupPhase == .kapatiliyor {
                if e.kod == "izin_yok" {
                    hangupTask?.cancel()
                    hangupPhase = .bosta
                    callError = "Telefon aramayı uygulamadan kapatmaya izin vermiyor"
                } else {
                    failHangup(e.mesaj)
                }
            }
        default:
            break
        }
    }

    private func updateCallClock(old: CallState, new: CallState) {
        guard new.durum == .acik else { callStartedAt = nil; return }
        if let s = new.sureSn { callStartedAt = Date().addingTimeInterval(-TimeInterval(s)) }
        else if old.durum != .acik || callStartedAt == nil { callStartedAt = Date() }
    }

    private func closed(_ reason: PeerSessionError?, wasActive: Bool) {
        if wasActive {
            resetLive()
        } else {
            switch reason {
            case .kodYanlis?: pairingNote = "Telefonda yanlış kod girildi."
            case .kodKilitlendi?: pairingNote = Self.lockedNote
            case .kodGerekli?: pairingNote = "Telefon kodsuz bağlanmayı denedi; telefonda kodu girmesi isteniyor."
            default: break
            }
            refreshPairing()
            if reason == .anahtarUyusmuyor { keyMismatch = true }
            if sasCode != nil {
                sasCode = nil
                onSASChange?(nil)
            }
        }
    }

    /// Baglanti yok: canli durum (arama, kulaklik) gecersiz; son bilinen telefon bilgisi kalir.
    private func resetLive() {
        let was = snapshot.call
        endHangup()
        isConnected = false
        connectionPath = nil
        callStartedAt = nil
        volumeDebounce?.cancel(); phoneVolumeDebounce?.cancel()
        snapshot.disconnected()
        contactIndex.reset()
        ContactPhotoCache.clear()
        if was.durum != .bosta { onCallTransition?(.bitti, snapshot) }
        let broker = broker
        Task { await broker.setConnected(false) }
        onSessionChange?(false)
    }
}
