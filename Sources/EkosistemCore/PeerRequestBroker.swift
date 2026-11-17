// Mac <-> telefon kanalinin motora bakan yuzu: istek/yanit eslemesi ve PeerChannel uygulamasi. Ag yok.
import Foundation

public enum PeerChannelError: Error, Equatable, Sendable {
    case baglantiYok
    case kapandi
    case desteklenmiyor
    case hata
    case beklenmeyenYanit
    /// Karsi taraf `error` mesaji dondurdu.
    case uzak(kod: String, mesaj: String)
}

/// Sifreli oturum uzerinden istek gonderip ayni `id` ile gelen yaniti bekler.
public protocol PeerTransport: Sendable {
    var isEstablished: Bool { get async }
    func request(_ message: PeerMessage) async throws -> PeerMessage
}

public actor PeerRequestBroker: PeerTransport {
    public typealias Sender = @Sendable (PeerEnvelope) async -> Bool

    private let sender: Sender
    private var connected = false
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<PeerMessage, Error>] = [:]

    public init(sender: @escaping Sender) { self.sender = sender }

    public var isEstablished: Bool { connected }
    public var pendingCount: Int { pending.count }

    /// Oturum kuruldu / koptu. Kopunca bekleyen istekler `kapandi` ile biter.
    public func setConnected(_ value: Bool) {
        connected = value
        if !value { failAll(PeerChannelError.kapandi) }
    }

    public func request(_ message: PeerMessage) async throws -> PeerMessage {
        guard connected else { throw PeerChannelError.baglantiYok }
        let id = nextID
        nextID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<PeerMessage, Error>) in
                if Task.isCancelled { c.resume(throwing: CancellationError()); return }
                pending[id] = c
                Task { [sender] in
                    if await !sender(PeerEnvelope(message, id: id)) { self.fail(id, PeerChannelError.baglantiYok) }
                }
            }
        } onCancel: {
            Task { await self.fail(id, CancellationError()) }
        }
    }

    /// Gelen bir mesaj bekleyen bir istegin yaniti ise onu tamamlar. Yalniz yanit tipleri eslenir
    /// (karsi tarafin kendi istegi ayni `id`yi tasisa da karismaz).
    @discardableResult
    public func handle(_ envelope: PeerEnvelope) -> Bool {
        guard let id = envelope.id, let c = pending[id] else { return false }
        switch envelope.message {
        case .earbudReleaseResult, .earbudConnectResult, .pong:
            pending[id] = nil
            c.resume(returning: envelope.message)
        case .error(let e):
            pending[id] = nil
            c.resume(throwing: PeerChannelError.uzak(kod: e.kod, mesaj: e.mesaj))
        default:
            return false
        }
        return true
    }

    private func fail(_ id: Int, _ error: Error) {
        guard let c = pending.removeValue(forKey: id) else { return }
        c.resume(throwing: error)
    }

    private func failAll(_ error: Error) {
        let all = pending
        pending = [:]
        for (_, c) in all { c.resume(throwing: error) }
    }
}

/// `PeerChannel`in gercek uygulamasi: kulaklik birakma / baglanma istekleri telefona gider.
public struct PeerEarbudChannel: PeerChannel {
    private let transport: any PeerTransport

    public init(transport: any PeerTransport) { self.transport = transport }

    public var isAvailable: Bool { get async { await transport.isEstablished } }

    /// `desteklenmiyor` ve `hata` firlatir; motor bu durumda yerel baglanip "Telefondan ayirin" ipucuna duser.
    public func requestRelease(deviceID: String) async throws {
        let reply = try await transport.request(.earbudRelease(EarbudRelease(cihazAdresi: deviceID)))
        guard case .earbudReleaseResult(let r) = reply else { throw PeerChannelError.beklenmeyenYanit }
        try Self.check(r)
    }

    public func requestConnect(deviceID: String) async throws {
        let reply = try await transport.request(.earbudConnect(EarbudConnect(cihazAdresi: deviceID)))
        guard case .earbudConnectResult(let r) = reply else { throw PeerChannelError.beklenmeyenYanit }
        try Self.check(r)
    }

    /// Sozlesmede ayri bir mesaj yok: telefondan kulakliga baglanmasi istenir (multipoint'te oynatma sahibi olmasi icin en yakin istek).
    public func requestPlaybackOwnership(deviceID: String) async throws {
        try await requestConnect(deviceID: deviceID)
    }

    /// En iyi caba: telefon kulakliga yeniden baglanir; hata yutulur.
    public func requestUndo(deviceID: String) async {
        try? await requestConnect(deviceID: deviceID)
    }

    private static func check(_ r: EarbudResult) throws {
        switch r.sonuc {
        case .tamam: return
        case .desteklenmiyor: throw PeerChannelError.desteklenmiyor
        case .hata: throw PeerChannelError.hata
        }
    }
}
