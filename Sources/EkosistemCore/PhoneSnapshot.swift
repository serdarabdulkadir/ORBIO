// Telefondan gelen mesajlarin Mac tarafindaki ozeti. Saf deger tipi: ag yok, kolay test edilir.
import Foundation

public enum CallTransition: Equatable, Sendable {
    case yok
    /// Bosta -> gelen arama caliyor.
    case gelenBasladi
    /// Herhangi bir aktif durum -> bosta.
    case bitti
}

public struct PhoneSnapshot: Equatable, Sendable {
    public var hello: PeerHello?
    public var phone: PhoneState?
    public var call = CallState(durum: .bosta)
    /// nil = telefon henuz bildirmedi (arayuz "izin yok" gibi davranir).
    public var perm: PermState?
    public var earbuds: [String: EarbudState] = [:]
    public var contacts: [PeerContact] = []
    /// nil = hic alinmadi.
    public var callLog: [CallLogEntry]?
    /// Telefondaki medya oturumu (baglanti kopunca silinir); nil = bildirilmedi.
    public var media: MediaState?
    /// Telefonun medya sesi (vol.state cihaz:"telefon"); baglanti kopunca silinir.
    public var phoneVolume: VolState?
    public var lastError: PeerError?
    /// Rehber onbellegi (yalniz bellek; baglanti kopunca ve izin kapaninca silinir).
    public var contactBook: [ContactRecord] = []
    public var contactsLoaded = false
    public var contactsLoading = false
    public var contactsTotal: Int?
    public var callLogLoaded = false
    public var callLogLoading = false
    /// Tek sayfada istenen kayit (telefon kendi ust sinirini uygular).
    public static let contactPageSize = 40
    public static let callLogPageSize = 100
    public static let callLogLimit = 300

    public init() {}

    public var isRinging: Bool { call.durum == .caliyor && call.yon == .gelen }
    public var isInCall: Bool { call.durum != .bosta }

    public func allows(_ p: PeerPermission) -> Bool { perm?.allows(p) ?? false }

    /// Gelen mesaji isler; karsi tarafa hemen gonderilecek yanitlari dondurur (ping -> pong).
    @discardableResult
    public mutating func apply(_ envelope: PeerEnvelope) -> [PeerEnvelope] {
        switch envelope.message {
        case .hello(let h): hello = h
        case .ping: return [PeerEnvelope(.pong, id: envelope.id)]
        case .phoneState(let s): phone = s
        case .callState(let c): call = c
        case .permState(let p): return applyPerm(p)
        case .earbudState(let e): earbuds[e.cihazId] = e
        case .contactsResult(let r): contacts = r.kisiler
        case .callLogResult(let r): callLog = r.kayitlar
        case .contactsPage(let p): return applyContactsPage(p)
        case .callLogPage(let p): return applyCallLogPage(p)
        case .contactsChanged:
            guard allows(.kisiler), !contactsLoading else { break }
            return [requestContacts(from: 0)]
        case .callLogChanged:
            guard allows(.aramaGecmisi), !callLogLoading else { break }
            return [requestCallLog(from: 0)]
        case .mediaState(let m): media = m
        case .volState(let v): if v.cihaz == "telefon" { phoneVolume = v }
        case .error(let e): lastError = e
        default: break   // pong, istek tipleri ve kanal yanitlari baska yerde ele alinir
        }
        return []
    }

    // MARK: Sayfali senkron

    private mutating func requestContacts(from offset: Int) -> PeerEnvelope {
        contactsLoading = true
        return PeerEnvelope(.contactsSync(ContactsSync(ofset: offset, adet: Self.contactPageSize)))
    }

    private mutating func requestCallLog(from offset: Int) -> PeerEnvelope {
        callLogLoading = true
        return PeerEnvelope(.callLogSync(CallLogSync(ofset: offset, adet: Self.callLogPageSize)))
    }

    /// Izin degisimi: acildiysa ilk senkron baslar; kapandiysa o verinin bellek onbellegi silinir.
    private mutating func applyPerm(_ p: PermState) -> [PeerEnvelope] {
        perm = p
        var out: [PeerEnvelope] = []
        if !p.kisiler {
            contactBook = []; contactsLoaded = false; contactsLoading = false; contactsTotal = nil; contacts = []
        } else if !contactsLoaded && !contactsLoading {
            out.append(requestContacts(from: 0))
        }
        if !p.aramaGecmisi {
            callLog = nil; callLogLoaded = false; callLogLoading = false
        } else if !callLogLoaded && !callLogLoading {
            out.append(requestCallLog(from: 0))
        }
        return out
    }

    private mutating func applyContactsPage(_ page: ContactsPage) -> [PeerEnvelope] {
        guard allows(.kisiler) else { return [] }
        if page.ofset == 0 { contactBook = [] }
        guard page.ofset == contactBook.count else { contactsLoading = false; return [] }   // sira disi sayfa: yoksay, bayragi kapat
        contactBook.append(contentsOf: page.kisiler)
        contactsTotal = page.toplam
        if page.son || page.kisiler.isEmpty {
            contactsLoaded = true; contactsLoading = false
            return []
        }
        return [requestContacts(from: contactBook.count)]
    }

    private mutating func applyCallLogPage(_ page: CallLogPage) -> [PeerEnvelope] {
        guard allows(.aramaGecmisi) else { return [] }
        var log = callLog ?? []
        if page.ofset == 0 { log = [] }
        guard page.ofset == log.count else { callLogLoading = false; return [] }
        log.append(contentsOf: page.kayitlar)
        callLog = log
        if page.son || page.kayitlar.isEmpty || log.count >= Self.callLogLimit {
            callLogLoaded = true; callLogLoading = false
            return []
        }
        return [requestCallLog(from: log.count)]
    }

    /// Baglanti koptu: canli durum (arama, kulaklik) gecersiz; telefon bilgisi ve izinler son bilinen olarak kalir.
    public mutating func disconnected() {
        call = CallState(durum: .bosta)
        earbuds = [:]
        media = nil
        phoneVolume = nil
        contacts = []
        contactBook = []
        contactsLoaded = false; contactsLoading = false; contactsTotal = nil
        callLog = nil
        callLogLoaded = false; callLogLoading = false
    }

    /// Eslesme kaldirildi: her sey silinir.
    public mutating func reset() { self = PhoneSnapshot() }

    public static func transition(from old: CallState, to new: CallState) -> CallTransition {
        if old.durum == .bosta, new.durum == .caliyor, new.yon == .gelen { return .gelenBasladi }
        if old.durum != .bosta, new.durum == .bosta { return .bitti }
        return .yok
    }

    /// Taninmayan mesaj tipine verilecek yanit (olumcul degil).
    public static func unknownTypeReply(_ type: String) -> PeerEnvelope {
        PeerEnvelope(.error(PeerError(kod: "bilinmeyen_tip", mesaj: type)))
    }
}
