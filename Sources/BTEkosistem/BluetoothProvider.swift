// Gercek saglayici: IOBluetooth (eslesmis cihazlar, baglanti), CoreBluetooth (0x004C reklam taramasi),
// sistem pil degeri (system_profiler). Izin durumu CoreBluetooth yetkisinden okunur.
import Foundation
import CoreBluetooth
import IOBluetooth
import EkosistemCore
import Synchronization

@MainActor
final class BluetoothProvider: NSObject, DeviceProvider {
    let events: AsyncStream<DeviceEvent>
    let audioRoute: any AudioRoute = IOBluetoothAudioRoute()
    let peerChannel: any PeerChannel = NoPeerChannel()
    var onPermissionChange: (@MainActor (PermissionState) -> Void)?

    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let batteryCache: BatteryCache
    private var central: CBCentralManager?
    private var pollTask: Task<Void, Never>?
    private var known: [String: Device] = [:]
    private var lastStatus: [String: ConnectionStatus] = [:]
    private var lastPermission: PermissionState?
    var onQcyState: (@MainActor (String, QcyDeviceState) -> Void)?
    /// Mac'in Bluetooth'u kapali mi (CoreBluetooth .poweredOff); acilinca false.
    var onPowerOff: (@MainActor (Bool) -> Void)?
    /// Kullanici "Kontrolu telefona ver" dedi: bu Mac GATT'i birakir ve telefon sahip olana dek denemez.
    private var qcyYielded: Set<String> = []
    private var qcyStates: [String: QcyDeviceState] = [:]
    // QCY: reklamdan bulunan BLE kontrol cihazi + A001 komut / yanit ozellikleri
    private var qcyPeripherals: [String: CBPeripheral] = [:]
    private var qcyCommand: [String: CBCharacteristic] = [:]
    private var qcyKeys: [String: CBCharacteristic] = [:]
    private var qcyLegacyEq: [String: CBCharacteristic] = [:]
    private var qcyLink: [String: QcyLinkStatus] = [:]
    private var qcyConnecting: Set<String> = []
    private var qcyBackoff: [String: QcyReconnectBackoff] = [:]
    private var qcyReadySince: [String: Date] = [:]
    private var qcyBattery: [String: CBCharacteristic] = [:]
    /// GATT 0008'den pil gelen cihazlar: bunlar icin reklam taramasi / sistem pili gerekmez.
    private var gattBattery: Set<String> = []
    // Tek yazma sirasi (cihaz basina): en az `writeInterval` arayla, ayni istek birlesir.
    private var writeQueues: [String: QcyWriteQueue] = [:]
    private var pumps: [String: Task<Void, Never>] = [:]
    private static let writeInterval: TimeInterval = 0.2
    private static let readBackDelay: TimeInterval = 0.35
    // Pencereli tarama (surekli tarama A2DP'de cizirti yapar).
    private var scanScheduler = ScanScheduler()
    private var scanTask: Task<Void, Never>?
    /// IOBluetooth eslesmis cihaz nesneleri onbellegi: her yoklamada `pairedDevices()` cagrilmaz.
    private var pairedCache: [String: IOBluetoothDevice] = [:]
    private var qcyNextAttempt: [String: Date] = [:]
    private var qcyRetry: [String: Task<Void, Never>] = [:]
    private var qcyTimeout: [String: Task<Void, Never>] = [:]
    var onQcyLink: (@MainActor (String, QcyLinkStatus) -> Void)?
    // Kanal sahibi + aktarim (ControlRelay): kulaklik tek BLE kontrol baglantisi kabul eder.
    /// Bu Mac kanalin sahibi mi oldu / olmaktan cikti (telefon uzerinden kontrolde tetiklenmez).
    var onLocalOwner: (@MainActor (String, Bool) -> Void)?
    /// Yerel kanaldan gelen 1002 yaniti ("yanit") ya da QCY reklami ("reklam", 1C 52 ile baslayan ham uretici verisi).
    var onQcyNotify: (@MainActor (_ deviceID: String, _ kind: String, _ bytes: [UInt8]) -> Void)?
    /// Telefon kanal sahibi: GATT denenmez, komutlar bu kapidan telefona gider.
    var relayWrite: (@MainActor (_ deviceID: String, _ bytes: [UInt8], _ kar: String?) -> Bool)?
    /// Telefon kanali su an komut alabilir mi (oturum acik ve telefon sahip)?
    var relayReady: (@MainActor (_ deviceID: String) -> Bool)?
    private(set) var qcyRemote: Set<String> = []
    private var qcyLocalOwned: [String: Bool] = [:]
    private var lastAdNotify: [String: Date] = [:]
    private static let connectTimeout: Double = 10
    private static let identifiersKey = "qcyKontrolKimlikleri"
    // AirPods / Beats AAP kanali (L2CAP 0x1001): yalniz bu Mac'e bagliyken acilir.
    private var airPodsChannels: [String: AirPodsChannel] = [:]
    /// AAP'den gelen son durum (kanal hazirken); yoksa yok.
    private var airPodsStates: [String: AirPodsDeviceState] = [:]
    /// Cihaz basina bilinen Apple model kimligi (reklam ya da AAP cihaz bilgisinden), kalici.
    private(set) var appleModelIDs: [String: UInt16] = BluetoothProvider.loadAppleModelIDs()
    var onAirPods: (@MainActor (_ deviceID: String, _ state: AirPodsDeviceState?) -> Void)?
    var onAppleModel: (@MainActor (_ deviceID: String, _ modelID: UInt16) -> Void)?
    private static let appleModelsKey = "appleModelKimlikleri"
    private let verbose = CommandLine.arguments.contains("--verbose")

