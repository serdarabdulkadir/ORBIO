import Foundation
import Synchronization
@testable import EkosistemCore

let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

func reading(l: Int? = nil, r: Int? = nil, c: Int? = nil, overall: Int? = nil,
             lc: Bool = false, rc: Bool = false, cc: Bool = false,
             source: BatterySource = .markaOzel, time: Date = t0) -> BatteryReading {
    BatteryReading(left: l, right: r, caseLevel: c, overall: overall, leftCharging: lc, rightCharging: rc,
                   caseCharging: cc, source: source, timestamp: time)
}

struct TestError: Error {}

enum Behavior: Sendable { case ok, fail, hang }

/// Cagri kaydi ve senaryolu davranis. Son davranis tekrar eder; yoksa `.ok`.
actor Script {
    private(set) var calls: [String] = []
    private var queues: [String: [Behavior]]

    init(_ queues: [String: [Behavior]] = [:]) { self.queues = queues }

    func perform(_ key: String) async throws {
        calls.append(key)
        var q = queues[key] ?? [.ok]
        let b = q.count > 1 ? q.removeFirst() : (q.first ?? .ok)
        queues[key] = q
        switch b {
        case .ok: return
        case .fail: throw TestError()
        case .hang: try await Task.sleep(for: .seconds(100_000))
        }
    }

    func record(_ key: String) { calls.append(key) }
    func count(_ key: String) -> Int { calls.filter { $0 == key }.count }
}

struct FakePeer: PeerChannel {
    let script: Script
    var available = true
    var isAvailable: Bool { get async { available } }
    func requestRelease(deviceID: String) async throws { try await script.perform("peer.release") }
    func requestConnect(deviceID: String) async throws { try await script.perform("peer.connect") }
    func requestPlaybackOwnership(deviceID: String) async throws { try await script.perform("peer.owner") }
    func requestUndo(deviceID: String) async { await script.record("peer.undo") }
}

struct FakeRoute: AudioRoute {
    let script: Script
    func connect(deviceID: String) async throws { try await script.perform("route.connect") }
    func disconnect(deviceID: String) async throws { try await script.perform("route.disconnect") }
    func makeActiveOutput(deviceID: String) async throws { try await script.perform("route.active") }
}

/// Saat uyuyanlari kurulana kadar bekler (zaman asimi gorevi baslasin diye).
func waitForSleepers(_ clock: ManualClock, atLeast n: Int = 1) async {
    for _ in 0..<100_000 where clock.sleeperCount < n { await Task.yield() }
}

/// Gorevlerin ilerlemesi icin yield.
func settle() async { for _ in 0..<200 { await Task.yield() } }

final class PhaseLog: Sendable {
    private let store = Mutex<[TransferPhase]>([])
    func add(_ p: TransferPhase) { store.withLock { $0.append(p) } }
    var all: [TransferPhase] { store.withLock { $0 } }
}

/// `#expect` icinde mutating cagri yapabilmek icin sinif kutusu.
final class Box<T> {
    var v: T
    init(_ v: T) { self.v = v }
}
