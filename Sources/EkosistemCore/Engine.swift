// Tum parcalari birlestiren gozlemlenebilir model: olaylar girer, UI durumu ve komutlar cikar.
import Foundation
import Observation

/// Saglayicilarin (IOBluetooth, CoreBluetooth, es kanali, sistem) motora verdigi olaylar.
public enum DeviceEvent: Sendable {
    /// Cihaz kaydi eklenir / guncellenir. Mevcutsa ayarlar korunur.
    case kayit(Device, settings: DeviceSettings? = nil)
    case unut(deviceID: String)
    /// BLE reklam paketi. `battery` reklamdan cozulduyse dolu.
    case reklam(deviceID: String, rssi: Int, battery: BatteryReading?)
    case baglanti(deviceID: String, ConnectionStatus)
    case pil(deviceID: String, BatteryReading)
    case ekranKilit(Bool)
    /// `host` tarafinda medya basladi.
    case medya(host: PlaybackHost)
    /// Telefonda cagri basladi / bitti.
    case cagri(started: Bool)
}

public enum EngineNotification: Equatable, Sendable {
    case dusukPil(LowBatteryAlert)
    /// Otomatik gecis oldu; `undo` suresi dolana kadar "Geri al" gosterilir.
    case otomatikGecis(AutoSwitchDecision, undo: UndoOffer)
    case geriDonusOnerisi(ReturnSuggestion)
    /// Yerel baglandi, karsi taraf sahip olabilir ("Telefondan ayirin").
    case gecisIpucu(deviceID: String)
    case gecisHatasi(deviceID: String)
}

/// Motorun UI'ya verdigi komutlar.
public enum EngineOutput: Equatable, Sendable {
    case kartGoster(CardContent)
    case kartKapat
    case bildirim(EngineNotification)
}

/// Es kanali yokken kullanilir (telefon ozellikleri kapali).
public struct NoPeerChannel: PeerChannel {
    public init() {}
    public var isAvailable: Bool { get async { false } }
    public func requestRelease(deviceID: String) async throws { throw CancellationError() }
    public func requestConnect(deviceID: String) async throws { throw CancellationError() }
    public func requestPlaybackOwnership(deviceID: String) async throws { throw CancellationError() }
    public func requestUndo(deviceID: String) async {}
}

@MainActor
@Observable
public final class EkosistemEngine {
    // MARK: Gozlemlenen durum
    public private(set) var devices: [Device] = []
    public private(set) var settings: [String: DeviceSettings] = [:]
    /// Veriyi degistiren son olayin zamani ("Guncellendi hh:mm").
    public private(set) var lastUpdate: Date?
    public private(set) var transferPhase: TransferPhase = .bosta
    public private(set) var transferringDeviceID: String?
    public private(set) var undoOffer: UndoOffer?
    public private(set) var screenLocked = false
    /// Son cikislar (en yeni sonda, en cok 50); hata ayiklama ve selftest icin.
    public private(set) var recentOutputs: [EngineOutput] = []

    /// UI komut akisi (tek tuketici).
    @ObservationIgnored public let outputs: AsyncStream<EngineOutput>
    /// Kart kapisi kararlari icin hata ayiklama gunlugu (--verbose).
    @ObservationIgnored public var cardLog: (@MainActor (String) -> Void)?

    // MARK: Ic durum
    private struct Record {
        var info: Device
        var reducer: DeviceStateReducer
    }
    @ObservationIgnored private var records: [Record] = []
    @ObservationIgnored private var gate = ProximityCardGate()
    @ObservationIgnored private var lowBattery = LowBatteryMonitor()
    @ObservationIgnored private var policy = AutoSwitchPolicy()
    @ObservationIgnored private var autoTask: Task<Void, Never>?
    @ObservationIgnored private let continuation: AsyncStream<EngineOutput>.Continuation
    @ObservationIgnored private let clock: any EngineClock
    @ObservationIgnored private let peer: any PeerChannel
    @ObservationIgnored private let route: any AudioRoute
    @ObservationIgnored private let systemBattery: @Sendable (String) -> BatteryReading?

    public init(clock: any EngineClock = SystemClock(),
                peer: any PeerChannel = NoPeerChannel(),
                route: any AudioRoute,
                systemBattery: @escaping @Sendable (String) -> BatteryReading? = { _ in nil }) {
        self.clock = clock; self.peer = peer; self.route = route; self.systemBattery = systemBattery
        (outputs, continuation) = AsyncStream.makeStream(of: EngineOutput.self)
    }