    private func log(_ text: String) { if verbose { print("[bluetooth] \(text)"); fflush(stdout) } }

    init(batteryCache: BatteryCache) {
        self.batteryCache = batteryCache
        (events, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
        super.init()
    }

    var permission: PermissionState {
        switch CBManager.authorization {
        case .allowedAlways: .verildi
        case .notDetermined: .bekliyor
        default: .reddedildi
        }
    }

    func start() {
        guard central == nil else { return }
        // CBCentralManager olusturmak izin istemini tetikler.
        central = CBCentralManager(delegate: self, queue: .main)
        loadPairedDevices()
        pollTask = Task { [weak self] in
            var round = 0
            while !Task.isCancelled {
                guard let self else { return }
                if round % 20 == 0 && round > 0 { self.loadPairedDevices() }
                self.pollConnections()
                // Sistem pili (system_profiler) yalniz BLE pil kaynagi olmayan cihazlar icin ve ~2 dk'da bir.
                if round % 40 == 0 { await self.readSystemBattery() }
                // Guvenlik agi: ~90 sn'de bir hafif durum okumasi (cihaz tusuyla degisen / kacan bildirimler).
                if round % 30 == 29 { self.resyncReady() }
                round += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func refresh() {
        loadPairedDevices()
        pollConnections()
        for id in known.keys where isQcy(id) { reconnect(id) }
        for channel in airPodsChannels.values { channel.reconnectNow() }
        Task { await readSystemBattery() }
    }

    // MARK: IOBluetooth

    private func loadPairedDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        pairedCache = [:]
        for d in paired {
            // Yalnizca ses cihazlari (ana sinif 0x04: Audio/Video).
            guard d.deviceClassMajor == 0x04, let address = d.addressString else { continue }
            let id = Self.normalize(address)
            pairedCache[id] = d
            guard known[id] == nil else { continue }
            let name = d.name ?? "Bluetooth kulaklık"
            let isApple = name.localizedCaseInsensitiveContains("airpods") || name.localizedCaseInsensitiveContains("beats")
            let device = Device(id: id, name: name, profile: isApple ? .apple : .standart, supportsMultipoint: false,
                                appleModelID: isApple ? appleModelIDs[id] : nil)
            known[id] = device
            log("eşleşmiş ses cihazı: \(name) profil=\(device.profile.rawValue)")
            continuation.yield(.kayit(device))
            if Self.isQcyName(name) { attemptConnect(id) }
        }
    }

    private func pollConnections() {
        for (id, d) in pairedCache {
            guard known[id] != nil else { continue }
            let status: ConnectionStatus = d.isConnected() ? .buMac : .degil
            if lastStatus[id] != status {
                log("bağlantı: \(known[id]?.name ?? id) -> \(status.rawValue)")
                lastStatus[id] = status
                continuation.yield(.baglanti(deviceID: id, status))
                if status == .buMac, isQcy(id) { attemptConnect(id) }
                if known[id]?.profile == .apple { updateAirPodsChannel(id, connected: status == .buMac) }
            }
        }
    }

    // MARK: Sistem pil degeri (Katman A, standart)

    private func readSystemBattery() async {
        // BLE'den pil alan QCY'ler ve bagli olmayanlar atlanir; aday yoksa surec hic baslatilmaz.
        let ids = Set(known.keys.filter { id in
            // GATT'ten pil alinan ya da kanali hazir QCY'ler atlanir; kanal acilamiyorsa sistem pili devreye girer.
            lastStatus[id] == .buMac && !(isQcy(id) && (gattBattery.contains(id) || (qcyLink[id] == .hazir && qcyPeripherals[id] != nil)))
        })
        guard !ids.isEmpty else { return }
        let result = await Task.detached { Self.systemProfilerBatteries(ids: ids) }.value
        log("sistem pil okuması: \(result.count) cihaz")
        for (id, reading) in result {
            log("pil \(known[id]?.name ?? id): sol=\(reading.left.map(String.init) ?? "--") sağ=\(reading.right.map(String.init) ?? "--") kutu=\(reading.caseLevel.map(String.init) ?? "--") genel=\(reading.overall.map(String.init) ?? "--")")
            batteryCache.set(reading, for: id)
            continuation.yield(.pil(deviceID: id, reading))
        }
    }

    /// `system_profiler -json SPBluetoothDataType`: bagli cihazlarin pil alanlari ("%100" ya da "80%").
    nonisolated private static func systemProfilerBatteries(ids: Set<String>) -> [String: BatteryReading] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = section["device_connected"] as? [[String: [String: Any]]] else { return [:] }
        func pct(_ v: Any?) -> Int? {
            guard let s = v as? String else { return nil }
            let digits = s.filter(\.isNumber)
            return Int(digits).map { min(max($0, 0), 100) }
        }
        var out: [String: BatteryReading] = [:]
        let now = Date()
        for entry in connected {
            for (_, props) in entry {
                guard let address = props["device_address"] as? String else { continue }
                let id = normalize(address)
                guard ids.contains(id) else { continue }
                let l = pct(props["device_batteryLevelLeft"]), r = pct(props["device_batteryLevelRight"])
                let c = pct(props["device_batteryLevelCase"]), main = pct(props["device_batteryLevelMain"])
                guard l != nil || r != nil || c != nil || main != nil else { continue }
                out[id] = BatteryReading(left: l, right: r, caseLevel: c, overall: (l == nil && r == nil) ? main : nil,
                                         source: .standart, timestamp: now)
            }
        }
        return out
    }

    nonisolated static func normalize(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    // MARK: Reklam esleme

    /// Apple reklamlari adres tasimaz: tek Apple profilli kayitli cihaz varsa ona eslenir.
    private func appleDeviceID() -> String? {
        let apples = known.values.filter { $0.profile == .apple }
        return apples.count == 1 ? apples.first?.id : nil
    }

    nonisolated static func isQcyName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("qcy") || name.localizedCaseInsensitiveContains("melobuds")
    }

    func isQcy(_ deviceID: String) -> Bool {
        qcyPeripherals[deviceID] != nil || (known[deviceID].map { Self.isQcyName($0.name) } ?? false)
    }

    func supportsListeningControl(_ deviceID: String) -> Bool { qcyPeripherals[deviceID] != nil }

    // MARK: QCY kontrol kanali (A001)

    private func setLink(_ id: String, _ status: QcyLinkStatus) {
        guard qcyLink[id] != status else { return }
        qcyLink[id] = status
        log("QCY kanal durumu: \(status)")
        onQcyLink?(id, status)
        let owned = status == .hazir && !qcyRemote.contains(id)
        if (qcyLocalOwned[id] ?? false) != owned {
            qcyLocalOwned[id] = owned
            onLocalOwner?(id, owned)
        }
        scanTick() // tarama talebi degisti (kanal hazir -> tarama kapanir; kapali -> pencereler acilir)
    }

    // MARK: Yazma sirasi (tek kapi)

    private func enqueue(_ id: String, _ item: QcyWriteItem) {
        var q = writeQueues[id] ?? QcyWriteQueue(minInterval: Self.writeInterval)
        q.enqueue(item)
        writeQueues[id] = q
        startPump(id)
    }

    private func resetQueue(_ id: String) {
        writeQueues[id] = nil
        pumps[id]?.cancel()
        pumps[id] = nil
    }

    private func startPump(_ id: String) {
        guard pumps[id] == nil else { return }
        pumps[id] = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard var q = self.writeQueues[id] else { self.pumps[id] = nil; return }
                let next = q.next(now: Date())
                self.writeQueues[id] = q
                switch next {
                case .empty:
                    self.pumps[id] = nil
                    return
                case .wait(let seconds):
                    try? await Task.sleep(for: .seconds(seconds))
                case .write(let item):
                    await self.perform(item, for: id)
                }
            }
        }
    }

