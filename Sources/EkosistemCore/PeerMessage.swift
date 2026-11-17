import Foundation

// Telefon kanali mesajlari. Tel bicimi: docs/telefon-kanali.md (Kotlin tarafi ile birebir).
// Her mesaj tek bir JSON nesnesidir: {"t":"<tip>","id":n,...alanlar}. `id` istek-yanit eslemesi icindir.

public enum CallStatus: String, Codable, Sendable { case bosta, caliyor, acik, araniyor }
public enum CallDirection: String, Codable, Sendable { case gelen, giden }
public enum CallLogDirection: String, Codable, Sendable { case gelen, giden, cevapsiz }
public enum EarbudLink: String, Codable, Sendable { case telefon, bos }
public enum PeerResult: String, Codable, Sendable { case tamam, desteklenmiyor, hata }

public struct PeerHello: Codable, Equatable, Sendable {
    public var ad: String
    public var surum: String
    public var protokol: Int
    public var cihazId: String
    public var platform: String   // "mac" | "android"
    public init(ad: String, surum: String, protokol: Int = 1, cihazId: String, platform: String) {
        self.ad = ad; self.surum = surum; self.protokol = protokol; self.cihazId = cihazId; self.platform = platform
    }
}

public struct PhoneState: Codable, Equatable, Sendable {
    public var ad: String
    public var model: String
    public var pil: Int
    public var sarj: Bool
    public var sinyal: Int
    public var ag: String   // "wifi" | "mobil" | "yok"
    public init(ad: String, model: String, pil: Int, sarj: Bool, sinyal: Int, ag: String) {
        self.ad = ad; self.model = model; self.pil = pil; self.sarj = sarj; self.sinyal = sinyal; self.ag = ag
    }
}

public struct CallState: Codable, Equatable, Sendable {
    public var durum: CallStatus
    public var yon: CallDirection?
    public var numara: String?
    public var kisiAdi: String?
    public var sureSn: Int?
    public init(durum: CallStatus, yon: CallDirection? = nil, numara: String? = nil,
                kisiAdi: String? = nil, sureSn: Int? = nil) {
        self.durum = durum; self.yon = yon; self.numara = numara; self.kisiAdi = kisiAdi; self.sureSn = sureSn
    }
}

public struct CallDial: Codable, Equatable, Sendable {
    public var numara: String
    public init(numara: String) { self.numara = numara }
}
public struct ContactsSearch: Codable, Equatable, Sendable {
    public var sorgu: String
    public init(sorgu: String) { self.sorgu = sorgu }
}
public struct PeerContact: Codable, Equatable, Sendable {
    public var ad: String
    public var numaralar: [String]
    public init(ad: String, numaralar: [String]) { self.ad = ad; self.numaralar = numaralar }
}
public struct ContactsResult: Codable, Equatable, Sendable {
    public var kisiler: [PeerContact]
    public init(kisiler: [PeerContact]) { self.kisiler = kisiler }
}
public struct CallLogRecent: Codable, Equatable, Sendable {
    public var adet: Int?
    public init(adet: Int? = nil) { self.adet = adet }
}
public struct CallLogEntry: Codable, Equatable, Sendable {
    public var numara: String
    public var kisiAdi: String?
    public var yon: CallLogDirection
    public var zaman: Int      // epoch saniye
    public var sureSn: Int
    public init(numara: String, kisiAdi: String? = nil, yon: CallLogDirection, zaman: Int, sureSn: Int) {
        self.numara = numara; self.kisiAdi = kisiAdi; self.yon = yon; self.zaman = zaman; self.sureSn = sureSn
    }
}
public struct CallLogResult: Codable, Equatable, Sendable {
    public var kayitlar: [CallLogEntry]
    public init(kayitlar: [CallLogEntry]) { self.kayitlar = kayitlar }
}

// MARK: Kisiler ve arama gecmisi senkronu (sayfali, artimli)

