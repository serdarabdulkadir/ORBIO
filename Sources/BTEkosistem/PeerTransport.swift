// Telefon kanali tasiyicilari: ayni PeerFraming / PeerSession bayt akisi iki yoldan gider.
// Wi-Fi: TCP (NWConnection, Mac dinler). Bluetooth: RFCOMM ("ORBIO Peer", telefon sunucu, Mac istemci).
// Oturum kodu (PeerLink / PeerSession) tasiyiciyi bilmez: bayt gonder / al + kapanis.
import Foundation
import Network
import IOBluetooth
import EkosistemCore

@MainActor
protocol PeerTransport: AnyObject {
    var path: PeerPath { get }
    /// Bayt akisi hazir (TCP: baglandi; RFCOMM: kanal acik).
    var onReady: (@MainActor () -> Void)? { get set }
    var onData: (@MainActor (Data) -> Void)? { get set }
    /// Karsi taraf ya da ag kapatti. `close()` ile kendi kapatisimizda cagrilmaz.
    var onClosed: (@MainActor () -> Void)? { get set }
    func start()
    func send(_ data: Data)
    /// Kuyruktaki baytlar gittikten sonra kapatir.
    func close()
}

// MARK: TCP

@MainActor
final class TcpTransport: PeerTransport {
    let path: PeerPath = .wifi
    var onReady: (@MainActor () -> Void)?
    var onData: (@MainActor (Data) -> Void)?
    var onClosed: (@MainActor () -> Void)?
    private let connection: NWConnection
    private var closed = false

    init(connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.state(state) }
        }
        connection.start(queue: .main)
    }

    func send(_ data: Data) {
        guard !closed else { return }
        connection.send(content: data, completion: .contentProcessed({ _ in }))
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        // Kuyruktaki cerceveler (ornegin eslesme red nedeni) gittikten sonra kapat; takilirsa 1 sn sonra zorla.
        let conn = connection
        conn.send(content: nil, contentContext: .finalMessage, isComplete: true,
                  completion: .contentProcessed({ _ in conn.cancel() }))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { conn.cancel() }
    }

    private func state(_ state: NWConnection.State) {
        switch state {
        case .ready:
            onReady?()
            receiveNext()
        case .failed, .cancelled:
            gone()
        default:
            break
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if let data, !data.isEmpty { self.onData?(data) }
                if error != nil || isComplete { self.gone(); return }
                if !self.closed { self.receiveNext() }
            }
        }
    }

    private func gone() {
        guard !closed else { return }
        onClosed?()
    }
}

// MARK: RFCOMM

/// Acik (ya da acilmakta olan) RFCOMM kanali. `open` basariyla biterse bayt akisi hazirdir.
@MainActor
final class RfcommTransport: NSObject, PeerTransport, IOBluetoothRFCOMMChannelDelegate {
    let path: PeerPath = .bluetooth
    var onReady: (@MainActor () -> Void)?
    var onData: (@MainActor (Data) -> Void)?
    var onClosed: (@MainActor () -> Void)?
    /// Kanal acma sonucu (istemci icin).
    var onOpenResult: (@MainActor (Bool) -> Void)?
    private let device: IOBluetoothDevice
    private let channelID: BluetoothRFCOMMChannelID
    private var channel: IOBluetoothRFCOMMChannel?
    private var opened = false
    private var started = false
    private var closed = false
    private var early: [Data] = []

    init(device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID) {
        self.device = device
        self.channelID = channelID
    }

    /// Kanali acar; sonuc `onOpenResult` ile gelir.
    func open() -> Bool {
        var ch: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        guard status == kIOReturnSuccess else { return false }
        channel = ch
        return true
    }

    func start() {
        started = true
        if opened { onReady?() }
        for data in early { onData?(data) }
        early = []
    }

    func send(_ data: Data) {
        guard !closed, opened, let channel else { return }
        let mtu = max(Int(channel.getMTU()), 23)
        var offset = 0
        while offset < data.count {
            let n = min(mtu, data.count - offset)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
            data.copyBytes(to: buffer, from: offset..<(offset + n))
            // Tampon yazma bitene kadar yasamali: writeComplete'te serbest birakilir (refcon).
            if channel.writeAsync(buffer, length: UInt16(n), refcon: buffer) != kIOReturnSuccess {
                buffer.deallocate()
                return
            }
            offset += n
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        onOpenResult = nil
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        MainActor.assumeIsolated {
            guard !self.closed, !self.opened else { return }
            if error == kIOReturnSuccess {
                self.opened = true
                self.onOpenResult?(true)
            } else {
                self.onOpenResult?(false)
            }
        }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        MainActor.assumeIsolated {
            guard !self.closed else { return }
            if self.started { self.onData?(data) } else { self.early.append(data) }
        }
    }

    nonisolated func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        refcon?.deallocate()
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated {
            guard !self.closed else { return }
            if self.opened { self.onClosed?() } else { self.onOpenResult?(false) }
        }
    }
}