    /// Sirada gelen istegi uygun yola (yerel GATT ya da telefon) verir.
    private func perform(_ item: QcyWriteItem, for id: String) async {
        if qcyRemote.contains(id) {
            switch item.target {
            case .command: _ = relayWrite?(id, item.bytes, nil)
            case .keyMap: _ = relayWrite?(id, item.bytes, "000d")
            case .legacyEq: _ = relayWrite?(id, item.bytes, "000b")
            case .keyMapRead, .batteryRead: break // yalniz yerel GATT okumasi
            }
            return
        }
        guard let p = qcyPeripherals[id] else { return }
        switch item.target {
        case .command: if let c = qcyCommand[id] { await writeQcy(item.bytes, p, c) }
        case .keyMap: if let c = qcyKeys[id] { await writeQcy(item.bytes, p, c) }
        case .legacyEq: if let c = qcyLegacyEq[id] { await writeQcy(item.bytes, p, c) }
        case .keyMapRead: if let c = qcyKeys[id] { p.readValue(for: c) }
        case .batteryRead: if let c = qcyBattery[id] { p.readValue(for: c) }
        }
    }

    // MARK: AirPods / Beats (AAP)

    private static func loadAppleModelIDs() -> [String: UInt16] {
        guard let raw = UserDefaults.standard.dictionary(forKey: appleModelsKey) as? [String: Int] else { return [:] }
        return raw.compactMapValues { UInt16(exactly: $0) }
    }

    /// Model kimligi ogrenildi: Device'a yansit, kalici kaydet, arayuze bildir; kanal modelsiz acildiysa yeniden kur.
    private func setAppleModel(_ id: String, _ modelID: UInt16) {
        guard appleModelIDs[id] != modelID else { return }
        appleModelIDs[id] = modelID
        UserDefaults.standard.set(appleModelIDs.mapValues(Int.init), forKey: Self.appleModelsKey)
        if var d = known[id] { d.appleModelID = modelID; known[id] = d }
        onAppleModel?(id, modelID)
        if let channel = airPodsChannels[id], channel.session.model == nil {
            let connected = lastStatus[id] == .buMac
            channel.stop()
            airPodsChannels[id] = nil
            updateAirPodsChannel(id, connected: connected)
        }
    }

    private func updateAirPodsChannel(_ id: String, connected: Bool) {
        if !connected {
            guard let channel = airPodsChannels.removeValue(forKey: id) else { return }
            channel.stop()
            return
        }
        guard airPodsChannels[id] == nil else { return }
        let channel = AirPodsChannel(deviceID: id, model: appleModelIDs[id].flatMap(AppleModelCatalog.model(forID:)))
        channel.log = { [weak self] in self?.log("[\(id)] \($0)") }
        channel.onModel = { [weak self] model in self?.setAppleModel(id, model.id) }
        channel.onState = { [weak self] state in self?.airPodsChanged(id, state) }
        airPodsChannels[id] = channel
        channel.start()
    }