public struct ContactNumber: Codable, Equatable, Sendable {
    public var no: String
    /// "cep" | "ev" | "is" | "diger"
    public var tur: String
    public init(no: String, tur: String) { self.no = no; self.tur = tur }
}
public struct ContactRecord: Codable, Equatable, Sendable, Identifiable {
    public var kid: String
    public var ad: String
    public var numaralar: [ContactNumber]
    public var favori: Bool
    public var gruplar: [String]
    /// Kucuk JPEG kucuk resmi, standart base64 (opsiyonel).
    public var foto: String?
    public var id: String { kid }
    public init(kid: String, ad: String, numaralar: [ContactNumber], favori: Bool = false, gruplar: [String] = [], foto: String? = nil) {
        self.kid = kid; self.ad = ad; self.numaralar = numaralar; self.favori = favori; self.gruplar = gruplar; self.foto = foto
    }
}
/// mac->tel: `ofset`inci kisiden baslayan sayfayi iste.
public struct ContactsSync: Codable, Equatable, Sendable {
    public var ofset: Int
    public var adet: Int?
    public init(ofset: Int, adet: Int? = nil) { self.ofset = ofset; self.adet = adet }
}
/// tel->mac: bir sayfa kisi. `son` = bu son sayfa.
public struct ContactsPage: Codable, Equatable, Sendable {
    public var ofset: Int
    public var toplam: Int
    public var son: Bool
    public var kisiler: [ContactRecord]
    public init(ofset: Int, toplam: Int, son: Bool, kisiler: [ContactRecord]) {
        self.ofset = ofset; self.toplam = toplam; self.son = son; self.kisiler = kisiler
    }
}
public struct CallLogSync: Codable, Equatable, Sendable {
    public var ofset: Int
    public var adet: Int?
    public init(ofset: Int, adet: Int? = nil) { self.ofset = ofset; self.adet = adet }
}
public struct CallLogPage: Codable, Equatable, Sendable {
    public var ofset: Int
    public var toplam: Int
    public var son: Bool
    public var kayitlar: [CallLogEntry]
    public init(ofset: Int, toplam: Int, son: Bool, kayitlar: [CallLogEntry]) {
        self.ofset = ofset; self.toplam = toplam; self.son = son; self.kayitlar = kayitlar
    }
}

