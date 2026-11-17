// Telefon kanali kaliciligi: Mac kimlik anahtari ve sabitlenen (pin) telefon anahtari Application Support altinda 0600 dosyalarda.
// Kalici kayit dosyada; Anahtar Zinciri yalniz eski kaydi bir kez tasimak icin okunur: ad-hoc yeniden imzada erisim/pin kaybolmasin (scripts/paketle.sh her seferinde yeniden imzalar).
import Foundation
import Security
import os
import EkosistemCore

struct PeerPin: Codable, Equatable {
    var key: Data     // telefonun X9.63 acik anahtari (65 bayt)
    var name: String
}

enum PeerStore {
    private static let files = SecureFileStore.applicationSupport("BTrack/peer")
    private static let identityFile = "mac-kimlik-anahtari.key"
    private static let pinFile = "sabitlenen-telefon.json"
    private static let deviceIDKey = "telefonKanaliCihazKimligi"
    static let enabledKey = "telefonKanaliAcik"

    /// Kalici cihaz kimligi (TXT `id` ve `hello.cihazId`); rastgele UUID.
    static func deviceID() -> String {
        if let s = UserDefaults.standard.string(forKey: deviceIDKey) { return s }
        let s = UUID().uuidString
        UserDefaults.standard.set(s, forKey: deviceIDKey)
        return s
    }

    /// UserDefaults bayragi: pin'li telefon var mi (her yukleme ve kayitta gercek dosya durumuyla esitlenir).
    static let pairedFlagKey = "peerPaired"
    static var pairedFlag: Bool {
        get { UserDefaults.standard.bool(forKey: pairedFlagKey) }
        set { UserDefaults.standard.set(newValue, forKey: pairedFlagKey) }
    }

    /// Okuma sonucu. `reddedildi`: dosya var ama okunamadi (kayit EZILMEZ).
    enum LoadResult {
        case ok(identity: PeerIdentity, persisted: Bool, pin: PeerPin?)
        case reddedildi(OSStatus)
    }

    private struct Cache { var identity: PeerIdentity?; var persisted = true; var pinLoaded = false; var pin: PeerPin? }
    private static let cache = OSAllocatedUnfairLock(initialState: Cache())
    private static let queue = DispatchQueue(label: "com.btekosistem.peerstore", qos: .userInitiated)

    /// Kimlik + pin'i arka plan kuyrugunda okur (ana is parcacigi beklemez).
    static func load() async -> LoadResult {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: loadBlocking()) }
        }
    }

    static func loadBlocking() -> LoadResult {
        let c = cache.withLock { $0 }
        var identity = c.identity
        var persisted = c.persisted
        if identity == nil {
            switch files.read(identityFile) {
            case .data(let raw):
                if let id = try? PeerIdentity(rawPrivateKey: raw) { identity = id; persisted = true }
                else {   // bozuk dosya: yeni uret
                    let id = PeerIdentity()
                    identity = id
                    persisted = files.write(id.rawPrivateKey, to: identityFile)
                }
            case .missing:
                // Eski surum Anahtar Zinciri'nde tutuyordu: bir kez okumayi dene (erisilemezse sessizce gec), dosyaya tasi.
                if let raw = legacyRead("mac-kimlik-anahtari"), let id = try? PeerIdentity(rawPrivateKey: raw) {
                    identity = id
                    persisted = files.write(raw, to: identityFile)
                } else {
                    let id = PeerIdentity()
                    identity = id
                    persisted = files.write(id.rawPrivateKey, to: identityFile)
                }
            case .failed:
                return .reddedildi(-1)
            }
        }
        var pin = c.pin
        if !c.pinLoaded {
            switch files.read(pinFile) {
            case .data(let d): pin = try? JSONDecoder().decode(PeerPin.self, from: d)
            case .missing:
                if let d = legacyRead("sabitlenen-telefon"), let p = try? JSONDecoder().decode(PeerPin.self, from: d) {
                    pin = p
                    _ = files.write(d, to: pinFile)
                } else { pin = nil }
            case .failed: return .reddedildi(-1)
            }
        }
        let (i, p, pn) = (identity!, persisted, pin)
        cache.withLock { $0.identity = i; $0.persisted = p; $0.pinLoaded = true; $0.pin = pn }
        pairedFlag = pn != nil
        return .ok(identity: i, persisted: p, pin: pn)
    }

    /// Arka planda yazar; sonuc async doner. Bayrak yalniz yazma basarili olunca `true` olur.
    static func savePin(_ pin: PeerPin) async -> Bool {
        guard let data = try? JSONEncoder().encode(pin) else { return false }
        cache.withLock { $0.pin = pin; $0.pinLoaded = true }
        let ok = await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: files.write(data, to: pinFile)) }
        }
        pairedFlag = ok
        return ok
    }

    static func clearPin() async {
        cache.withLock { $0.pin = nil; $0.pinLoaded = true }
        pairedFlag = false
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { files.delete(pinFile); legacyDelete("sabitlenen-telefon"); cont.resume() }
        }
    }

    // MARK: Eski Anahtar Zinciri kayitlari (yalniz tek seferlik tasima)

    private static func legacyQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.btekosistem.mac.peer",
         kSecAttrAccount as String: account]
    }

    private static func legacyRead(_ account: String) -> Data? {
        var q = legacyQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    /// Eslesme kaldirilinca eski kayit geri gelmesin diye silinir (erisilemezse sessizce gecilir).
    private static func legacyDelete(_ account: String) {
        SecItemDelete(legacyQuery(account) as CFDictionary)
    }
}