    private func airPodsChanged(_ id: String, _ state: AirPodsDeviceState?) {
        airPodsStates[id] = state
        onAirPods?(id, state)
        if let reading = state?.batteryReading(at: Date()) {
            batteryCache.set(reading, for: id)
            continuation.yield(.pil(deviceID: id, reading))
        }
    }

    func sendAirPods(_ command: AirPodsCommand, for id: String) -> Bool {
        airPodsChannels[id]?.send(command) ?? false
    }

    // MARK: Pencereli tarama

    private func scanProfile() -> ScanProfile {
        let qcyIDs = known.keys.filter { isQcy($0) }
        return ScanProfile.resolve(
            qcyNeedsAdvert: qcyIDs.contains { qcyLink[$0] != .hazir },
            qcyReadyWithoutGattBattery: qcyIDs.contains { qcyLink[$0] == .hazir && !qcyRemote.contains($0) && !gattBattery.contains($0) },
            appleKnown: known.values.contains { $0.profile == .apple && airPodsChannels[$0.id]?.isReady != true })
    }

    private func startScanLoop() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.scanTick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func scanTick() {
        guard let central, central.state == .poweredOn, permission == .verildi else { return }
        switch scanScheduler.tick(now: Date(), profile: scanProfile()) {
        case .none: break
        case .start(let duplicates):
            log("tarama penceresi acik (tekrarli=\(duplicates))")
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: duplicates])
        case .stop:
            log("tarama penceresi kapali")
            central.stopScan()
        }
    }

    /// "Yenile" / "Tekrar dene": geri cekilmeyi sifirlar ve hemen dener.
    func reconnect(_ deviceID: String) {
        qcyBackoff[deviceID]?.reset()
        qcyNextAttempt[deviceID] = nil
        attemptConnect(deviceID, force: true)
    }

    /// Telefon kanal sahibi olunca GATT denemesi birakilir (cakisma / dongu olmasin); sahiplik bitince normal denenir.
    func setRemoteOwner(_ id: String, _ remote: Bool) {
        if remote {
            guard !qcyRemote.contains(id), qcyLocalOwned[id] != true else { return }
            qcyRemote.insert(id)
            qcyRetry[id]?.cancel(); qcyRetry[id] = nil
            qcyTimeout[id]?.cancel(); qcyTimeout[id] = nil
            qcyConnecting.remove(id)
            if let p = qcyPeripherals[id] { central?.cancelPeripheralConnection(p) }
            qcyCommand[id] = nil
            qcyKeys[id] = nil
            qcyLegacyEq[id] = nil
            qcyBattery[id] = nil
            qcyReadySince[id] = nil
            resetQueue(id)
            setLink(id, .hazir)
            requestRemoteReads(id)
        } else {
            guard qcyRemote.remove(id) != nil else { return }
            qcyYielded.remove(id)
            setLink(id, .kapali)
            reconnect(id)
        }
    }

    /// Mac GATT'i birakir (telefona devir): baglanti kapanir, `takeOver` / telefon sahip olana dek denenmez.
    func yieldChannel(_ id: String) {
        guard !qcyRemote.contains(id) else { return }
        qcyYielded.insert(id)
        qcyRetry[id]?.cancel(); qcyRetry[id] = nil
        qcyTimeout[id]?.cancel(); qcyTimeout[id] = nil
        qcyConnecting.remove(id)
        if let p = qcyPeripherals[id] { central?.cancelPeripheralConnection(p) }
        qcyCommand[id] = nil
        qcyKeys[id] = nil
        qcyLegacyEq[id] = nil
        qcyBattery[id] = nil
        gattBattery.remove(id)
        qcyReadySince[id] = nil
        resetQueue(id)
        setLink(id, .kapali)
    }

    /// Devir bitti / zaman asimi: Mac yeniden dogrudan baglanabilir.
    func clearYield(_ id: String) {
        guard qcyYielded.remove(id) != nil, !qcyRemote.contains(id) else { return }
        reconnect(id)
    }

    var ownedChannelIDs: [String] { qcyLink.keys.filter { ownsChannel($0) } }

    func isRemoteControlled(_ id: String) -> Bool { qcyRemote.contains(id) }

    /// Yerel kanal acik mi (sahip bildirimi icin).
    func ownsChannel(_ id: String) -> Bool { qcyLink[id] == .hazir && qcyCommand[id] != nil && !qcyRemote.contains(id) }

    /// Telefonun ctl.write istegi. `kar` yok/"1001": FF cerceveli, uzunlugu tutarli paket komut ozelligine;
    /// "000d": 20 baytlik tus esleme; "000b": eski EQ (11 bayt).
    @discardableResult
    func writeRelayed(_ id: String, _ bytes: [UInt8], kar: String? = nil) -> Bool {
        guard qcyPeripherals[id] != nil, !qcyRemote.contains(id) else { return false }
        switch kar?.lowercased() ?? "1001" {
        case "1001":
            guard bytes.count >= 4, bytes[0] == 0xFF, Int(bytes[1]) + 2 == bytes.count else { log("ctl.write reddedildi: çerçeve geçersiz"); return false }
            guard qcyCommand[id] != nil else { return false }
            enqueue(id, .make(target: .command, bytes: bytes, notBefore: Date()))
        case "000d":
            guard bytes.count == 20 else { log("ctl.write 000D reddedildi: uzunluk geçersiz"); return false }
            guard qcyKeys[id] != nil else { return false }
            enqueue(id, .make(target: .keyMap, bytes: bytes, notBefore: Date()))
        case "000b":
            guard bytes.count == 11 else { log("ctl.write 000B reddedildi: uzunluk geçersiz"); return false }
            guard qcyLegacyEq[id] != nil else { return false }
            enqueue(id, .make(target: .legacyEq, bytes: bytes, notBefore: Date()))
        default:
            log("ctl.write reddedildi: bilinmeyen karakteristik")
            return false
        }
        return true
    }

    /// Telefondan gelen ctl.notify: yerel gelmis gibi cozucu hattina verilir.
    func ingestRemote(_ id: String, kind: String, bytes: [UInt8]) {
        guard qcyRemote.contains(id) else { return }
        switch kind {
        case "yanit":
            applyQcyResponse(id, bytes)
        case "reklam":
            guard let ad = QcyAdvertisement.parse(manufacturerData: bytes) else { return }
            let reading = ad.reading(at: Date())
            batteryCache.set(reading, for: id)
            continuation.yield(.pil(deviceID: id, reading))
        default:
            break
        }
    }

    private func requestRemoteReads(_ id: String) { requestQcyReads(id) }

    private func attemptConnect(_ id: String, force: Bool = false) {
        guard !qcyRemote.contains(id), !qcyYielded.contains(id) else { return }
        guard let central, central.state == .poweredOn else { return }
        if qcyLink[id] == .hazir, qcyCommand[id] != nil {
            if force { requestQcyReads(id) }
            return
        }
        guard !qcyConnecting.contains(id) else { return }
        if !force, let next = qcyNextAttempt[id], Date() < next { return }
        // Ne bagli ne reklam gormus: sonsuz denemeye gerek yok; baglanti ya da reklam gelince yeniden baslar.
        guard lastStatus[id] == .buMac || qcyPeripherals[id] != nil else { setLink(id, .kapali); return }
        if qcyPeripherals[id] == nil { restoreQcyPeripheral(id) }
        guard let p = qcyPeripherals[id] else {
            log("QCY kontrol cihazı bulunamadı (reklam yok, kayıtlı kimlik yok)")
            qcyFail(id)
            return
        }
        qcyRetry[id]?.cancel()
        qcyRetry[id] = nil
        qcyConnecting.insert(id)
        setLink(id, .baglaniyor)
        p.delegate = self
        log("QCY GATT bağlanıyor (deneme \((qcyBackoff[id]?.failures ?? 0) + 1))")
        central.connect(p)
        nonisolated(unsafe) let peripheral = p
        qcyTimeout[id]?.cancel()
        qcyTimeout[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.connectTimeout))
            guard !Task.isCancelled, let self, self.qcyConnecting.contains(id) else { return }
            self.log("QCY GATT bağlantı zaman aşımı (\(Int(Self.connectTimeout)) sn): kulaklık başka bir merkezde olabilir")
            self.central?.cancelPeripheralConnection(peripheral)
            self.qcyFail(id)
        }
    }

    /// Kayitli BLE kimligiyle (onceki basarili baglanti) cihazi yeniden bulur.
    private func restoreQcyPeripheral(_ id: String) {
        guard let central,
              let stored = UserDefaults.standard.dictionary(forKey: Self.identifiersKey) as? [String: String],
              let text = stored[id], let uuid = UUID(uuidString: text),
              let p = central.retrievePeripherals(withIdentifiers: [uuid]).first else { return }
        qcyPeripherals[id] = p
        log("QCY kontrol cihazı kayıtlı kimlikle bulundu")
    }

    private func storeIdentifier(_ id: String, _ p: CBPeripheral) {
        var stored = (UserDefaults.standard.dictionary(forKey: Self.identifiersKey) as? [String: String]) ?? [:]
        stored[id] = p.identifier.uuidString
        UserDefaults.standard.set(stored, forKey: Self.identifiersKey)
    }

    /// Baglanti basarisiz / koptu: kanal kapali, geri cekilmeli yeniden deneme.
    private func qcyFail(_ id: String) {
        guard !qcyRemote.contains(id) else { return }
        qcyConnecting.remove(id)
        qcyTimeout[id]?.cancel()
        qcyTimeout[id] = nil
        qcyCommand[id] = nil
        qcyKeys[id] = nil
        qcyLegacyEq[id] = nil
        qcyBattery[id] = nil
        gattBattery.remove(id)
        resetQueue(id)
        // Kopunca durum eskimis olur: "bilinmiyor"a don, yeniden baglaninca yeniden okunur.
        if qcyStates[id] != nil { qcyStates[id] = nil; onQcyState?(id, QcyDeviceState()) }
        setLink(id, .kapali)
        guard qcyRetry[id] == nil else { return }
        var backoff = qcyBackoff[id] ?? QcyReconnectBackoff()
        let delay = backoff.failed(now: Date(), readySince: qcyReadySince[id], jitter: Double.random(in: 0...0.2))
        qcyBackoff[id] = backoff
        qcyReadySince[id] = nil
        qcyNextAttempt[id] = Date().addingTimeInterval(delay)
        log("QCY yeniden deneme \(Int(delay)) sn sonra")
        qcyRetry[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.qcyRetry[id] = nil
            self.attemptConnect(id)
        }
    }

    /// Tek GATT yazmasi. Yanitsiz yazmada CoreBluetooth'un gonderme hazirligi (`canSendWriteWithoutResponse`) beklenir;
    /// paket tek seferde sigmiyorsa (ozel EQ 77 bayt) kesilmesin diye yanitli yazilir.
    private func writeQcy(_ packet: [UInt8], _ p: CBPeripheral, _ c: CBCharacteristic) async {
        let fits = packet.count <= p.maximumWriteValueLength(for: .withoutResponse)
        let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) && fits ? .withoutResponse : .withResponse
        if type == .withoutResponse {
            for _ in 0..<40 where !p.canSendWriteWithoutResponse { try? await Task.sleep(for: .milliseconds(25)) }
        }
        p.writeValue(Data(packet), for: c, type: type)
    }

    /// Komutu yazma sirasina koyar (yanit beklenmez), sonra ayni opcode'un geri okumasini geciktirerek siraya koyar.
    /// Donus: kanal acik ve istek siraya alindi mi.
    func send(_ command: QcyCommand, for deviceID: String) async -> Bool {
        if qcyRemote.contains(deviceID) {
            guard relayReady?(deviceID) == true,
                  let packet = command.packet(state: qcyStates[deviceID] ?? QcyDeviceState()) else { return false }
            log("QCY telefon üzerinden yazılıyor: \(command)")
            enqueue(deviceID, .make(target: command.writesKeyMap ? .keyMap : .command, bytes: packet, notBefore: Date()))
            if !command.writesKeyMap {
                enqueue(deviceID, .make(target: .command, bytes: QcyPacket.request(opcode: command.readbackOpcode),
                                        notBefore: Date().addingTimeInterval(Self.readBackDelay)))
            }
            return true
        }
        guard qcyPeripherals[deviceID] != nil else { return false }
        if qcyCommand[deviceID] == nil {
            attemptConnect(deviceID, force: true)
            for _ in 0..<40 where qcyCommand[deviceID] == nil { try? await Task.sleep(for: .milliseconds(200)) }
        }
        guard qcyCommand[deviceID] != nil else { log("QCY komut kanalı açılamadı"); return false }
        guard let packet = command.packet(state: qcyStates[deviceID] ?? QcyDeviceState()) else {
            log("QCY komutu yazılmadı (durum okunmadı): \(command)")
            return false
        }
        let readAt = Date().addingTimeInterval(Self.readBackDelay)
        if command.writesKeyMap {
            guard qcyKeys[deviceID] != nil else { log("QCY 000D yok: tuş eşlemesi yazılamadı"); return false }
            enqueue(deviceID, .make(target: .keyMap, bytes: packet, notBefore: Date()))
            enqueue(deviceID, .make(target: .keyMapRead, bytes: [], notBefore: readAt))
        } else {
            enqueue(deviceID, .make(target: .command, bytes: packet, notBefore: Date()))
            // Cihazin gercek durumunu okuyup arayuze yansit.
            enqueue(deviceID, .make(target: .command, bytes: QcyPacket.request(opcode: command.readbackOpcode), notBefore: readAt))
        }
        log("QCY sıraya alındı: \(command)")
        return true
    }

    /// Ilk okumalar: ses modu (0x17), kulak algilama (0x2C), cift cihaz (0x24), oyun, kulak, EQ, tus eslemesi, pil.
    /// Hepsi yazma sirasindan gecer (araliklari ve birlesme sirada); `light`: yalniz hafif durum okumalari.
    private func requestQcyReads(_ id: String, light: Bool = false) {
        let now = Date()
        var opcodes = [QcyNoise.opcode, QcyWearingDetection.opcode, QcyGameMode.opcode, QcyEarDetection.opcode]
        if !light { opcodes += [QcyCommand.multipointOpcode, QcyEqPreset.opcode] }
        for opcode in opcodes {
            enqueue(id, .make(target: .command, bytes: QcyPacket.request(opcode: opcode), notBefore: now))
        }
        guard !qcyRemote.contains(id) else { return }
        if !light, qcyKeys[id] != nil { enqueue(id, .make(target: .keyMapRead, bytes: [], notBefore: now)) }
        if qcyBattery[id] != nil { enqueue(id, .make(target: .batteryRead, bytes: [], notBefore: now)) }
    }

    /// ~90 sn'de bir: hazir kanallarda hafif durum okumasi.
    private func resyncReady() {
        for (id, status) in qcyLink where status == .hazir { requestQcyReads(id, light: true) }
    }

    /// Yanit gelmezse (en cok 3 kez) okumalari tekrarlar.
    private func watchFirstReads(_ id: String) {
        Task { [weak self] in
            for _ in 0..<3 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.qcyCommand[id] != nil else { return }
                if self.qcyStates[id]?.mode != nil { return }
                self.log("QCY ilk okuma yanıtı yok, tekrar isteniyor")
                self.requestQcyReads(id)
            }
        }
    }

    fileprivate func handleQcy(_ ad: QcyAdvertisement, peripheral: CBPeripheral, rssi: Int, rawAd: [UInt8]) {
        guard let address = ad.controlAddress else { return }
        let id = Self.normalize(address)
        guard known[id] != nil else { log("QCY reklam (kayitsiz) \(id) rssi=\(rssi)"); return }
        let reading = ad.reading(at: Date())
        log("QCY reklam \(id) rssi=\(rssi) sol=\(ad.left.map(String.init) ?? "--") sağ=\(ad.right.map(String.init) ?? "--") kutu=\(ad.caseLevel.map(String.init) ?? "--")")
        if qcyPeripherals[id] == nil { log("QCY kontrol cihazı bulundu: \(known[id]?.name ?? id)") }
        qcyPeripherals[id] = peripheral
        batteryCache.set(reading, for: id)
        // .reklam hem pili gunceller hem yakinlik kartini besler (RSSI esigi kapida).
        continuation.yield(.reklam(deviceID: id, rssi: rssi, battery: reading))
        if ownsChannel(id), Date().timeIntervalSince(lastAdNotify[id] ?? .distantPast) >= 5 {
            lastAdNotify[id] = Date()
            onQcyNotify?(id, "reklam", rawAd)
        }
        // Reklam yeniden gorulunce (geri cekilme suresi dolduysa) GATT'e baglan.
        attemptConnect(id)
    }

    fileprivate func qcyID(for peripheral: CBPeripheral) -> String? {
        qcyPeripherals.first { $0.value.identifier == peripheral.identifier }?.key
    }

    fileprivate func qcyConnected(_ p: CBPeripheral) {
        log("QCY GATT bağlandı, servis aranıyor")
        p.delegate = self
        p.discoverServices([CBUUID(string: QcyGatt.service)])
    }

    fileprivate func qcyConnectFailed(_ p: CBPeripheral, error: Error?) {
        guard let id = qcyID(for: p) else { return }
        log("QCY GATT bağlantı hatası: \(error?.localizedDescription ?? "bilinmiyor")")
        qcyFail(id)
    }

    fileprivate func qcyServices(_ p: CBPeripheral, error: Error?) {
        if let error {
            log("QCY servis keşfi hatası: \(error.localizedDescription)")
            if let id = qcyID(for: p) { qcyFail(id) }
            return
        }
        let services = p.services ?? []
        log("QCY servisler: \(services.map { $0.uuid.uuidString }.joined(separator: ","))")
        guard let svc = services.first(where: { $0.uuid == CBUUID(string: QcyGatt.service) }) else {
            if let id = qcyID(for: p) { qcyFail(id) }
            return
        }
        p.discoverCharacteristics(nil, for: svc)
    }

    fileprivate func qcyCharacteristics(_ p: CBPeripheral, _ s: CBService) {
        guard let id = qcyID(for: p) else { return }
        for c in s.characteristics ?? [] {
            if c.uuid == CBUUID(string: QcyGatt.command) { qcyCommand[id] = c }
            if c.uuid == CBUUID(string: QcyKeyMap.characteristic) { qcyKeys[id] = c }
            if c.uuid == CBUUID(string: "000B") { qcyLegacyEq[id] = c }
            if c.uuid == CBUUID(string: QcyBatteryCharacteristic.uuid) {
                qcyBattery[id] = c
                if c.properties.contains(.notify) { p.setNotifyValue(true, for: c) }
            }
            if c.uuid == CBUUID(string: QcyGatt.response) { p.setNotifyValue(true, for: c) }
        }
        guard qcyCommand[id] != nil else {
            log("QCY 1001 komut özelliği yok")
            qcyFail(id)
            return
        }
        log("QCY kanal hazır (000D \(qcyKeys[id] != nil ? "var" : "yok"))")
        qcyConnecting.remove(id)
        qcyTimeout[id]?.cancel()
        qcyTimeout[id] = nil
        qcyNextAttempt[id] = nil
        qcyReadySince[id] = Date() // deneme sayaci yalniz kararli (>= 30 sn) baglantidan sonra sifirlanir
        storeIdentifier(id, p)
        setLink(id, .hazir)
        requestQcyReads(id)
        watchFirstReads(id)
    }

    fileprivate func qcyResponse(_ p: CBPeripheral, uuid: CBUUID, _ value: Data?) {
        guard let id = qcyID(for: p), let value else { return }
        if uuid == CBUUID(string: QcyBatteryCharacteristic.uuid) {
            let bytes = [UInt8](value)
            guard let reading = QcyBatteryCharacteristic.parse(bytes, at: Date()) else { return }
            gattBattery.insert(id)
            batteryCache.set(reading, for: id)
            continuation.yield(.pil(deviceID: id, reading))
            if Date().timeIntervalSince(lastAdNotify[id] ?? .distantPast) >= 5,
               let raw = QcyBatteryCharacteristic.syntheticAdvertisement(bytes, controlAddress: id) {
                lastAdNotify[id] = Date()
                onQcyNotify?(id, "reklam", raw)
            }
        } else if uuid == CBUUID(string: QcyKeyMap.characteristic) {
            var state = qcyStates[id] ?? QcyDeviceState()
            log("QCY 000D okundu: \(value.map { String(format: "%02X", $0) }.joined(separator: " "))")
            guard state.apply(keyMapBytes: [UInt8](value)) else { return }
            qcyStates[id] = state
            onQcyState?(id, state)
        } else {
            onQcyNotify?(id, "yanit", [UInt8](value))
            applyQcyResponse(id, [UInt8](value))
        }
    }

    /// 1002 yanit paketini (yerel ya da telefondan) durum cozucusune verir.
    private func applyQcyResponse(_ id: String, _ packet: [UInt8]) {
        var state = qcyStates[id] ?? QcyDeviceState()
        var changed = false
        for block in QcyPacket.parse(packet) {
            if state.apply(opcode: block.opcode, parameters: block.parameters) { changed = true }
            // Kutuya girip cikinca cihaz 0x28 bildirir ve modu gecici degistirip geri alir: guncel modu oku.
            if block.opcode == 0x28 { enqueue(id, .make(target: .command, bytes: QcyPacket.request(opcode: QcyNoise.opcode), notBefore: Date().addingTimeInterval(0.5))) }
        }
        guard changed else { return }
        qcyStates[id] = state
        onQcyState?(id, state)
    }

    fileprivate func qcyDisconnected(_ p: CBPeripheral, error: Error?) {
        guard let id = qcyID(for: p) else { return }
        log("QCY GATT koptu: \(error?.localizedDescription ?? "hatasız")")
        qcyFail(id)
    }

    fileprivate func handleAdvertisement(manufacturerData: Data?, rssi: Int) {
        guard let manufacturerData else { return }
        if manufacturerData.starts(with: [0x4C, 0x00]) { log("Apple reklamı rssi=\(rssi) uzunluk=\(manufacturerData.count)") }
        guard let info = ProximityPairingParser.parse(manufacturerData: [UInt8](manufacturerData)),
              let id = appleDeviceID() else { return }
        log("Proximity Pairing çözüldü: \(info.modelName ?? String(info.model, radix: 16))")
        if info.modelInfo != nil { setAppleModel(id, info.model) }
        // AAP kanali hazirsa pil / durum oradan gelir; reklam yalniz yaklasma karti icin beslenir.
        let battery = airPodsChannels[id]?.isReady == true ? nil : BatteryReading(info: info, at: Date())
        continuation.yield(.reklam(deviceID: id, rssi: rssi, battery: battery))
    }

    private func reloadAfterPowerOn() {
        loadPairedDevices()
        pollConnections()
        Task { await readSystemBattery() }
        // IOBluetooth yigini ilk anda eksik liste verebilir: kisa sure sonra tekrar bakilir.
        Task { [weak self] in
            for seconds in [2.0, 6.0] {
                try? await Task.sleep(for: .seconds(seconds))
                guard let self else { return }
                self.loadPairedDevices()
                self.pollConnections()
            }
        }
    }

    fileprivate func centralStateChanged(_ state: CBManagerState) {
        let current = permission
        log("CBManager durum=\(state.rawValue) izin=\(current.label)")
        if current != lastPermission {
            lastPermission = current
            onPermissionChange?(current)
        }
        if current == .verildi { onPowerOff?(state == .poweredOff) }
        if state == .poweredOn, current == .verildi {
            // Bluetooth sonradan acildi: eslesmis cihaz listesi ve kanallar bastan kurulur (kapaliyken liste bos kalmisti).
            reloadAfterPowerOn()
            // Surekli tarama yok: pencereli zamanlayici (ScanScheduler) taramayi acip kapatir.
            scanScheduler.reset()
            startScanLoop()
            scanTick()
            for id in known.keys where isQcy(id) { attemptConnect(id) }
        } else {
            scanScheduler.reset()
        }
    }
}