public struct EarbudState: Codable, Equatable, Sendable {
    public var cihazId: String
    public var ad: String
    public var baglanti: EarbudLink
    public init(cihazId: String, ad: String, baglanti: EarbudLink) {
        self.cihazId = cihazId; self.ad = ad; self.baglanti = baglanti
    }
}
public struct EarbudRelease: Codable, Equatable, Sendable {
    public var cihazAdresi: String
    public init(cihazAdresi: String) { self.cihazAdresi = cihazAdresi }
}
public struct EarbudConnect: Codable, Equatable, Sendable {
    public var cihazAdresi: String
    public init(cihazAdresi: String) { self.cihazAdresi = cihazAdresi }
}
public struct EarbudResult: Codable, Equatable, Sendable {
    public var sonuc: PeerResult
    public var cihazAdresi: String?
    public init(sonuc: PeerResult, cihazAdresi: String? = nil) { self.sonuc = sonuc; self.cihazAdresi = cihazAdresi }
}
/// `ctl.owner` (iki yon): bu taraf kulakligin BLE kontrol kanalini tutuyor mu.
public struct CtlOwner: Codable, Equatable, Sendable {
    public var cihazAdresi: String
    public var sahip: Bool
    public init(cihazAdresi: String, sahip: Bool) { self.cihazAdresi = cihazAdresi; self.sahip = sahip }
}
/// `ctl.write` (sahip olmayan -> sahip): QCY paketinin ham baytlari, kucuk harf hex.
/// `kar` (opsiyonel): hedef karakteristik "1001" (varsayilan) | "000d" tus esleme | "000b" eski EQ; yoksa JSON'a yazilmaz.
public struct CtlWrite: Codable, Equatable, Sendable {
    public var cihazAdresi: String
    public var bayt: String
    public var kar: String?
    public init(cihazAdresi: String, bayt: String, kar: String? = nil) { self.cihazAdresi = cihazAdresi; self.bayt = bayt; self.kar = kar }
}
/// `ctl.notify` (sahip -> diger): `tur` = "yanit" | "reklam"; `bayt` kucuk harf hex.
public struct CtlNotify: Codable, Equatable, Sendable {
    public var cihazAdresi: String
    public var tur: String
    public var bayt: String
    public init(cihazAdresi: String, tur: String, bayt: String) { self.cihazAdresi = cihazAdresi; self.tur = tur; self.bayt = bayt }
}
/// ctl.* bayt alanlari: kucuk harf hex.
public enum CtlHex {
    public static func encode(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    public static func decode(_ text: String) -> [UInt8]? {
        let u = Array(text.utf8)
        guard u.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(u.count / 2)
        func nib(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: c - 48
            case 97...102: c - 87
            case 65...70: c - 55
            default: nil
            }
        }
        var i = 0
        while i < u.count {
            guard let a = nib(u[i]), let b = nib(u[i + 1]) else { return nil }
            out.append(a << 4 | b); i += 2
        }
        return out
    }
}
public struct PermState: Codable, Equatable, Sendable {
    public var cagriYonetimi: Bool
    public var kisiler: Bool
    public var aramaGecmisi: Bool
    /// Varsayilan: hepsi KAPALI.
    public init(cagriYonetimi: Bool = false, kisiler: Bool = false, aramaGecmisi: Bool = false) {
        self.cagriYonetimi = cagriYonetimi; self.kisiler = kisiler; self.aramaGecmisi = aramaGecmisi
    }
}
/// `media.state` (tel->mac): telefondaki medya oturumu. Opsiyonel alan yoksa JSON'a yazilmaz.
public struct MediaState: Codable, Equatable, Sendable {
    public var caliyor: Bool
    /// Aktif medya oturumu var mi.
    public var oturum: Bool
    public var uygulama: String?
    public var baslik: String?
    public var sanatci: String?
    public init(caliyor: Bool, oturum: Bool, uygulama: String? = nil, baslik: String? = nil, sanatci: String? = nil) {
        self.caliyor = caliyor; self.oturum = oturum; self.uygulama = uygulama; self.baslik = baslik; self.sanatci = sanatci
    }
}
/// `media.cmd` (iki yon): komut = "oynat_duraklat" | "oynat" | "duraklat" | "sonraki" | "onceki".
public struct MediaCmd: Codable, Equatable, Sendable {
    public var komut: String
    public init(komut: String) { self.komut = komut }
    public static let oynatDuraklat = "oynat_duraklat", oynat = "oynat", duraklat = "duraklat", sonraki = "sonraki", onceki = "onceki"
}
/// `vol.state` (iki yon): `cihaz` = "mac" | "telefon"; `seviye` 0...100.
public struct VolState: Codable, Equatable, Sendable {
    public var cihaz: String
    public var seviye: Int
    public var sessiz: Bool
    public init(cihaz: String, seviye: Int, sessiz: Bool) {
        self.cihaz = cihaz; self.seviye = min(max(seviye, 0), 100); self.sessiz = sessiz
    }
}
/// `vol.set` (iki yon): `hedef` = "mac" | "telefon"; opsiyonel alan yoksa JSON'a yazilmaz.
public struct VolSet: Codable, Equatable, Sendable {
    public var hedef: String
    public var seviye: Int?
    public var sessiz: Bool?
    public init(hedef: String, seviye: Int? = nil, sessiz: Bool? = nil) {
        self.hedef = hedef; self.seviye = seviye.map { min(max($0, 0), 100) }; self.sessiz = sessiz
    }
}
public struct PeerError: Codable, Equatable, Sendable {
    public var kod: String
    public var mesaj: String
    public init(kod: String, mesaj: String) { self.kod = kod; self.mesaj = mesaj }
}

public enum PeerMessageError: Error, Equatable, Sendable {
    case bilinmeyenTip(String)
    case gecersizJSON
}