/// Telefonun "ORBIO Peer" RFCOMM sunucusunu bulur: eslesmis telefon sinifi cihazlara (ve daha once baglanilan
/// telefona) SDP sorgusu, servis kaydi, kanal numarasi, kanal acma. Surekli sorgu YOK: cagiran geri cekilme uygular.
@MainActor
final class RfcommPeerClient: NSObject {
    static let serviceUUID = "6f2a0b1e-4c1d-4e8a-9b3f-0a7c5e2d9b11"
    private static let lastAddressKey = "telefonRfcommAdresi"
    private static let phoneClass: BluetoothDeviceClassMajor = 0x02   // Phone
    private static let sdpTimeout: TimeInterval = 20
    private static let openTimeout: TimeInterval = 15
    private static let maxCandidates = 3

    /// Kanal acildi: tasiyici hazir, sunucuya verilir.
    var onTransport: (@MainActor (RfcommTransport) -> Void)?
    /// Hicbir aday ulasilamadi.
    var onFailed: (@MainActor () -> Void)?
    private(set) var isBusy = false

    private var queue: [IOBluetoothDevice] = []
    private var current: IOBluetoothDevice?
    private var transport: RfcommTransport?
    private var timeout: Task<Void, Never>?
    private var candidateCache: (at: Date, count: Int)?
    private let verbose = CommandLine.arguments.contains("--verbose")
    private func log(_ text: String) { if verbose { print("[rfcomm] \(text)"); fflush(stdout) } }

    /// Eslesmis telefon adayi var mi (30 sn onbellekli; her tikte IOBluetooth sorgulanmaz).
    var hasCandidates: Bool {
        if let c = candidateCache, Date().timeIntervalSince(c.at) < 30 { return c.count > 0 }
        let n = candidates().count
        candidateCache = (Date(), n)
        return n > 0
    }

    func connect() {
        guard !isBusy else { return }
        queue = candidates()
        guard !queue.isEmpty else { onFailed?(); return }
        isBusy = true
        next()
    }

    func cancel() {
        timeout?.cancel(); timeout = nil
        queue = []
        current = nil
        transport?.close(); transport = nil
        isBusy = false
    }

    // MARK: Ic

    private func candidates() -> [IOBluetoothDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let last = UserDefaults.standard.string(forKey: Self.lastAddressKey)
        var list = paired.filter { $0.deviceClassMajor == Self.phoneClass || $0.addressString == last }
        // Daha once baglanilan telefon basa.
        list.sort { ($0.addressString == last ? 0 : 1) < ($1.addressString == last ? 0 : 1) }
        return Array(list.prefix(Self.maxCandidates))
    }

    private func next() {
        timeout?.cancel(); timeout = nil
        transport = nil
        guard isBusy, !queue.isEmpty else {
            let failed = isBusy
            isBusy = false
            current = nil
            if failed { onFailed?() }
            return
        }
        let device = queue.removeFirst()
        current = device
        log("SDP sorgusu: \(device.name ?? device.addressString ?? "?")")
        guard device.performSDPQuery(self) == kIOReturnSuccess else { next(); return }
        timeout = Task { [weak self, weak device] in
            try? await Task.sleep(for: .seconds(Self.sdpTimeout))
            guard !Task.isCancelled, let self, self.current === device else { return }
            self.log("SDP zaman aşımı")
            self.next()
        }
    }

    private func sdpDone(_ device: IOBluetoothDevice, status: IOReturn) {
        guard isBusy, current === device else { return }
        timeout?.cancel(); timeout = nil
        guard status == kIOReturnSuccess else { log("SDP hata \(status)"); next(); return }
        let uuid = UUID(uuidString: Self.serviceUUID)!
        let sdpUUID: IOBluetoothSDPUUID? = withUnsafeBytes(of: uuid.uuid) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        guard let sdpUUID, let record = device.getServiceRecord(for: sdpUUID) else {
            log("ORBIO Peer servisi yok (telefon uygulaması kapalı olabilir)")
            next()
            return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { next(); return }
        let t = RfcommTransport(device: device, channelID: channelID)
        t.onOpenResult = { [weak self, weak t] ok in
            guard let self, let t, self.transport === t else { return }
            self.timeout?.cancel(); self.timeout = nil
            if ok {
                self.log("RFCOMM kanalı açık (kanal \(channelID))")
                if let address = device.addressString { UserDefaults.standard.set(address, forKey: Self.lastAddressKey) }
                self.transport = nil
                self.queue = []; self.current = nil; self.isBusy = false
                t.onOpenResult = nil
                self.onTransport?(t)
            } else {
                self.log("RFCOMM kanalı açılamadı")
                t.close()
                self.next()
            }
        }
        transport = t
        guard t.open() else { t.close(); next(); return }
        timeout = Task { [weak self, weak t] in
            try? await Task.sleep(for: .seconds(Self.openTimeout))
            guard !Task.isCancelled, let self, let t, self.transport === t else { return }
            self.log("RFCOMM açma zaman aşımı")
            t.close()
            self.next()
        }
    }

    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        nonisolated(unsafe) let d = device
        MainActor.assumeIsolated { if let d { self.sdpDone(d, status: status) } }
    }
}