    // MARK: Girisler

    /// Olay akisini tuketir ve saniyede bir `tick()` calistirir; iptal edilince doner.
    public func run(events: AsyncStream<DeviceEvent>) async {
        let clock = self.clock
        let ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: 1) } catch { return }
                self?.tick()
            }
        }
        defer { ticker.cancel() }
        for await event in events { handle(event) }
    }

    public func handle(_ event: DeviceEvent) {
        let now = clock.now
        switch event {
        case .kayit(let device, let newSettings):
            if let i = index(device.id) {
                records[i].info.name = device.name
                records[i].info.profile = device.profile
                records[i].info.supportsMultipoint = device.supportsMultipoint
            } else {
                var reducer = DeviceStateReducer(startedAt: now)
                if let b = device.battery { reducer.updateBattery(b) }
                records.append(Record(info: device, reducer: reducer))
            }
            if let newSettings { settings[device.id] = newSettings }
            else if settings[device.id] == nil { settings[device.id] = DeviceSettings() }
        case .unut(let id):
            records.removeAll { $0.info.id == id }
            settings[id] = nil
            lowBattery.reset(deviceID: id)
        case .baglanti(let id, let status):
            guard let i = index(id) else { return }
            records[i].reducer.setConnection(status, at: now)
        case .pil(let id, let reading):
            guard let i = index(id) else { return }
            records[i].reducer.updateBattery(reading)
            checkLowBattery(id, reading, now)
        case .reklam(let id, let rssi, let battery):
            guard let i = index(id) else { return }
            records[i].reducer.recordAdvertisement(at: now)
            if let battery {
                records[i].reducer.updateBattery(battery)
                checkLowBattery(id, battery, now)
            }
            considerCard(id, rssi: rssi, decoded: battery, now)
        case .ekranKilit(let locked):
            screenLocked = locked
            if locked, gate.dismiss() { emit(.kartKapat) }
        case .medya(let host):
            for r in records {
                let id = r.info.id
                let rule = settings[id]?.autoSwitch ?? .hicbirZaman
                if let d = policy.mediaStarted(deviceID: id, on: host, rule: rule, state: r.reducer.state(at: now), at: now) {
                    startAutomatic(d)
                }
            }
        case .cagri(let started):
            for r in records {
                let id = r.info.id
                if started {
                    let rule = settings[id]?.autoSwitch ?? .hicbirZaman
                    if let d = policy.callStarted(deviceID: id, rule: rule, state: r.reducer.state(at: now), at: now) {
                        startAutomatic(d)
                    }
                } else {
                    policy.callEnded(deviceID: id, at: now)
                }
            }
        }
        lastUpdate = now
        refresh()
    }

    /// Zamana bagli gecisleri isler: kart suresi, donus onerisi, "Geri al" suresi, durum dusmeleri.
    public func tick() {
        let now = clock.now
        if gate.dismissIfExpired(at: now) { emit(.kartKapat) }
        for s in policy.dueReturnSuggestions(at: now) {
            if let r = record(s.deviceID), currentHost(r, now) != s.owner {
                emit(.bildirim(.geriDonusOnerisi(s)))
            }
        }
        refresh()
    }

    /// Kart kapatma dugmesi gibi kullanici eylemi.
    public func dismissCard() {
        if gate.dismiss() { emit(.kartKapat) }
    }

    public func updateSettings(for deviceID: String, _ change: (inout DeviceSettings) -> Void) {
        guard index(deviceID) != nil else { return }
        var s = settings[deviceID] ?? DeviceSettings()
        change(&s)
        settings[deviceID] = s
    }

    // MARK: Ses gecisi

    /// Elle ses gecisi ("Buraya bagla" / "Telefona gonder").
    public func transfer(deviceID: String, to target: PlaybackHost) async -> TransferOutcome {
        await performTransfer(deviceID, to: target, automatic: nil)
    }

    /// "Geri al" (30 sn penceresi). Teklif yoksa nil.
    public func undoLastSwitch() async -> TransferOutcome? {
        guard let offer = policy.consumeUndo(at: clock.now) else { refresh(); return nil }
        refresh()
        return await performTransfer(offer.deviceID, to: offer.restoreTo, automatic: nil)
    }

    /// Suren otomatik gecisin bitmesini bekler (testler / selftest).
    public func waitForAutomaticTransfer() async {
        await autoTask?.value
    }

    private func startAutomatic(_ decision: AutoSwitchDecision) {
        guard autoTask == nil, transferringDeviceID == nil else { return }
        autoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.performTransfer(decision.deviceID, to: decision.target, automatic: decision)
            self.autoTask = nil
        }
    }

    private func performTransfer(_ id: String, to target: PlaybackHost, automatic: AutoSwitchDecision?) async -> TransferOutcome {
        guard transferringDeviceID == nil else { return .mesgul }
        guard let r = record(id) else { return .iptal }
        let startHost = currentHost(r, clock.now) ?? (target == .buMac ? .telefon : .buMac)
        transferringDeviceID = id
        let runner = TransferEngine(peer: peer, route: route, clock: clock) { [weak self] phase in
            Task { @MainActor in self?.transferPhase = phase }
        }
        let outcome = await runner.transfer(deviceID: id, to: target, multipoint: r.info.supportsMultipoint)
        transferringDeviceID = nil
        transferPhase = .bosta

        let now = clock.now
        switch outcome {
        case .basarili, .ipucu:
            if let i = index(id) {
                let local = target == .buMac
                records[i].reducer.setConnection(local ? .buMac : (outcome == .ipucu ? .degil : .telefon), at: now)
            }
            if let automatic {
                let offer = policy.recordSwitch(automatic, from: startHost, at: now)
                emit(.bildirim(.otomatikGecis(automatic, undo: offer)))
            } else {
                policy.recordManualSwitch(deviceID: id, at: now)
            }
            if outcome == .ipucu { emit(.bildirim(.gecisIpucu(deviceID: id))) }
        case .baglanamadi:
            emit(.bildirim(.gecisHatasi(deviceID: id)))
        case .iptal, .mesgul:
            break
        }
        lastUpdate = now
        refresh()
        return outcome
    }

    // MARK: Yardimcilar

    private func index(_ id: String) -> Int? { records.firstIndex { $0.info.id == id } }
    private func record(_ id: String) -> Record? { index(id).map { records[$0] } }

    private func currentHost(_ r: Record, _ now: Date) -> PlaybackHost? {
        switch r.reducer.state(at: now) {
        case .bagliBuMac: .buMac
        case .bagliTelefon: .telefon
        default: nil
        }
    }

    private func checkLowBattery(_ id: String, _ reading: BatteryReading, _ now: Date) {
        let alerts = lowBattery.observe(deviceID: id, reading: reading, at: now)
        guard settings[id]?.silent != true else { return }
        for a in alerts { emit(.bildirim(.dusukPil(a))) }
    }

    private func considerCard(_ id: String, rssi: Int, decoded: BatteryReading?, _ now: Date) {
        guard let s = settings[id], s.proximityCard, !s.silent else {
            cardLog?("kart bastirildi [\(id)]: ayar kapali ya da sessiz")
            return
        }
        let decision = gate.consider(deviceID: id, rssi: rssi, decoded: decoded, systemBattery: systemBattery(id),
                                     screenLocked: screenLocked,
                                     alreadyConnected: record(id).map { currentHost($0, now) == .buMac } ?? false,
                                     at: now)
        switch decision {
        case .goster(let content):
            cardLog?("kart gosterildi [\(id)] rssi=\(rssi) kaynak=\(content.source)")
            emit(.kartGoster(content))
        case .bastir(let why): cardLog?("kart bastirildi [\(id)] rssi=\(rssi): \(why)")
        case .bekle: cardLog?("kart bekliyor [\(id)] rssi=\(rssi) (esik \(ProximityCardGate.threshold(for: id)))")
        }
    }

    private func refresh() {
        let now = clock.now
        devices = records.map { r in
            var d = r.info
            d.state = r.reducer.state(at: now)
            d.battery = r.reducer.battery
            return d
        }
        undoOffer = policy.undoOffer(at: now)
    }

    private func emit(_ output: EngineOutput) {
        recentOutputs.append(output)
        if recentOutputs.count > 50 { recentOutputs.removeFirst(recentOutputs.count - 50) }
        continuation.yield(output)
    }
}
