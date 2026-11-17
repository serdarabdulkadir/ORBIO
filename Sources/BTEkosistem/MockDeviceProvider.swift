// Sahte veri: QCY T13 ANC bagli, ikinci cihaz bagli degil; pil zamanla degisir, kart tetiklenir.
import Foundation
import EkosistemCore

@MainActor
final class MockDeviceProvider: DeviceProvider {
    let events: AsyncStream<DeviceEvent>
    let audioRoute: any AudioRoute = MockAudioRoute()
    let peerChannel: any PeerChannel = MockPeerChannel()
    private(set) var permission: PermissionState = .verildi
    var onPermissionChange: (@MainActor (PermissionState) -> Void)?

    static let mainID = "mock-qcy-t13"
    static let secondID = "mock-redmi-buds"

    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private var task: Task<Void, Never>?
    private var left = 82, right = 80, caseLevel = 18

    init() {
        (events, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
    }

    var onQcyState: (@MainActor (String, QcyDeviceState) -> Void)?
    var onQcyLink: (@MainActor (String, QcyLinkStatus) -> Void)?
    private var qcyState = QcyDeviceState(
        mode: .kapali,
        wearing: QcyWearingDetection(enabled: true, musicAction: 1, ancAction: 1, toneEnabled: nil),
        multipoint: false,
        keys: QcyKeyMap(bytes: [0x01, 0x00, 0x02, 0x00, 0x03, 0x01, 0x04, 0x01, 0x05, 0x04,
                                0x06, 0x03, 0x07, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00]))
    func supportsListeningControl(_ deviceID: String) -> Bool { true }
    func isQcy(_ deviceID: String) -> Bool { deviceID == Self.mainID }
    func reconnect(_ deviceID: String) { onQcyLink?(deviceID, .hazir) }
    func send(_ command: QcyCommand, for deviceID: String) async -> Bool {
        guard command.packet(state: qcyState) != nil else { return false }
        qcyState = qcyState.applying(command)
        onQcyState?(deviceID, qcyState)
        return true
    }

    func start() {
        guard task == nil else { return }
        let id = Self.mainID
        continuation.yield(.kayit(Device(id: id, name: "QCY T13 ANC", profile: .tws, supportsMultipoint: false)))
        continuation.yield(.kayit(Device(id: Self.secondID, name: "Redmi Buds 6", profile: .tws, supportsMultipoint: true)))
        continuation.yield(.baglanti(deviceID: id, .buMac))
        continuation.yield(.baglanti(deviceID: Self.secondID, .degil))
        publishBattery()
        onQcyLink?(id, .hazir)
        onQcyState?(id, qcyState)
        task = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick += 1
                guard let self else { return }
                if tick == 8 || tick % 90 == 0 { self.triggerCard() }
                if tick % 15 == 0 { self.drift() }
            }
        }
    }

    func refresh() { publishBattery() }

    /// Yaklasma karti: ust uste iki guclu reklam paketi.
    private func triggerCard() {
        let b = currentReading()
        for _ in 0..<2 { continuation.yield(.reklam(deviceID: Self.mainID, rssi: -42, battery: b)) }
    }

    private func drift() {
        left = max(left - 1, 0)
        if Int.random(in: 0...1) == 0 { right = max(right - 1, 0) }
        publishBattery()
    }

    private func currentReading() -> BatteryReading {
        BatteryReading(left: left, right: right, caseLevel: caseLevel, source: .markaOzel, timestamp: Date())
    }

    private func publishBattery() {
        continuation.yield(.pil(deviceID: Self.mainID, currentReading()))
    }
}

struct MockAudioRoute: AudioRoute {
    func connect(deviceID: String) async throws { try await Task.sleep(for: .milliseconds(500)) }
    func disconnect(deviceID: String) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func makeActiveOutput(deviceID: String) async throws {}
}

struct MockPeerChannel: PeerChannel {
    var isAvailable: Bool { get async { true } }
    func requestRelease(deviceID: String) async throws { try await Task.sleep(for: .milliseconds(400)) }
    func requestConnect(deviceID: String) async throws { try await Task.sleep(for: .milliseconds(500)) }
    func requestPlaybackOwnership(deviceID: String) async throws { try await Task.sleep(for: .milliseconds(300)) }
    func requestUndo(deviceID: String) async {}
}