public enum PeerMessage: Equatable, Sendable {
    case hello(PeerHello)
    case ping, pong
    case phoneState(PhoneState)
    case callState(CallState)
    case callAnswer, callReject, callHangup
    case callDial(CallDial)
    case contactsSearch(ContactsSearch)
    case contactsResult(ContactsResult)
    case callLogRecent(CallLogRecent)
    case callLogResult(CallLogResult)
    case contactsSync(ContactsSync)
    case contactsPage(ContactsPage)
    case contactsChanged
    case callLogSync(CallLogSync)
    case callLogPage(CallLogPage)
    case callLogChanged
    case earbudState(EarbudState)
    case earbudRelease(EarbudRelease)
    case earbudReleaseResult(EarbudResult)
    case earbudConnect(EarbudConnect)
    case earbudConnectResult(EarbudResult)
    case permState(PermState)
    case ctlOwner(CtlOwner)
    case ctlWrite(CtlWrite)
    case ctlNotify(CtlNotify)
    case mediaState(MediaState)
    case mediaCmd(MediaCmd)
    case volState(VolState)
    case volSet(VolSet)
    case error(PeerError)

    /// Tel uzerindeki `t` degeri.
    public var type: String {
        switch self {
        case .hello: "hello"
        case .ping: "ping"
        case .pong: "pong"
        case .phoneState: "phone.state"
        case .callState: "call.state"
        case .callAnswer: "call.answer"
        case .callReject: "call.reject"
        case .callHangup: "call.hangup"
        case .callDial: "call.dial"
        case .contactsSearch: "contacts.search"
        case .contactsResult: "contacts.result"
        case .callLogRecent: "calllog.recent"
        case .callLogResult: "calllog.result"
        case .contactsSync: "contacts.sync"
        case .contactsPage: "contacts.page"
        case .contactsChanged: "contacts.changed"
        case .callLogSync: "calllog.sync"
        case .callLogPage: "calllog.page"
        case .callLogChanged: "calllog.changed"
        case .earbudState: "earbud.state"
        case .earbudRelease: "earbud.release"
        case .earbudReleaseResult: "earbud.release.result"
        case .earbudConnect: "earbud.connect"
        case .earbudConnectResult: "earbud.connect.result"
        case .permState: "perm.state"
        case .ctlOwner: "ctl.owner"
        case .ctlWrite: "ctl.write"
        case .ctlNotify: "ctl.notify"
        case .mediaState: "media.state"
        case .mediaCmd: "media.cmd"
        case .volState: "vol.state"
        case .volSet: "vol.set"
        case .error: "error"
        }
    }

    func encodePayload(to encoder: Encoder) throws {
        switch self {
        case .ping, .pong, .callAnswer, .callReject, .callHangup, .contactsChanged, .callLogChanged: break
        case .hello(let v): try v.encode(to: encoder)
        case .phoneState(let v): try v.encode(to: encoder)
        case .callState(let v): try v.encode(to: encoder)
        case .callDial(let v): try v.encode(to: encoder)
        case .contactsSearch(let v): try v.encode(to: encoder)
        case .contactsResult(let v): try v.encode(to: encoder)
        case .callLogRecent(let v): try v.encode(to: encoder)
        case .callLogResult(let v): try v.encode(to: encoder)
        case .contactsSync(let v): try v.encode(to: encoder)
        case .contactsPage(let v): try v.encode(to: encoder)
        case .callLogSync(let v): try v.encode(to: encoder)
        case .callLogPage(let v): try v.encode(to: encoder)
        case .earbudState(let v): try v.encode(to: encoder)
        case .earbudRelease(let v): try v.encode(to: encoder)
        case .earbudReleaseResult(let v): try v.encode(to: encoder)
        case .earbudConnect(let v): try v.encode(to: encoder)
        case .earbudConnectResult(let v): try v.encode(to: encoder)
        case .permState(let v): try v.encode(to: encoder)
        case .ctlOwner(let v): try v.encode(to: encoder)
        case .ctlWrite(let v): try v.encode(to: encoder)
        case .ctlNotify(let v): try v.encode(to: encoder)
        case .mediaState(let v): try v.encode(to: encoder)
        case .mediaCmd(let v): try v.encode(to: encoder)
        case .volState(let v): try v.encode(to: encoder)
        case .volSet(let v): try v.encode(to: encoder)
        case .error(let v): try v.encode(to: encoder)
        }
    }

