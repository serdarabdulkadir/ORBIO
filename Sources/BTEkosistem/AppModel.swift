// Uygulama modeli: saglayici + motor + kart paneli + ayar kaliciligi.
import AppKit
import Observation
import EkosistemCore

/// Panelin ustunde gosterilen tek satirlik bildirim (sistem bildirimi yerine; paket bildirim izni gerektirmez).
struct Banner: Equatable, Identifiable {
    enum Action: Equatable { case undo, returnTo(PlaybackHost, deviceID: String) }
    let id = UUID()
    let symbol: String
    let text: String
    var action: Action?
    var actionTitle: String?
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(mock: CommandLine.arguments.contains("--mock"))

    let engine: EkosistemEngine
    let isMock: Bool
    let volume = SystemVolume()
    /// Telefon kanali (eslesme, baglanti, arama). Sahte modda baslatilmaz.
    let phone: PhoneModel
    /// Panelin secili sekmesi ("Kulaklik" | "Telefon"); hatirlanir.
    private(set) var panelTab: PanelTab
    private(set) var permission: PermissionState
    private(set) var banner: Banner?
    var selectedID: String?
    /// Cihazdan okunan QCY durumu; okunmayan alanlar nil, arayuz yalnizca dolu olanlari gosterir.
    private(set) var qcyStates: [String: QcyDeviceState] = [:]
    /// QCY A001 kontrol kanalinin durumu (yoksa henuz baglaniyor sayilir).
    private(set) var qcyLinks: [String: QcyLinkStatus] = [:]
    /// Ilk okunan tus eslemesi ("Onceki degere don" icin).
    /// Kontrolu telefon uzerinden giden cihazlar (kanal sahibi telefon).
    private(set) var qcyRemote: Set<String> = []
    /// AAP kanalindan okunan AirPods / Beats durumu (kanal hazirken); yoksa kanal yok = bilinmiyor.
    private(set) var airPodsStates: [String: AirPodsDeviceState] = [:]
    /// Cihaz basina bilinen Apple model kimligi (reklam ya da AAP'den); yetenekler buradan okunur.
    private(set) var appleModelIDs: [String: UInt16] = [:]
    /// Mac'in Bluetooth'u kapali (panelde bos durum metni).
    private(set) var bluetoothOff = false
    @ObservationIgnored private var relay: ControlRelay?
    @ObservationIgnored private var initialKeys: [String: QcyKeyMap] = [:]
    /// Cihazin KENDI bildirdigi durum (gercek); `qcyStates` bunun ustune bekleyen iyimser komutlari uygulanmis halidir.
    @ObservationIgnored private var deviceStates: [String: QcyDeviceState] = [:]
    @ObservationIgnored private var optimistic: [String: QcyOptimisticTracker] = [:]

    @ObservationIgnored private let provider: any DeviceProvider
    @ObservationIgnored private let cardController = ProximityCardController()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var card: CardModel?
    @ObservationIgnored private var cardTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var connectGate = ConnectCardGate(startedAt: Date())
    @ObservationIgnored private let connectedController = ProximityCardController()
    @ObservationIgnored private var connectedModel: ConnectedCardModel?
    @ObservationIgnored private var connectedTask: Task<Void, Never>?
    @ObservationIgnored private let callController = ProximityCardController(size: NSSize(width: 360, height: 230), anchor: .top)
    @ObservationIgnored private lazy var bubble = FloatingCallBubbleController(phone: phone, openPanel: { [weak self] in self?.openPhoneTab() })
    @ObservationIgnored private let pairingController = ProximityCardController(size: NSSize(width: 360, height: 230), anchor: .center)

    private static let settingsKey = "cihazAyarlari"
    private static let forgottenKey = "unutulanCihazlar"
    private static let lastConnectedKey = "sonBagliCihaz"
    private static let panelTabKey = "panelSekmesi"

    init(mock: Bool) {
        isMock = mock
        let cache = BatteryCache()
        let provider: any DeviceProvider = mock ? MockDeviceProvider() : BluetoothProvider(batteryCache: cache)
        self.provider = provider
        permission = provider.permission
        let phone = PhoneModel()
        self.phone = phone
        panelTab = UserDefaults.standard.string(forKey: Self.panelTabKey).flatMap(PanelTab.init(rawValue:)) ?? .kulaklik
        // Gercek kanal: telefona kulaklik birakma / baglanma istekleri. Sahte modda sahte kanal.
        engine = EkosistemEngine(peer: mock ? provider.peerChannel : phone.channel, route: provider.audioRoute,
                                 systemBattery: { cache.reading(for: $0) })
    }

