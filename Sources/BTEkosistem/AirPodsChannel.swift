// AirPods / Beats kontrol kanali: IOBluetooth L2CAP PSM 0x1001 (Apple Accessory Protocol).
// Protokol mantigi (hangi paket ne zaman, gelen paket durumu nasil gunceller) EkosistemCore.AAPSession'da;
// burada yalniz kanal acma / yazma / yeniden deneme var. Tek yazma kuyrugu (QcyWriteQueue), araliklidir.
// BLE taramasi ACMAZ: tarama ScanScheduler'a aittir (cizirti duzeltmesi).
import Foundation
import IOBluetooth
import EkosistemCore

enum AirPodsCommand: Equatable {
    case listeningMode(ListeningMode)
    case conversationalAwareness(Bool)
    case earDetection(Bool)
    case oneBudANC(Bool)
    case adaptiveStrength(UInt8)
}

@MainActor
final class AirPodsChannel: NSObject, IOBluetoothL2CAPChannelDelegate {
    static let psm: BluetoothL2CAPPSM = 0x1001
    private static let openTimeout: TimeInterval = 10
    private static let writeInterval: TimeInterval = 0.2

    let deviceID: String
    /// Durum degisti (nil = kanal yok / durum bilinmiyor).
    var onState: ((AirPodsDeviceState?) -> Void)?
    /// AAP cihaz bilgisinden model cozuldu.
    var onModel: ((AppleModel) -> Void)?
    var log: ((String) -> Void)?

    private(set) var session: AAPSession
    private var channel: IOBluetoothL2CAPChannel?
    private var running = false
    private var opening = false
    private var queue = QcyWriteQueue(minInterval: AirPodsChannel.writeInterval)
    private var pump: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var backoff = QcyReconnectBackoff()
    private var readySince: Date?

    init(deviceID: String, model: AppleModel?) {
        self.deviceID = deviceID
        session = AAPSession(model: model)
        super.init()
    }

    var isReady: Bool { session.phase == .ready }
    var state: AirPodsDeviceState? { isReady ? session.state : nil }

    // MARK: Yasam dongusu

    func start() {
        guard !running else { return }
        running = true
        backoff.reset()
        open()
    }

    func stop() {
        running = false
        retry?.cancel(); retry = nil
        teardown()
        onState?(nil)
    }

    /// Kullanici "Yenile": geri cekilmeyi sifirla, hemen yeniden dene.
    func reconnectNow() {
        guard running else { return }
        backoff.reset()
        retry?.cancel(); retry = nil
        teardown()
        open()
    }