extension BluetoothProvider: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated { self.centralStateChanged(state) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let rssi = RSSI.intValue
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated {
            if let data, let qcy = QcyAdvertisement.parse(manufacturerData: [UInt8](data)) {
                self.handleQcy(qcy, peripheral: p, rssi: rssi, rawAd: [UInt8](data))
            } else {
                self.handleAdvertisement(manufacturerData: data, rssi: rssi)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated { self.qcyConnected(p) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let e = error
        MainActor.assumeIsolated { self.qcyConnectFailed(p, error: e) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let e = error
        MainActor.assumeIsolated { self.qcyDisconnected(p, error: e) }
    }
}

extension BluetoothProvider: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let e = error
        MainActor.assumeIsolated { self.qcyServices(p, error: e) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        nonisolated(unsafe) let p = peripheral
        nonisolated(unsafe) let s = service
        MainActor.assumeIsolated { self.qcyCharacteristics(p, s) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        nonisolated(unsafe) let p = peripheral
        let value = characteristic.value
        nonisolated(unsafe) let uuid = characteristic.uuid
        MainActor.assumeIsolated { self.qcyResponse(p, uuid: uuid, value) }
    }
}

/// IOBluetooth ile Classic baglanti. Engelleyici cagrilar arka planda calisir; iptalde hemen doner.
struct IOBluetoothAudioRoute: AudioRoute {
    struct Failure: Error {}

    func connect(deviceID: String) async throws {
        try await run(deviceID) { $0.openConnection() == kIOReturnSuccess }
    }

    func disconnect(deviceID: String) async throws {
        try await run(deviceID) { $0.closeConnection() == kIOReturnSuccess }
    }

    /// Kulakligi CoreAudio varsayilan cikisi yapar; aygit listede gec belirebilir, basarisizsa sessizce doner.
    func makeActiveOutput(deviceID: String) async throws {
        let name = IOBluetoothDevice(addressString: deviceID)?.name ?? ""
        _ = await AudioOutputSwitch.setDefaultWhenAvailable(address: deviceID, name: name)
    }

    private func run(_ id: String, _ work: @escaping @Sendable (IOBluetoothDevice) -> Bool) async throws {
        typealias Cont = CheckedContinuation<Void, Error>
        let box = Mutex<Cont?>(nil)
        @Sendable func takeCont() -> Cont? { box.withLock { c in let v = c; c = nil; return v } }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: Cont) in
                if Task.isCancelled { cont.resume(throwing: CancellationError()); return }
                box.withLock { $0 = cont }
                DispatchQueue.global(qos: .userInitiated).async {
                    let ok = IOBluetoothDevice(addressString: id).map(work) ?? false
                    if let c = takeCont() { ok ? c.resume() : c.resume(throwing: Failure()) }
                }
            }
        } onCancel: {
            takeCont()?.resume(throwing: CancellationError())
        }
    }
}