    static func decode(type: String, from d: Decoder) throws -> PeerMessage {
        switch type {
        case "hello": return .hello(try PeerHello(from: d))
        case "ping": return .ping
        case "pong": return .pong
        case "phone.state": return .phoneState(try PhoneState(from: d))
        case "call.state": return .callState(try CallState(from: d))
        case "call.answer": return .callAnswer
        case "call.reject": return .callReject
        case "call.hangup": return .callHangup
        case "call.dial": return .callDial(try CallDial(from: d))
        case "contacts.search": return .contactsSearch(try ContactsSearch(from: d))
        case "contacts.result": return .contactsResult(try ContactsResult(from: d))
        case "calllog.recent": return .callLogRecent(try CallLogRecent(from: d))
        case "calllog.result": return .callLogResult(try CallLogResult(from: d))
        case "contacts.sync": return .contactsSync(try ContactsSync(from: d))
        case "contacts.page": return .contactsPage(try ContactsPage(from: d))
        case "contacts.changed": return .contactsChanged
        case "calllog.sync": return .callLogSync(try CallLogSync(from: d))
        case "calllog.page": return .callLogPage(try CallLogPage(from: d))
        case "calllog.changed": return .callLogChanged
        case "earbud.state": return .earbudState(try EarbudState(from: d))
        case "earbud.release": return .earbudRelease(try EarbudRelease(from: d))
        case "earbud.release.result": return .earbudReleaseResult(try EarbudResult(from: d))
        case "earbud.connect": return .earbudConnect(try EarbudConnect(from: d))
        case "earbud.connect.result": return .earbudConnectResult(try EarbudResult(from: d))
        case "perm.state": return .permState(try PermState(from: d))
        case "ctl.owner": return .ctlOwner(try CtlOwner(from: d))
        case "ctl.write": return .ctlWrite(try CtlWrite(from: d))
        case "ctl.notify": return .ctlNotify(try CtlNotify(from: d))
        case "media.state": return .mediaState(try MediaState(from: d))
        case "media.cmd": return .mediaCmd(try MediaCmd(from: d))
        case "vol.state": return .volState(try VolState(from: d))
        case "vol.set": return .volSet(try VolSet(from: d))
        case "error": return .error(try PeerError(from: d))
        default: throw PeerMessageError.bilinmeyenTip(type)
        }
    }
}

/// `{"t":..., "id":...}` zarfi + mesaj.
public struct PeerEnvelope: Codable, Equatable, Sendable {
    public var id: Int?
    public var message: PeerMessage

    public init(_ message: PeerMessage, id: Int? = nil) { self.message = message; self.id = id }

    private enum Keys: String, CodingKey { case t, id }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let t = try c.decode(String.self, forKey: .t)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        message = try PeerMessage.decode(type: t, from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(message.type, forKey: .t)
        try c.encodeIfPresent(id, forKey: .id)
        try message.encodePayload(to: encoder)
    }
}

public enum PeerCodec {
    public static func encode(_ envelope: PeerEnvelope) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> PeerEnvelope {
        do { return try JSONDecoder().decode(PeerEnvelope.self, from: data) }
        catch let e as PeerMessageError { throw e }
        catch { throw PeerMessageError.gecersizJSON }
    }
}

// MARK: Telefon izinleri

public enum PeerPermission: String, Sendable { case cagriYonetimi, kisiler, aramaGecmisi }

extension PeerMessage {
    /// Telefon tarafinda bu istegi yurutmek icin gereken izin (yoksa nil).
    public var requiredPermission: PeerPermission? {
        switch self {
        case .callAnswer, .callReject, .callHangup, .callDial: .cagriYonetimi
        case .contactsSearch, .contactsSync: .kisiler
        case .callLogRecent, .callLogSync: .aramaGecmisi
        default: nil
        }
    }
}

extension PermState {
    public func allows(_ p: PeerPermission) -> Bool {
        switch p {
        case .cagriYonetimi: cagriYonetimi
        case .kisiler: kisiler
        case .aramaGecmisi: aramaGecmisi
        }
    }

    /// Telefon tarafi kapisi: izin yoksa donecek `error` {kod:"izin_yok"} yaniti; izin varsa nil.
    public func denial(for envelope: PeerEnvelope) -> PeerEnvelope? {
        guard let need = envelope.message.requiredPermission, !allows(need) else { return nil }
        return PeerEnvelope(.error(PeerError(kod: "izin_yok", mesaj: need.rawValue)), id: envelope.id)
    }
}
