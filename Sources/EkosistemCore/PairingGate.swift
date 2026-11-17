import Foundation
import CryptoKit

// Ilk eslesme kapisi (ISTEGE BAGLI ek guvenlik; aktif kod yoksa pasif): Mac'te "Telefonu esle" ile uretilen tek kullanimlik 6 haneli kod (docs/telefon-kanali.md bolum 6).
// Telefon kodu el sikismada HMAC kaniti olarak yollar (kodun kendisi aga cikmaz). SAS karsilastirmasi (MITM korumasi) ayrica surer.

public enum PairingGateResult: Equatable, Sendable {
    case kabul
    /// Aktif kod var ama telefon kanit yollamadi (telefon kod girip yeniden denemeli; yanlis deneme sayilmaz).
    case gerekli
    /// Kilitlenmis (3 yanlis): kapi kapatilana / yeni kod uretilene dek reddedilir.
    case kilitli
    case yanlis
    /// Yanlis deneme siniri doldu: kod iptal edildi.
    case kilitlendi
}

public struct PairingGateState: Equatable, Sendable {
    public var code: String?
    public var expiresAt: Date?
    public var locked: Bool
}

public final class PairingGate: @unchecked Sendable {
    public static let lifetime: TimeInterval = 300
    public static let maxFailures = 3
    static let proofLabel = Data("btrack-pair-v1".utf8)

    private let lock = NSLock()
    private let clock: any EngineClock
    private var code: String?
    private var expiresAt: Date?
    private var failures = 0
    private var locked = false

    public init(clock: any EngineClock = SystemClock()) { self.clock = clock }

    /// Yeni kod uretir (eskisi gecersiz olur); donen deger ekranda gosterilir.
    @discardableResult
    public func open(code fixed: String? = nil) -> PairingGateState {
        lock.lock(); defer { lock.unlock() }
        let c = fixed ?? String(format: "%06d", Int.random(in: 0...999_999))
        code = c
        expiresAt = clock.now.addingTimeInterval(Self.lifetime)
        failures = 0
        locked = false
        return stateLocked()
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        code = nil; expiresAt = nil; failures = 0; locked = false
    }

    public var state: PairingGateState {
        lock.lock(); defer { lock.unlock() }
        return stateLocked()
    }

    /// Telefonun `kod` kanitini dogrular. Basarida kod tuketilir (tek kullanim).
    public func verify(proof: Data?, phonePublicKey: Data, phoneNonce: Data) -> PairingGateResult {
        lock.lock(); defer { lock.unlock() }
        if locked { return .kilitli }
        // Aktif kod yoksa kapi pasif: onceki davranis (yalniz SAS karsilastirmasi).
        guard let current = code, let exp = expiresAt, clock.now < exp else {
            code = nil; expiresAt = nil
            return .kabul
        }
        guard let proof else { return .gerekli }
        let expected = Self.proof(code: current, phonePublicKey: phonePublicKey, phoneNonce: phoneNonce)
        if proof.count == expected.count, Self.constantTimeEqual(proof, expected) {
            code = nil; expiresAt = nil; failures = 0
            return .kabul
        }
        failures += 1
        if failures >= Self.maxFailures {
            code = nil; expiresAt = nil; locked = true
            return .kilitlendi
        }
        return .yanlis
    }

    /// Telefon tarafiyla ayni kanit: HMAC-SHA256(anahtar = kod UTF-8, mesaj = etiket || pub || nonce).
    public static func proof(code: String, phonePublicKey: Data, phoneNonce: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(
            for: proofLabel + phonePublicKey + phoneNonce, using: SymmetricKey(data: Data(code.utf8)))
        return Data(mac)
    }

    private func stateLocked() -> PairingGateState {
        if let exp = expiresAt, clock.now >= exp { code = nil; expiresAt = nil }
        return PairingGateState(code: code, expiresAt: expiresAt, locked: locked)
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0 && a.count == b.count
    }
}
