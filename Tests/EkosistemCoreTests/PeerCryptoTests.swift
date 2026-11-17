import Testing
import Foundation
import CryptoKit
@testable import EkosistemCore

private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
private func unhex(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}
private func bytes(_ r: ClosedRange<Int>) -> Data { Data(r.map { UInt8($0) }) }

private let macNonce = Data((0..<16).map { UInt8(0xA0 + $0) })
private let phoneNonce = Data((0..<16).map { UInt8(0xB0 + $0) })

private func vectorIdentities() throws -> (PeerIdentity, PeerIdentity) {
    (try PeerIdentity(rawPrivateKey: bytes(1...32)), try PeerIdentity(rawPrivateKey: bytes(33...64)))
}

/// Android'de elle HMAC ile yazilacak HKDF-SHA256 (RFC 5869).
private func manualHKDF(ikm: Data, salt: Data, info: Data, length: Int) -> Data {
    let prk = Data(HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: salt)))
    var t = Data(), okm = Data(), i: UInt8 = 1
    while okm.count < length {
        t = Data(HMAC<SHA256>.authenticationCode(for: t + info + Data([i]), using: SymmetricKey(data: prk)))
        okm += t; i += 1
    }
    return okm.prefix(length)
}

@Test func hkdfRFC5869Vektoru() {
    let okm = manualHKDF(ikm: Data(repeating: 0x0b, count: 22), salt: bytes(0...12), info: bytes(0xf0...0xf9), length: 42)
    #expect(hex(okm) == "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865")
}

@Test func anahtarTuretmeVektoruVeElleHKDF() throws {
    let (m, p) = try vectorIdentities()
    #expect(hex(m.publicKey) == "04515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354")
    #expect(hex(p.publicKey) == "041f140146bfb1b251f84f4ddbe0d4cdcfd77afd984a9520e35794021f8312bb9eec995a08b1fa7704df3dcc0b50a9665263fb7711f95f9f8a449c5096e47c892b")
    let km = try PeerCrypto.deriveKeys(role: .mac, identity: m, peerPublicKey: p.publicKey, macNonce: macNonce, phoneNonce: phoneNonce)
    let kp = try PeerCrypto.deriveKeys(role: .telefon, identity: p, peerPublicKey: m.publicKey, macNonce: macNonce, phoneNonce: phoneNonce)
    #expect(hex(km.transcriptHash) == "ba69f2c2355561d031c3e7fe8c06b0c274daab2afb207059ab9334abd561879a")
    #expect(hex(km.macToPhone.withUnsafeBytes { Data($0) }) == "3e7994371738fd367f8393c81893a0371df27a71ed52fdd4142ec49917eccef0")
    #expect(hex(km.phoneToMac.withUnsafeBytes { Data($0) }) == "cbe20cf9b684bdb2a428ae219e708ce69a45856684940b59a7a0165e3df6aaf8")
    #expect(km.sas == "538801")
    #expect(kp.sas == km.sas && kp.transcriptHash == km.transcriptHash)
    #expect(kp.macToPhone == km.macToPhone && kp.phoneToMac == km.phoneToMac)
    // Elle HKDF ayni cikti: ECDH x-koordinati 32 bayt.
    let secret = unhex("4fe243908f378aa1c2a69538822e6ed908c3225d8692575507c649901245150a")
    let okm = manualHKDF(ikm: secret, salt: km.transcriptHash, info: Data("btekosistem/v1".utf8), length: 68)
    #expect(okm.prefix(32) == km.macToPhone.withUnsafeBytes { Data($0) })
    #expect(okm[32..<64] == km.phoneToMac.withUnsafeBytes { Data($0) })
    let n = okm[64..<68].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    #expect(String(format: "%06d", n % 1_000_000) == "538801")
}