    func setPanelTab(_ tab: PanelTab) {
        panelTab = tab
        defaults.set(tab.rawValue, forKey: Self.panelTabKey)
        if tab == .telefon { startPhoneOnDemand() }
    }

    func start() {
        guard tasks.isEmpty else { return }
        provider.onPermissionChange = { [weak self] in self?.permission = $0 }
        provider.onQcyLink = { [weak self] id, status in
            guard let self else { return }
            qcyLinks[id] = status
            if status != .hazir { optimistic[id]?.removeAll() } // kanal yok: bekleyen iyimser komut gecersiz
        }
        provider.onQcyState = { [weak self] id, state in
            guard let self else { return }
            deviceStates[id] = state
            if state == QcyDeviceState() { optimistic[id]?.removeAll() } // kanal koptu: durum bilinmiyor
            if initialKeys[id] == nil, let k = state.keys { initialKeys[id] = k }
            // Cihaz bildirimi gercek durumdur; bekleyen (henuz onaylanmamis) komutlar uzerine uygulanir.
            let shown = optimistic[id]?.isEmpty == false
                ? optimistic[id]!.reconcile(device: state, now: Date())
                : state
            applyShown(id, shown)
        }
        if let bt = provider as? BluetoothProvider {
            appleModelIDs = bt.appleModelIDs
            bt.onAppleModel = { [weak self] id, modelID in self?.appleModelIDs[id] = modelID }
            bt.onPowerOff = { [weak self] off in
                self?.bluetoothOff = off
                self?.phone.bluetoothAvailable = !off
            }
            bt.onAirPods = { [weak self] id, state in self?.airPodsStates[id] = state }
            let phone = phone
            let relay = ControlRelay(provider: bt, send: { phone.sendPeer($0) })
            relay.onRemoteChange = { [weak self] id, remote in
                if remote { self?.qcyRemote.insert(id) } else { self?.qcyRemote.remove(id) }
            }
            phone.onControl = { [weak relay] in relay?.receive($0) }
            phone.onSessionChange = { [weak relay, weak bt] up in
                if up {
                    relay?.sessionEstablished(ownedIDs: bt?.ownedChannelIDs ?? [])
                } else {
                    relay?.sessionClosed()
                }
            }
            self.relay = relay
        }
        let saved = loadSettings()
        let forgotten = Set(defaults.stringArray(forKey: Self.forgottenKey) ?? [])
        let source = provider.events
        let (stream, cont) = AsyncStream.makeStream(of: DeviceEvent.self)
        tasks.append(Task {
            for await event in source {
                if case .kayit(let device, nil) = event {
                    if forgotten.contains(device.id) { continue }
                    cont.yield(.kayit(device, settings: saved[device.id]))
                } else {
                    cont.yield(event)
                }
            }
            cont.finish()
        })
        tasks.append(Task { await engine.run(events: stream) })
        tasks.append(Task { for await o in engine.outputs { handle(o) } })
        if CommandLine.arguments.contains("--verbose") {
            engine.cardLog = { print("[kart] \($0)"); fflush(stdout) }
        }
        volume.start()
        provider.start()
        permission = provider.permission
        startPhone()
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                self?.checkConnections()
                self?.bubble.sync()
                try? await Task.sleep(for: .milliseconds(500))
            }
        })
    }

    // MARK: Telefon

    private func startPhone() {
        phone.onCallTransition = { [weak self] transition, _ in self?.callChanged(transition) }
        phone.onSASChange = { [weak self] code in self?.pairingChanged(code) }
        // Anahtar Zinciri'ne acilista dokunma: sunucu yalnizca pin'li telefon bayragi varsa (arka planda)
        // ya da kullanici Telefon sekmesini / ayarlarini / "Telefonu esle"yi acinca baslar (`ensureStarted`).
        if !isMock && (PeerStore.pairedFlag || panelTab == .telefon) { phone.start() }
    }

    /// Telefon sekmesi, Ayarlar > Telefon ya da "Telefonu esle" acilinca sunucuyu (ve Yerel Ag iznini) tetikler.
    func startPhoneOnDemand() { if !isMock { phone.ensureStarted() } }

    /// Baloncuga basinca: panel Telefon sekmesine gecer ve menu cubugu ogesi tiklanarak acilir.
    func openPhoneTab() {
        setPanelTab(.telefon)
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let button = Self.findStatusButton(in: window.contentView) { button.performClick(nil); return }
        }
    }

    private static func findStatusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let b = view as? NSStatusBarButton { return b }
        for sub in view.subviews { if let b = findStatusButton(in: sub) { return b } }
        return nil
    }

    /// Gelen arama: kisa kart + motora "cagri basladi/bitti" (Otomatik gecis kurali icin).
    private func callChanged(_ transition: CallTransition) {
        switch transition {
        case .gelenBasladi:
            engine.handle(.cagri(started: true))
            // Baloncuk aciksa gelen arama orada gosterilir (cift bildirim olmasin).
            if !phone.bubbleEnabled { callController.present(IncomingCallCardView(phone: phone, close: { [weak self] in self?.callController.hide() })) }
            watchIncomingCall()
        case .bitti:
            engine.handle(.cagri(started: false))
            callController.hide()
        case .yok:
            break
        }
    }

    /// Arama caliyor olmaktan cikinca (cevaplandi / reddedildi) kart kapanir.
    private func watchIncomingCall() {
        Task { [weak self] in
            while let self, self.phone.isRinging {
                try? await Task.sleep(for: .milliseconds(300))
            }
            self?.callController.hide()
        }
    }

    private func pairingChanged(_ code: String?) {
        if code != nil {
            pairingController.present(PairingCardView(phone: phone))
            setPanelTab(.telefon)
        } else {
            pairingController.hide()
        }
    }

    func openLocalNetworkPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Baglandi karti

    /// Bilinen kulaklik Bu Mac'e BAGLANDIGI an kisa onay karti. Yaklasma karti aciksa (kendi "Baglandi" asamasi var) gosterilmez.
    private func checkConnections() {
        let now = Date()
        for d in engine.devices {
            let s = settings(for: d.id)
            let show = connectGate.observe(deviceID: d.id, state: d.state, proximityEnabled: s.proximityCard,
                                           silent: s.silent, screenLocked: engine.screenLocked, at: now)
            if show, card == nil { showConnectedCard(d) }
        }
        if let m = connectedModel, let d = engine.devices.first(where: { $0.id == m.device.id }) { m.device = d }
    }

    private func showConnectedCard(_ device: Device) {
        let model = ConnectedCardModel(device: device)
        connectedModel = model
        connectedController.present(ConnectedCardView(model: model))
        connectedTask?.cancel()
        connectedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ConnectCardGate.visibleDuration))
            guard !Task.isCancelled, let self, self.connectedModel === model else { return }
            self.connectedModel = nil
            self.connectedController.hide()
        }
    }

    /// Panelde yalnizca su an bagli olanlar; hic biri bagli degilse son bagli olan cihaz.
    var visibleDevices: [Device] {
        let connected = engine.devices.filter { $0.state == .bagliBuMac || $0.state == .bagliTelefon }
        if let first = connected.first {
            if defaults.string(forKey: Self.lastConnectedKey) != first.id { defaults.set(first.id, forKey: Self.lastConnectedKey) }
            return connected
        }
        if let last = defaults.string(forKey: Self.lastConnectedKey),
           let d = engine.devices.first(where: { $0.id == last }) { return [d] }
        return []
    }

    var primary: Device? {
        let list = visibleDevices
        return list.first { $0.id == selectedID } ?? list.first
    }

    var secondary: Device? {
        visibleDevices.first { $0.id != primary?.id }
    }

    /// Ses modu / kulak algilama gercekten cihaza yazilabiliyor mu? Simdilik yalniz sahte saglayicida.
    func supportsDeviceControl(_ device: Device) -> Bool { provider.supportsListeningControl(device.id) }

    func isQcy(_ device: Device) -> Bool { provider.isQcy(device.id) }

    // MARK: AirPods / Beats (AAP)

    /// Katalogdaki model; yalniz Apple profilinde ve kimlik biliniyorsa. Yetenekler (`supports`) buradan.
    func appleModel(for device: Device) -> AppleModel? {
        guard device.profile == .apple else { return nil }
        return (device.appleModelID ?? appleModelIDs[device.id]).flatMap(AppleModelCatalog.model(forID:))
    }

    /// AAP kanali hazirsa guncel durum; degilse nil (kontroller soluk / gizli).
    func airPods(for id: String) -> AirPodsDeviceState? { airPodsStates[id] }

    @discardableResult
    func sendAirPods(_ command: AirPodsCommand, to device: Device) -> Bool {
        guard let bt = provider as? BluetoothProvider else { return false }
        return bt.sendAirPods(command, for: device.id)
    }
    /// Kontrol kanalini telefon tutuyor; komutlar telefon uzerinden gider.
    func isRemoteControlled(_ id: String) -> Bool { qcyRemote.contains(id) }
    /// Devir dugmesi: yalniz peer oturumu aciksa gorunur. Telefon sahipse "Mac'e al", Mac sahipse "telefona ver".
    enum ControlOwnerAction { case macAl, telefonaVer }
    func controlOwnerAction(for device: Device) -> ControlOwnerAction? {
        guard isQcy(device), phone.isConnected, relay?.isSessionUp == true else { return nil }
        if isRemoteControlled(device.id) { return .macAl }
        if qcyLink(for: device.id) == .hazir { return .telefonaVer }
        return nil
    }
    func performControlOwnerAction(_ action: ControlOwnerAction, for device: Device) {
        switch action {
        case .macAl: relay?.takeControl(device.id)
        case .telefonaVer: relay?.giveControl(device.id)
        }
    }
    func qcyLink(for id: String) -> QcyLinkStatus { qcyLinks[id] ?? .baglaniyor }
    func retryQcyLink(_ device: Device) { provider.reconnect(device.id) }
    func canRestoreTouch(_ device: Device) -> Bool {
        guard let first = initialKeys[device.id] else { return false }
        return first != qcyStates[device.id]?.keys
    }
    func restoreTouch(_ device: Device) {
        if let first = initialKeys[device.id] { send(.keys(first), to: device) }
    }

    func qcyState(for id: String) -> QcyDeviceState { qcyStates[id] ?? QcyDeviceState() }

    func setListeningMode(_ device: Device, _ mode: ListeningMode) { send(.mode(mode), to: device) }

    /// Oyun modu / EQ on ayari yazma komutlari `send` hattina bagli.
    static let extendedWriteAvailable = true

    func setGameMode(_ device: Device, _ enabled: Bool) { send(.gameMode(enabled), to: device) }

    func setEqPreset(_ device: Device, _ preset: QcyEqPreset) { send(.eqPreset(preset), to: device) }

    /// Ozel 10 bant EQ (dB); yazilir, geri okunmaz.
    func setCustomEq(_ device: Device, _ gains: [Int]) { send(.customEq(gains), to: device) }

    func setTouch(_ device: Device, side: QcyTouchSide, gesture: QcyTouchGesture, function: QcyKeyFunction) {
        send(.touch(side, gesture, function), to: device)
    }

    /// Komutu iyimser uygular; yazma basarisizsa onceki duruma doner. Gercek durum okuma yanitiyla duzelir.
    /// Cift cihaz ve dokunmatik ayarlar iyimser uygulanmaz: yazma sonrasi geri okunan deger gosterilir,
    /// beklenenle uyusmazsa uyari cikar (yazma tekrarlanmaz).
    func send(_ command: QcyCommand, to device: Device) {
        let id = device.id
        let previousState = qcyState(for: id)
        let previousMode = settings(for: id).listeningMode
        let previousEar = settings(for: id).earDetection
        guard command.packet(state: previousState) != nil else {
            show(Banner(symbol: "exclamationmark.triangle.fill", text: "Bu ayar için cihazdan veri okunmadı; komut gönderilemedi."))
            return
        }
        if command.verifiedByReadback {
            Task {
                guard await provider.send(command, for: id) else {
                    show(Banner(symbol: "exclamationmark.triangle.fill", text: "Komut gönderilemedi: kontrol kanalı kapalı."))
                    return
                }
                for _ in 0..<16 {
                    try? await Task.sleep(for: .milliseconds(250))
                    if command.isSatisfied(by: qcyState(for: id)) { return }
                }
                let text: String
                if case .multipoint = command { text = "Bu kulaklık çift cihaz ayarını değiştirmedi." }
                else if case .transparencyLevel = command { text = "Bu kulaklık şeffaflık seviyesini değiştirmedi." }
                else { text = "Bu kulaklık dokunmatik kontrol ayarını değiştirmedi." }
                show(Banner(symbol: "exclamationmark.triangle.fill", text: text))
            }
            return
        }
        // Iyimser: hemen gosterilir ama KESIN degil; cihaz bildirimi/geri okumasi gelince onaylanir, gelmezse geri alinir.
        optimistic[id, default: QcyOptimisticTracker()].begin(command, now: Date())
        let next = previousState.applying(command)
        qcyStates[id] = next
        update(id) {
            if let m = next.mode { $0.listeningMode = m }
            if let w = next.wearing { $0.earDetection = w.enabled }
        }
        Task {
            if await !provider.send(command, for: id) {
                // Yazilamadi: bu komutun bekleyen kaydi silinir, cihazin gercek durumuna (yoksa onceki) donulur.
                optimistic[id]?.removeAll()
                qcyStates[id] = deviceStates[id] ?? previousState
                show(Banner(symbol: "exclamationmark.triangle.fill", text: "Komut gönderilemedi: kontrol kanalı kapalı."))
                update(id) { $0.listeningMode = previousMode; $0.earDetection = previousEar }
                return
            }
            try? await Task.sleep(for: .seconds(QcyOptimisticTracker.defaultTimeout + 0.3))
            expireOptimistic(id, previousMode: previousMode, previousEar: previousEar)
        }
    }

    /// Gosterilecek durumu arayuze ve ayarlara yansitir (yalniz dolu alanlar; bos = bilinmiyor).
    private func applyShown(_ id: String, _ shown: QcyDeviceState) {
        qcyStates[id] = shown
        update(id) {
            if let mode = shown.mode { $0.listeningMode = mode }
            if let w = shown.wearing { $0.earDetection = w.enabled }
        }
    }

    /// Zaman asimi: cihaz komutu onaylamadiysa arayuz cihazin gercek durumuna doner ve uyarir.
    private func expireOptimistic(_ id: String, previousMode: ListeningMode, previousEar: Bool) {
        guard var tracker = optimistic[id] else { return }
        let dead = tracker.expire(now: Date())
        guard !dead.isEmpty else { optimistic[id] = tracker; return }
        let truth = deviceStates[id] ?? QcyDeviceState()
        let shown = tracker.reconcile(device: truth, now: Date())
        optimistic[id] = tracker
        qcyStates[id] = shown
        update(id) {
            $0.listeningMode = shown.mode ?? previousMode
            $0.earDetection = shown.wearing?.enabled ?? previousEar
        }
        show(Banner(symbol: "exclamationmark.triangle.fill", text: "Kulaklık değişikliği onaylamadı; kulaklığın gerçek durumu gösteriliyor."))
    }

    func settings(for id: String) -> DeviceSettings { engine.settings[id] ?? DeviceSettings() }

    func update(_ id: String, _ change: (inout DeviceSettings) -> Void) {
        engine.updateSettings(for: id, change)
        defaults.set(try? JSONEncoder().encode(engine.settings), forKey: Self.settingsKey)
    }

    func forget(_ id: String) {
        var list = defaults.stringArray(forKey: Self.forgottenKey) ?? []
        if !list.contains(id) { list.append(id) }
        defaults.set(list, forKey: Self.forgottenKey)
        engine.handle(.unut(deviceID: id))
        connectGate.forget(deviceID: id)
        if selectedID == id { selectedID = nil }
        defaults.set(try? JSONEncoder().encode(engine.settings), forKey: Self.settingsKey)
    }

    func refresh() { provider.refresh() }

    func transfer(_ id: String, to host: PlaybackHost) {
        Task { _ = await engine.transfer(deviceID: id, to: host) }
    }

    func perform(_ action: Banner.Action) {
        switch action {
        case .undo: Task { _ = await engine.undoLastSwitch() }
        case .returnTo(let host, let id): transfer(id, to: host)
        }
        banner = nil
    }

    func dismissBanner() { banner = nil }

    func openBluetoothPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Ic

    private func loadSettings() -> [String: DeviceSettings] {
        guard let data = defaults.data(forKey: Self.settingsKey),
              let decoded = try? JSONDecoder().decode([String: DeviceSettings].self, from: data) else { return [:] }
        return decoded
    }

    private func name(_ id: String) -> String { engine.devices.first { $0.id == id }?.name ?? "Kulaklık" }

    private func handle(_ output: EngineOutput) {
        switch output {
        case .kartGoster(let content):
            guard let device = engine.devices.first(where: { $0.id == content.deviceID }) else { return }
            cardTask?.cancel()
            let model = CardModel(content: content, device: device)
            card = model
            cardController.show(model: model,
                                connect: { [weak self] in self?.connectFromCard() },
                                close: { [weak self] in self?.closeCard() })
            watchCard(model)
        case .kartKapat:
            // Baglanma / onay / hata asamasinda kart kendi zamanlayicisiyla kapanir.
            if card?.phase ?? .normal == .normal { closeCard() }
        case .bildirim(let n):
            show(banner(for: n))
        }
    }

    private func closeCard() {
        cardTask?.cancel()
        card = nil
        engine.dismissCard()
        cardController.hide()
    }

    private func connectFromCard() {
        guard let card, card.phase == .normal || card.phase == .failed else { return }
        let id = card.content.deviceID
        card.phase = .connecting
        Task { [weak self] in
            let outcome = await self?.engine.transfer(deviceID: id, to: .buMac)
            guard let self, self.card === card, card.phase == .connecting else { return }
            switch outcome {
            case .basarili, .ipucu: finishCard(card)
            default: failCard(card)
            }
        }
    }

    private func finishCard(_ card: CardModel) {
        card.phase = .connected
        cardTask?.cancel()
        cardTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled, self?.card === card { self?.closeCard() }
        }
    }

    private func failCard(_ card: CardModel) {
        card.phase = .failed
        cardTask?.cancel()
        cardTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled, self?.card === card, card.phase == .failed { self?.closeCard() }
        }
    }

    /// Kart acikken cihaz durumunu (pil, baglanti) canli tasir; bagliBuMac olunca onay gosterip kapatir.
    private func watchCard(_ model: CardModel) {
        Task { [weak self] in
            while let self, self.card === model {
                if let d = engine.devices.first(where: { $0.id == model.content.deviceID }) {
                    model.device = d
                    if d.state == .bagliBuMac {
                        switch model.phase {
                        case .connecting, .failed: finishCard(model)
                        case .normal: closeCard()
                        case .connected: break
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func banner(for n: EngineNotification) -> Banner {
        switch n {
        case .dusukPil(let a):
            Banner(symbol: "battery.25percent", text: "\(name(a.deviceID)) \(a.channel.label.lowercased()) pili %\(a.percent): şarj edin.")
        case .otomatikGecis(let d, _):
            Banner(symbol: "arrow.left.arrow.right",
                   text: "\(name(d.deviceID)) \(d.target == .telefon ? "telefona" : "bu Mac'e") geçti.",
                   action: .undo, actionTitle: "Geri al")
        case .geriDonusOnerisi(let s):
            Banner(symbol: "phone.down.fill", text: "Çağrı bitti. Ses bu Mac'e dönsün mü?",
                   action: .returnTo(s.owner, deviceID: s.deviceID), actionTitle: "Mac'e döndür")
        case .gecisIpucu:
            Banner(symbol: "info.circle", text: "Telefondan ayırın: kulaklık hâlâ telefona bağlı olabilir.")
        case .gecisHatasi:
            Banner(symbol: "exclamationmark.triangle.fill",
                   text: "Bağlanamadı. Kulaklıktaki düğmeye basıp tekrar deneyin.")
        }
    }

    private func show(_ b: Banner) {
        banner = b
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(b.action == nil ? 10 : 30))
            if !Task.isCancelled, self?.banner?.id == b.id { self?.banner = nil }
        }
    }
}