    private func open() {
        guard running, channel == nil, !opening else { return }
        guard let device = IOBluetoothDevice(addressString: deviceID) else { scheduleRetry(); return }
        opening = true
        session = AAPSession(model: session.model)
        var ch: IOBluetoothL2CAPChannel?
        let status = device.openL2CAPChannelAsync(&ch, withPSM: Self.psm, delegate: self)
        guard status == kIOReturnSuccess else {
            log?("AAP kanal acma istegi basarisiz (\(status))")
            opening = false
            scheduleRetry()
            return
        }
        channel = ch
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.openTimeout))
            guard !Task.isCancelled, let self, self.opening else { return }
            self.log?("AAP kanal acma zaman asimi")
            self.failed()
        }
    }

    private func teardown() {
        timeout?.cancel(); timeout = nil
        pump?.cancel(); pump = nil
        queue.clear()
        opening = false
        session.close()
        let ch = channel
        channel = nil
        _ = ch?.close()
    }

    /// Kanal acilamadi / koptu / reddedildi: durum bilinmiyor, ustel geri cekilmeyle yeniden dene.
    private func failed() {
        teardown()
        onState?(nil)
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard running else { return }
        let delay = backoff.failed(now: Date(), readySince: readySince, jitter: Double.random(in: 0...0.2))
        readySince = nil
        log?("AAP yeniden deneme \(Int(delay)) sn sonra")
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.retry = nil
            self.open()
        }
    }

    /// Model sonradan cozuldu (AAP cihaz bilgisi): oturum modeli degistirilemedigi icin kanal bir kez yeniden acilir.
    private func restartWithModel(_ model: AppleModel) {
        teardown()
        onState?(nil)
        session = AAPSession(model: model)
        open()
    }

    // MARK: Yazma kuyrugu

    private func enqueue(_ bytes: [UInt8]) {
        // Kontrol komutlari (kimlik baytina gore) birlesir: art arda ayni ayar yalniz sonuncusu gider.
        let key: String? = (bytes.count > 6 && bytes[4] == 0x09) ? "c:\(bytes[6])" : nil
        queue.enqueue(QcyWriteItem(target: .command, bytes: bytes, key: key, notBefore: Date()))
        startPump()
    }

    private func startPump() {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                switch self.queue.next(now: Date()) {
                case .empty:
                    self.pump = nil
                    return
                case .wait(let seconds):
                    try? await Task.sleep(for: .seconds(seconds))
                case .write(let item):
                    self.write(item.bytes)
                }
            }
        }
    }

    private func write(_ bytes: [UInt8]) {
        guard let channel, session.phase != .closed else { return }
        // Tampon yazma bitene kadar yasamali: writeComplete'te serbest birakilir (refcon).
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
        buffer.initialize(from: bytes, count: bytes.count)
        let status = channel.writeAsync(buffer, length: UInt16(bytes.count), refcon: buffer)
        if status != kIOReturnSuccess {
            buffer.deallocate()
            log?("AAP yazma hatasi (\(status))")
        }
    }

    // MARK: Komutlar (kanal hazir degilse ya da model desteklemiyorsa false)

    func send(_ command: AirPodsCommand) -> Bool {
        let packet: [UInt8]?
        switch command {
        case .listeningMode(let m): packet = session.listeningModeCommand(m)
        case .conversationalAwareness(let on): packet = session.conversationalAwarenessCommand(on)
        case .earDetection(let on): packet = session.earDetectionCommand(on)
        case .oneBudANC(let on): packet = session.oneBudANCCommand(on)
        case .adaptiveStrength(let v): packet = session.adaptiveStrengthCommand(wire: v)
        }
        guard let packet else { return false }
        enqueue(packet)
        return true
    }

    // MARK: IOBluetoothL2CAPChannelDelegate

    nonisolated func l2capChannelOpenComplete(_ l2capChannel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        MainActor.assumeIsolated {
            guard self.opening else { return }
            self.opening = false
            self.timeout?.cancel(); self.timeout = nil
            guard error == kIOReturnSuccess else {
                self.log?("AAP kanal acilamadi (\(error))")
                self.failed()
                return
            }
            self.log?("AAP kanal acik")
            self.readySince = Date()
            for packet in self.session.begin() { self.enqueue(packet) }
        }
    }

    nonisolated func l2capChannelData(_ l2capChannel: IOBluetoothL2CAPChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        MainActor.assumeIsolated { self.received(bytes) }
    }

    nonisolated func l2capChannelWriteComplete(_ l2capChannel: IOBluetoothL2CAPChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        refcon?.deallocate()
    }

    nonisolated func l2capChannelClosed(_ l2capChannel: IOBluetoothL2CAPChannel!) {
        MainActor.assumeIsolated {
            guard self.running, self.channel != nil else { return }
            self.log?("AAP kanal kapandi")
            self.failed()
        }
    }

    private func received(_ bytes: [UInt8]) {
        let before = session.state
        let wasReady = isReady
        let step = session.receive(bytes)
        for packet in step.send { enqueue(packet) }
        if let event = step.events.first {
            switch event {
            case .handshakeRejected, .disconnected:
                log?("AAP kulaklik kanali reddetti / kesti")
                failed()
                return
            case .deviceInfo(let info):
                if session.model == nil, let model = AppleModelCatalog.model(forModelNumber: info.modelNumber) {
                    onModel?(model)
                    restartWithModel(model)
                    return
                }
            default: break
            }
        }
        if session.state != before || (!wasReady && isReady) { onState?(session.state) }
    }
}
