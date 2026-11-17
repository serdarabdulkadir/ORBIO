// docs/islevler.md 2.2: ses gecisi durum makinesi ("Buraya bagla" / "Telefona gonder").
import Foundation

/// Mac <-> telefon es kanali (yerel ag). Uygulamalar iptali desteklemelidir.
public protocol PeerChannel: Sendable {
    /// Esleme ve ag var mi? Yoksa gecis yalniz yerel yapilir (2.2 adim 6).
    var isAvailable: Bool { get async }
    /// Karsi tarafa `birak` istegi gonderir; `birakildi` yaniti gelince doner.
    func requestRelease(deviceID: String) async throws
    /// Karsi tarafin kulakliga baglanmasini ister.
    func requestConnect(deviceID: String) async throws
    /// Multipoint: karsi tarafin oynatma sahibi olmasini ister.
    func requestPlaybackOwnership(deviceID: String) async throws
    /// `geri al`: karsi taraf baglantisini geri kurar (en iyi caba, hata firlatmaz).
    func requestUndo(deviceID: String) async
}

/// Bu Mac'in ses baglantisi (Classic Bluetooth). Uygulamalar iptali desteklemelidir.
public protocol AudioRoute: Sendable {
    func connect(deviceID: String) async throws
    func disconnect(deviceID: String) async throws
    /// Multipoint: Mac'in ses cikisini kulakliga cevirir.
    func makeActiveOutput(deviceID: String) async throws
}

public enum TransferPhase: Equatable, Sendable {
    case bosta
    case birakIsteniyor
    /// 1 tabanli deneme numarasi.
    case baglaniyor(attempt: Int)
    case geriAliniyor
}

public enum TransferOutcome: Equatable, Sendable {
    /// Gecis tamam.
    case basarili
    /// Yerel baglandi ama karsi taraf hala sahip olabilir: "Telefondan ayirin" ipucu goster.
    case ipucu
    /// Tekrardan sonra da baglanamadi; karsi tarafa `geri al` gonderildi.
    case baglanamadi
    /// Kullanici/uygulama iptal etti.
    case iptal
    /// Baska bir gecis suruyor (yalniz EkosistemEngine dondurur).
    case mesgul
}

public struct TransferEngine: Sendable {
    public static let releaseTimeout: TimeInterval = 3
    public static let connectTimeout: TimeInterval = 8
    public static let maxAttempts = 2 // ilk deneme + 1 tekrar

    private struct TimedOut: Error {}

    private let peer: any PeerChannel
    private let route: any AudioRoute
    private let clock: any EngineClock
    private let onPhase: @Sendable (TransferPhase) -> Void

    public init(peer: any PeerChannel, route: any AudioRoute, clock: any EngineClock,
                onPhase: @escaping @Sendable (TransferPhase) -> Void = { _ in }) {
        self.peer = peer; self.route = route; self.clock = clock; self.onPhase = onPhase
    }

    /// Sesi `target` tarafina gecirir. Iptal guvenli: iptal edilirse ve karsi tarafa `birak`
    /// gonderilmisse en iyi caba `geri al` gonderilir, sonuc `.iptal` olur.
    public func transfer(deviceID: String, to target: PlaybackHost, multipoint: Bool) async -> TransferOutcome {
        defer { onPhase(.bosta) }
        let outcome: TransferOutcome
        switch (target, multipoint) {
        case (.buMac, true): outcome = await multipointToMac(deviceID)
        case (.telefon, true): outcome = await multipointToPhone(deviceID)
        case (.buMac, false): outcome = await toMac(deviceID)
        case (.telefon, false): outcome = await toPhone(deviceID)
        }
        return outcome
    }

    // MARK: Multipoint kisayolu (2.2 adim 2)

    private func multipointToMac(_ id: String) async -> TransferOutcome {
        do {
            try await withTimeout(Self.connectTimeout) { try await route.connect(deviceID: id) }
            try await route.makeActiveOutput(deviceID: id)
            return .basarili
        } catch is CancellationError { return .iptal } catch { return .baglanamadi }
    }

    private func multipointToPhone(_ id: String) async -> TransferOutcome {
        guard await peer.isAvailable else { return .ipucu }
        do {
            try await withTimeout(Self.connectTimeout) { try await peer.requestPlaybackOwnership(deviceID: id) }
            return .basarili
        } catch is CancellationError { return .iptal } catch { return .baglanamadi }
    }

    // MARK: Tek baglantili akis (adim 3-6)

    private func toMac(_ id: String) async -> TransferOutcome {
        var released = false
        var hint = false
        if await peer.isAvailable {
            onPhase(.birakIsteniyor)
            do {
                try await withTimeout(Self.releaseTimeout) { try await peer.requestRelease(deviceID: id) }
                released = true
            } catch is CancellationError {
                return .iptal
            } catch {
                hint = true // yanit yok: yalniz yerel baglanmayi dene, ipucu goster
            }
        } else {
            hint = true
        }
        switch await connectWithRetry({ try await route.connect(deviceID: id) }) {
        case .success: return hint ? .ipucu : .basarili
        case .cancelled:
            await undo(id, ifReleased: released)
            return .iptal
        case .failure:
            await undo(id, ifReleased: released)
            return .baglanamadi
        }
    }

    private func toPhone(_ id: String) async -> TransferOutcome {
        guard await peer.isAvailable else {
            do { try await route.disconnect(deviceID: id) } catch is CancellationError { return .iptal } catch { return .baglanamadi }
            return .ipucu
        }
        do { try await route.disconnect(deviceID: id) } catch is CancellationError { return .iptal } catch { return .baglanamadi }
        switch await connectWithRetry({ try await peer.requestConnect(deviceID: id) }) {
        case .success: return .basarili
        case .cancelled, .failure:
            let cancelled = Task.isCancelled
            // Geri al: Mac kulakliga yeniden baglanir (en iyi caba).
            onPhase(.geriAliniyor)
            try? await route.connect(deviceID: id)
            return cancelled ? .iptal : .baglanamadi
        }
    }

    private enum Attempt { case success, failure, cancelled }

    private func connectWithRetry(_ op: @escaping @Sendable () async throws -> Void) async -> Attempt {
        for attempt in 1...Self.maxAttempts {
            onPhase(.baglaniyor(attempt: attempt))
            do {
                try await withTimeout(Self.connectTimeout, op)
                return .success
            } catch is CancellationError {
                return .cancelled
            } catch {
                continue
            }
        }
        return .failure
    }

    private func undo(_ id: String, ifReleased released: Bool) async {
        guard released else { return }
        onPhase(.geriAliniyor)
        await peer.requestUndo(deviceID: id)
    }

    /// `operation` ile saat uyumlu zaman asimini yaristirir. Zaman asiminda `TimedOut` firlatir.
    private func withTimeout(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await clock.sleep(for: seconds)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
