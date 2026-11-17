import Foundation
import CryptoKit

// Eslesme/sifreleme cekirdegi. Belirtim: docs/telefon-kanali.md (bolum 4-6).

public enum PeerRole: String, Sendable { case mac, telefon }

public enum PeerCryptoError: Error, Equatable, Sendable {
    case gecersizAnahtar
    case gecersizNonce
    case kisaPaket
    case tekrar              // sayac onceki degerden kucuk/esit
    case kimlikDogrulama     // etiket dogrulanamadi (yanlis anahtar / bozuk veri)
    case sayacTasmasi
}

/// Uzun omurlu P-256 kimligi. Ham ozel anahtar 32 bayttir (Keychain / Android Keystore'da saklanir).
public struct PeerIdentity: Sendable {
    let privateKey: P256.KeyAgreement.PrivateKey

    public init() { privateKey = P256.KeyAgreement.PrivateKey() }

    public init(rawPrivateKey: Data) throws {
        guard let k = try? P256.KeyAgreement.PrivateKey(rawRepresentation: rawPrivateKey) else {
            throw PeerCryptoError.gecersizAnahtar
        }
        privateKey = k
    }

    public var rawPrivateKey: Data { privateKey.rawRepresentation }
    /// X9.63 sikistirilmamis nokta: 0x04 || X(32) || Y(32) = 65 bayt.
    public var publicKey: Data { privateKey.publicKey.x963Representation }
}

public struct PeerSessionKeys: Sendable {
    public let macToPhone: SymmetricKey
    public let phoneToMac: SymmetricKey
    /// 6 haneli eslesme kodu (basinda sifir olabilir).
    public let sas: String
    public let transcriptHash: Data
}

public enum PeerCrypto {
    public static let transcriptTag = Data("BTEKO1".utf8)
    public static let hkdfInfo = Data("btekosistem/v1".utf8)
    public static let nonceLength = 16

    public static func randomNonce() -> Data {
        Data((0..<nonceLength).map { _ in UInt8.random(in: 0...255) })
    }

    /// Anahtar turetme. Iki taraf da ayni (macPub, phonePub, macNonce, phoneNonce) sirasiyla hesaplar.
    public static func deriveKeys(role: PeerRole, identity: PeerIdentity, peerPublicKey: Data,
                                  macNonce: Data, phoneNonce: Data) throws -> PeerSessionKeys {
        guard macNonce.count == nonceLength, phoneNonce.count == nonceLength else { throw PeerCryptoError.gecersizNonce }
        guard peerPublicKey.count == 65,
              let peer = try? P256.KeyAgreement.PublicKey(x963Representation: peerPublicKey),
              let secret = try? identity.privateKey.sharedSecretFromKeyAgreement(with: peer) else {
            throw PeerCryptoError.gecersizAnahtar
        }
        let macPub = role == .mac ? identity.publicKey : peerPublicKey
        let phonePub = role == .mac ? peerPublicKey : identity.publicKey
        let hash = Data(SHA256.hash(data: transcriptTag + macPub + phonePub + macNonce + phoneNonce))
        let okm = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: hash, sharedInfo: hkdfInfo, outputByteCount: 68)
        let bytes = okm.withUnsafeBytes { Data($0) }
        return split(okm: bytes, hash: hash)
    }

    /// 68 baytlik HKDF ciktisini boler: [0,32) mac->telefon, [32,64) telefon->mac, [64,68) SAS.
    static func split(okm: Data, hash: Data) -> PeerSessionKeys {
        let b = [UInt8](okm)
        let n = (UInt32(b[64]) << 24) | (UInt32(b[65]) << 16) | (UInt32(b[66]) << 8) | UInt32(b[67])
        let digits = String(n % 1_000_000)
        return PeerSessionKeys(
            macToPhone: SymmetricKey(data: Data(b[0..<32])),
            phoneToMac: SymmetricKey(data: Data(b[32..<64])),
            sas: String(repeating: "0", count: 6 - digits.count) + digits,
            transcriptHash: hash)
    }

    static func counterBytes(_ c: UInt64) -> Data {
        withUnsafeBytes(of: c.bigEndian) { Data($0) }
    }

    /// Belirli sayacla mühürleme: sayac(8) || sifreli(n) || etiket(16). Nonce = 00000000 || sayac. AAD = sayac(8).
    public static func seal(_ plaintext: Data, key: SymmetricKey, counter: UInt64) throws -> Data {
        let cb = counterBytes(counter)
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 4) + cb)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: cb)
        return cb + box.ciphertext + box.tag
    }

    static func parseCounter(_ packet: Data) throws -> UInt64 {
        guard packet.count >= 8 + 16 else { throw PeerCryptoError.kisaPaket }
        return packet.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    public static func open(_ packet: Data, key: SymmetricKey) throws -> (counter: UInt64, plaintext: Data) {
        let counter = try parseCounter(packet)
        let body = Data(packet.dropFirst(8))
        let cb = counterBytes(counter)
        do {
            let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 4) + cb)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body.dropLast(16), tag: body.suffix(16))
            return (counter, try AES.GCM.open(box, using: key, authenticating: cb))
        } catch {
            throw PeerCryptoError.kimlikDogrulama
        }
    }
}

/// Yonlu sifreleyici: giden sayac 1'den baslar; gelen sayac kesin artan olmalidir.
public struct PeerCipher: Sendable {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sendCounter: UInt64 = 0
    private var lastReceived: UInt64 = 0

    public init(role: PeerRole, keys: PeerSessionKeys) {
        sendKey = role == .mac ? keys.macToPhone : keys.phoneToMac
        receiveKey = role == .mac ? keys.phoneToMac : keys.macToPhone
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        guard sendCounter < UInt64.max else { throw PeerCryptoError.sayacTasmasi }
        let packet = try PeerCrypto.seal(plaintext, key: sendKey, counter: sendCounter + 1)
        sendCounter += 1
        return packet
    }

    public mutating func open(_ packet: Data) throws -> Data {
        let counter = try PeerCrypto.parseCounter(packet)
        guard counter > lastReceived else { throw PeerCryptoError.tekrar }
        let result = try PeerCrypto.open(packet, key: receiveKey)
        lastReceived = result.counter   // yalniz dogrulama basarili olunca ilerler
        return result.plaintext
    }
}