@Test func aesGcmVektoruVeTur() throws {
    let key = SymmetricKey(data: bytes(0...31))
    let pt = Data(#"{"id":1,"t":"ping"}"#.utf8)
    let packet = try PeerCrypto.seal(pt, key: key, counter: 1)
    #expect(hex(packet) == "00000000000000016ef4d69866ce01322c5a7303ced6539972bd6149d15d86aae12692f305fb8fdc1a15c0")
    let r = try PeerCrypto.open(packet, key: key)
    #expect(r.counter == 1 && r.plaintext == pt)
}

@Test func yanlisAnahtarEtiketVeKisaPaketReddi() throws {
    let key = SymmetricKey(data: bytes(0...31)), other = SymmetricKey(data: bytes(1...32))
    let packet = try PeerCrypto.seal(Data("gizli".utf8), key: key, counter: 5)
    #expect(throws: PeerCryptoError.kimlikDogrulama) { try PeerCrypto.open(packet, key: other) }
    var bad = packet; bad[bad.count - 1] ^= 1
    #expect(throws: PeerCryptoError.kimlikDogrulama) { try PeerCrypto.open(bad, key: key) }
    var badCt = packet; badCt[9] ^= 1
    #expect(throws: PeerCryptoError.kimlikDogrulama) { try PeerCrypto.open(badCt, key: key) }
    var badCounter = packet; badCounter[7] ^= 1   // sayac AAD ve nonce'ta: dogrulama basarisiz
    #expect(throws: PeerCryptoError.kimlikDogrulama) { try PeerCrypto.open(badCounter, key: key) }
    #expect(throws: PeerCryptoError.kisaPaket) { try PeerCrypto.open(packet.prefix(23), key: key) }
}

@Test func sayacliSifreleyiciTekrarReddi() throws {
    let (m, p) = try vectorIdentities()
    let km = try PeerCrypto.deriveKeys(role: .mac, identity: m, peerPublicKey: p.publicKey, macNonce: macNonce, phoneNonce: phoneNonce)
    var mac = PeerCipher(role: .mac, keys: km), phone = PeerCipher(role: .telefon, keys: km)
    let p1 = try mac.seal(Data("bir".utf8)), p2 = try mac.seal(Data("iki".utf8))
    #expect(p1 != p2)
    #expect(try phone.open(p1) == Data("bir".utf8))
    #expect(try phone.open(p2) == Data("iki".utf8))
    #expect(throws: PeerCryptoError.tekrar) { try phone.open(p1) }   // tekrar
    #expect(throws: PeerCryptoError.tekrar) { try phone.open(p2) }
    // Yon ayrimi: mac'in kendi paketi mac'te acilmaz (yansitma saldirisi).
    var mac2 = PeerCipher(role: .mac, keys: km)
    #expect(throws: PeerCryptoError.kimlikDogrulama) { try mac2.open(p1) }
    // Bozuk paket sayaci ilerletmez.
    var phone2 = PeerCipher(role: .telefon, keys: km)
    var bad = p2; bad[bad.count - 1] ^= 1
    #expect(throws: PeerCryptoError.kimlikDogrulama) { try phone2.open(bad) }
    #expect(try phone2.open(p2) == Data("iki".utf8))
}

@Test func gecersizAnahtarVeNonce() throws {
    let (m, _) = try vectorIdentities()
    #expect(throws: PeerCryptoError.gecersizAnahtar) {
        try PeerCrypto.deriveKeys(role: .mac, identity: m, peerPublicKey: Data(repeating: 1, count: 65), macNonce: macNonce, phoneNonce: phoneNonce)
    }
    #expect(throws: PeerCryptoError.gecersizNonce) {
        try PeerCrypto.deriveKeys(role: .mac, identity: m, peerPublicKey: m.publicKey, macNonce: Data(), phoneNonce: phoneNonce)
    }
    #expect(throws: PeerCryptoError.gecersizAnahtar) { try PeerIdentity(rawPrivateKey: Data(count: 32)) }
    #expect(try PeerIdentity(rawPrivateKey: m.rawPrivateKey).publicKey == m.publicKey)
}
