// Zaman soyutlamasi: gercek zaman (SystemClock) ve testler / selftest icin elle ilerletilen sahte zaman.
import Foundation
import Synchronization

/// Cekirdegin zaman kaynagi. `sleep` iptal edilince `CancellationError` firlatmalidir.
public protocol EngineClock: Sendable {
    var now: Date { get }
    func sleep(for seconds: TimeInterval) async throws
}

/// Gercek saat.
public struct SystemClock: EngineClock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Elle ilerletilen saat. `advance(by:)` suresi dolan `sleep` cagrilarini uyandirir.
public final class ManualClock: EngineClock {
    private struct Waiter {
        let id: UInt64
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }
    private struct State {
        var now: Date
        var nextID: UInt64 = 0
        var waiters: [Waiter] = []
    }
    private let state: Mutex<State>

    public init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        state = Mutex(State(now: start))
    }

    public var now: Date { state.withLock { $0.now } }

    /// Bekleyen (uyuyan) gorev sayisi; testlerde "zaman asimi kuruldu mu" beklemek icin.
    public var sleeperCount: Int { state.withLock { $0.waiters.count } }

    public func sleep(for seconds: TimeInterval) async throws {
        let id = state.withLock { s -> UInt64 in s.nextID += 1; return s.nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                enum Action { case wait, resume, cancel }
                let action = state.withLock { s -> Action in
                    if Task.isCancelled { return .cancel }
                    let deadline = s.now.addingTimeInterval(seconds)
                    if deadline <= s.now { return .resume }
                    s.waiters.append(Waiter(id: id, deadline: deadline, continuation: cont))
                    return .wait
                }
                switch action {
                case .wait: break
                case .resume: cont.resume()
                case .cancel: cont.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let waiter = state.withLock { s -> Waiter? in
                guard let i = s.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return s.waiters.remove(at: i)
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Saati ilerletir; suresi dolanlari sirayla uyandirir.
    public func advance(by seconds: TimeInterval) {
        let due = state.withLock { s -> [Waiter] in
            s.now = s.now.addingTimeInterval(seconds)
            let ready = s.waiters.filter { $0.deadline <= s.now }.sorted { $0.deadline < $1.deadline }
            s.waiters.removeAll { $0.deadline <= s.now }
            return ready
        }
        for w in due { w.continuation.resume() }
    }
}
