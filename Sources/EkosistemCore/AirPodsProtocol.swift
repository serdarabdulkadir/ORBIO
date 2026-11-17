// Apple Accessory Protocol (AAP): AirPods / Beats kontrol kanalinin SAF paket kurucu ve ayristiricisi.
// Tasima: L2CAP PSM 0x1001; her L2CAP veri birimi tek bir AAP paketidir (ek cerceveleme gerekmez).
// Bu dosya G/C yapmaz, IOBluetooth'a dokunmaz; kanal sahibi sinif `AirPodsLink` (BTEkosistem).
//
// Apple bu protokolu belgelemedi. Bayt anlamlari topluluk tersine muhendisliginden OKUNDU, kod kopyalanmadi
// (GPL projelerden hicbir kod / yapi alinmadi; asagidaki olgular bagimsiz yazildi):
//  - tyalie/AAP-Protocol-Defintion (Kaitai tanimi, PSM 0x1001, PacketLogger notlari)
//  - LibrePods docs: "AAP Definitions", control_commands, opcodes, device-info
//  - d4rken-org/capod (AAP ust yapisi: paket turleri, canli cihaz yakalamalarindan duzeltmeler)
// Etiketler: [dogrulandi-kaynak] = en az iki bagimsiz topluluk kaynaginda tutarli (cihazimizda SINANMADI);
// [deneysel] = tek kaynak, kaynaklar celisiyor ya da cikarim. Ayrinti: docs/airpods.md.
import Foundation

// MARK: - Degerler

/// Kulaklik yerlesimi (kulak algilama, opcode 0x0006). [dogrulandi-kaynak]: 00 kulakta, 01 kulak disinda, 02 kutuda.
public enum AAPPodPlacement: Equatable, Sendable, Codable {
    case inEar, outOfEar, inCase
    case unknown(UInt8)

    init(wire: UInt8) {
        switch wire {
        case 0x00: self = .inEar
        case 0x01: self = .outOfEar
        case 0x02: self = .inCase
        default: self = .unknown(wire)
        }
    }
}

/// Pil bileseni kodu (opcode 0x0004). [dogrulandi-kaynak]: 0x02 sag, 0x04 sol, 0x08 kutu; 0x01 tek parca [deneysel].
public enum AAPBatteryComponent: UInt8, Equatable, Sendable, Codable {
    case single = 0x01, right = 0x02, left = 0x04, caseBox = 0x08
}

/// Sarj durumu bayti. [dogrulandi-kaynak]: 1 sarj oluyor, 2 bosaliyor, 4 bagli degil; 5 "optimize sarj" [deneysel].
public enum AAPChargeState: Equatable, Sendable, Codable {
    case unknown, charging, discharging, disconnected, optimized

    init(wire: UInt8) {
        switch wire {
        case 0x01: self = .charging
        case 0x02: self = .discharging
        case 0x04: self = .disconnected
        case 0x05: self = .optimized
        default: self = .unknown
        }
    }

    public var isCharging: Bool { self == .charging || self == .optimized }
}

public struct AAPBatteryEntry: Equatable, Sendable, Codable {
    public let component: AAPBatteryComponent
    public let percent: Int
    public let state: AAPChargeState
}

/// Cihaz bilgisi (opcode 0x001D, kulaklik baglaninca kendiliginden gelir). [deneysel]: tek ornek paket uzerinden.
public struct AAPDeviceInfo: Equatable, Sendable, Codable {
    public let name: String
    /// Apple model numarasi, ornek "A3048" (`AppleModelCatalog.model(forModelNumber:)` ile eslenir).
    public let modelNumber: String
    public let manufacturer: String
    public let serialNumber: String
    public let firmwareVersion: String
}

/// Konusma farkindaligi etkinligi (opcode 0x004B). [dogrulandi-kaynak]: 1/2 konusmaya basladi, 3 durdu,
/// 8/9 normal ses; 5 (konusma suruyor) [deneysel].
public enum AAPConversationActivity: Equatable, Sendable {
    case speaking, stopped, normalVolume
    case other(UInt8)

    init(wire: UInt8) {
        switch wire {
        case 0x01, 0x02, 0x05: self = .speaking
        case 0x03: self = .stopped
        case 0x08, 0x09: self = .normalVolume
        default: self = .other(wire)
        }
    }
}

public extension ListeningMode {
    /// AAP dinleme modu baytlari. [dogrulandi-kaynak]: 1 kapali, 2 gurultu engeli, 3 seffaf, 4 uyarlanir.
    var aapValue: UInt8 {
        switch self {
        case .kapali: 0x01
        case .gurultuEngeli: 0x02
        case .seffaf: 0x03
        case .uyarlanir: 0x04
        }
    }

    init?(aapValue: UInt8) {
        switch aapValue {
        case 0x01: self = .kapali
        case 0x02: self = .gurultuEngeli
        case 0x03: self = .seffaf
        case 0x04: self = .uyarlanir
        default: return nil
        }
    }
}

// MARK: - Olaylar

/// Kulakliktan gelen bir paketin cozulmus hali.
public enum AAPEvent: Equatable, Sendable {
    /// Tur 0x0001 baglanti yaniti, durum 0. [dogrulandi-kaynak]
    case handshakeAccepted(major: UInt16, minor: UInt16, features: UInt64)
    /// Tur 0x0001, durum != 0: kulaklik kanali reddetti.
    case handshakeRejected(status: UInt16)
    /// Tur 0x0002 baglanti kesme.
    case disconnected(status: UInt16)
    /// 0x0004 pil bildirimi (bos olabilir).
    case battery([AAPBatteryEntry])
    /// 0x0006 kulak algilama: birincil / ikincil kulaklik. Hangisinin sol oldugu `budRole` ile bilinir.
    case earDetection(primary: AAPPodPlacement, secondary: AAPPodPlacement)
    /// 0x0008 birincil (mikrofon) kulaklik. [deneysel]: sekil yalniz iki kaynakta, kisa belge.
    case budRole(primaryIsLeft: Bool)
    /// Kontrol 0x0D dinleme modu. [dogrulandi-kaynak]
    case listeningMode(ListeningMode)
    /// Kontrol 0x1A dongu maskesi (bit 0 kapali, 1 ANC, 2 seffaf, 3 uyarlanir). [dogrulandi-kaynak]
    case listeningModeCycle(mask: UInt8)
    /// Kontrol 0x28 konusma farkindaligi ayari (1 acik, 2 kapali). [dogrulandi-kaynak]
    case conversationalAwarenessSetting(Bool)
    /// 0x004B konusma etkinligi bildirimi.
    case conversationActivity(AAPConversationActivity)
    /// Kontrol 0x0A kulak algilama ayari (1 acik, 2 kapali). [dogrulandi-kaynak]
    case earDetectionSetting(Bool)
    /// Kontrol 0x1B tek kulaklikla ANC (1 acik, 2 kapali). [dogrulandi-kaynak]
    case oneBudANC(Bool)
    /// Kontrol 0x2E uyarlanir gurultu seviyesi, ham bayt 0...100. [deneysel]: kaynaklar yonu celisiyor
    /// (LibrePods: 100 = daha cok filtre; capod canli cihazda tersini bildiriyor). Yorum yapmadan ham tutulur.
    case adaptiveStrength(wire: UInt8)
    case deviceInfo(AAPDeviceInfo)
    /// Taninmayan / ilgisiz opcode ya da bozuk govde (olay uretmez, yalniz kayit icin).
    case unhandled(opcode: UInt16)
}

// MARK: - Ayristirici

public enum AAPParser {
    static let typeConnectResponse: UInt16 = 0x0001
    static let typeDisconnect: UInt16 = 0x0002
    static let typeMessage: UInt16 = 0x0004
    static let service: UInt16 = 0x0004

    static let opBattery: UInt16 = 0x0004
    static let opEarDetection: UInt16 = 0x0006
    static let opBudRole: UInt16 = 0x0008
    static let opControl: UInt16 = 0x0009
    static let opDeviceInfo: UInt16 = 0x001D
    static let opConversation: UInt16 = 0x004B

    static let ctlEarDetection: UInt8 = 0x0A
    static let ctlListeningMode: UInt8 = 0x0D
    static let ctlListeningModeCycle: UInt8 = 0x1A
    static let ctlOneBudANC: UInt8 = 0x1B
    static let ctlConversation: UInt8 = 0x28
    static let ctlAdaptiveStrength: UInt8 = 0x2E

    /// Tek bir L2CAP veri birimini cozer. Kisa / bozuk / AAP olmayan veri icin nil.
    public static func parse(_ p: [UInt8]) -> AAPEvent? {
        guard p.count >= 4 else { return nil }
        let type = le16(p, 0)
        switch type {
        case typeConnectResponse:
            guard p.count >= 18 else { return nil }
            let status = le16(p, 4)
            guard status == 0 else { return .handshakeRejected(status: status) }
            return .handshakeAccepted(major: le16(p, 6), minor: le16(p, 8), features: le64(p, 10))
        case typeDisconnect:
            guard p.count >= 6 else { return nil }
            return .disconnected(status: le16(p, 4))
        case typeMessage:
            guard p.count >= 6, le16(p, 2) == service else { return nil }
            return parseMessage(opcode: le16(p, 4), payload: Array(p.dropFirst(6)))
        default:
            return nil
        }
    }

    static func parseMessage(opcode: UInt16, payload: [UInt8]) -> AAPEvent {
        let unhandled = AAPEvent.unhandled(opcode: opcode)
        switch opcode {
        case opBattery:
            return .battery(parseBattery(payload))
        case opEarDetection:
            guard payload.count >= 2 else { return unhandled }
            return .earDetection(primary: AAPPodPlacement(wire: payload[0]), secondary: AAPPodPlacement(wire: payload[1]))
        case opBudRole:
            // [pod 01 sol / 02 sag] 00 [00|01] ... ; sekil uymazsa yok sayilir.
            guard payload.count >= 4, payload[1] == 0x00, payload[2] <= 0x01,
                  payload[0] == 0x01 || payload[0] == 0x02 else { return unhandled }
            return .budRole(primaryIsLeft: payload[0] == 0x01)
        case opControl:
            return parseControl(payload) ?? unhandled
        case opConversation:
            // Eski: tek bayt; yeni: 02 00 01 <durum>.
            if payload.count == 1 { return .conversationActivity(AAPConversationActivity(wire: payload[0])) }
            if payload.count == 4, payload[0] == 0x02, payload[1] == 0x00, payload[2] == 0x01 {
                return .conversationActivity(AAPConversationActivity(wire: payload[3]))
            }
            return unhandled
        case opDeviceInfo:
            return parseDeviceInfo(payload).map(AAPEvent.deviceInfo) ?? unhandled
        default:
            return unhandled
        }
    }

    /// Her kayit 5 bayt: bilesen, 0x01 (ayirici), yuzde, sarj durumu, 0x01. Yuzde > 100 (127 sahte, 255 bagli degil) atilir.
    static func parseBattery(_ payload: [UInt8]) -> [AAPBatteryEntry] {
        guard let count = payload.first else { return [] }
        var entries: [AAPBatteryEntry] = []
        var offset = 1
        for _ in 0..<Int(count) {
            guard offset + 5 <= payload.count else { break }
            defer { offset += 5 }
            guard let component = AAPBatteryComponent(rawValue: payload[offset]) else { continue }
            let percent = Int(payload[offset + 2])
            guard percent <= 100 else { continue }
            entries.append(AAPBatteryEntry(component: component, percent: percent,
                                           state: AAPChargeState(wire: payload[offset + 3])))
        }
        return entries
    }

    /// Kontrol paketi govdesi: [kimlik] [deger] [0] [0] [0]. Yalniz bilinen kimlikler ve gecerli degerler cozulur.
    static func parseControl(_ payload: [UInt8]) -> AAPEvent? {
        guard payload.count >= 2 else { return nil }
        let value = payload[1]
        switch payload[0] {
        case ctlListeningMode:
            return ListeningMode(aapValue: value).map(AAPEvent.listeningMode)
        case ctlListeningModeCycle:
            return .listeningModeCycle(mask: value & 0x0F)
        case ctlConversation:
            return appleBool(value).map(AAPEvent.conversationalAwarenessSetting)
        case ctlEarDetection:
            return appleBool(value).map(AAPEvent.earDetectionSetting)
        case ctlOneBudANC:
            return appleBool(value).map(AAPEvent.oneBudANC)
        case ctlAdaptiveStrength:
            guard value <= 100 else { return nil }
            return AAPEvent.adaptiveStrength(wire: value)
        default:
            return nil
        }
    }

    /// Apple mantiksal degeri: 1 dogru, 2 yanlis, baska deger bilinmiyor.
    static func appleBool(_ v: UInt8) -> Bool? {
        switch v {
        case 0x01: true
        case 0x02: false
        default: nil
        }
    }

    /// Govde: sabit onek (gozlenen 02 D5 00 04 00; anlami bilinmiyor) + NUL ayrimli UTF-8 metinler:
    /// ad, model numarasi, uretici, seri no, yazilim surumu. Ilk yazdirilabilir bayttan baslar. [deneysel]
    static func parseDeviceInfo(_ payload: [UInt8]) -> AAPDeviceInfo? {
        guard let start = payload.firstIndex(where: { $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        let fields = payload[start...].split(separator: 0x00, maxSplits: 8, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        guard fields.count >= 2, !fields[0].isEmpty else { return nil }
        func field(_ i: Int) -> String { i < fields.count ? fields[i] : "" }
        return AAPDeviceInfo(name: field(0), modelNumber: field(1), manufacturer: field(2),
                             serialNumber: field(3), firmwareVersion: field(4))
    }

    static func le16(_ p: [UInt8], _ i: Int) -> UInt16 { UInt16(p[i]) | UInt16(p[i + 1]) << 8 }

    static func le64(_ p: [UInt8], _ i: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(p[i + $1]) << UInt64(8 * $1) }
    }
}

// MARK: - Paket kurucu

public enum AAPPacket {
    /// El sikisma (tur 0, hizmet 4, surum 1.2, ozellik 0). Bu olmadan kulaklik hicbir pakete yanit vermez.
    /// [dogrulandi-kaynak]
    public static let handshake: [UInt8] = [0x00, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00,
                                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

    /// Bildirimleri ac (opcode 0x000F, tum filtreler): pil, kulak algilama, mod, konusma. [dogrulandi-kaynak]
    public static let requestNotifications: [UInt8] = [0x04, 0x00, 0x04, 0x00, 0x0F, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]

    /// Ana bilgisayar ozelliklerini bildir (opcode 0x004D): Uyarlanir mod ve ses calarken konusma farkindaligi icin
    /// gerekli. [deneysel]: LibrePods 0xFF, capod 0xD7 kullaniyor; az iddia eden (0xD7) secildi.
    public static let featureEnable: [UInt8] = [0x04, 0x00, 0x04, 0x00, 0x4D, 0x00, 0xD7, 0x00,
                                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

    /// Kontrol komutu: 04 00 04 00 09 00 [kimlik] [deger] 00 00 00. [dogrulandi-kaynak]
    public static func control(_ id: UInt8, _ value: UInt8) -> [UInt8] {
        [0x04, 0x00, 0x04, 0x00, 0x09, 0x00, id, value, 0x00, 0x00, 0x00]
    }

    public static func setListeningMode(_ mode: ListeningMode) -> [UInt8] {
        control(AAPParser.ctlListeningMode, mode.aapValue)
    }

    public static func setConversationalAwareness(_ on: Bool) -> [UInt8] {
        control(AAPParser.ctlConversation, on ? 0x01 : 0x02)
    }

    public static func setEarDetection(_ on: Bool) -> [UInt8] {
        control(AAPParser.ctlEarDetection, on ? 0x01 : 0x02)
    }

    public static func setOneBudANC(_ on: Bool) -> [UInt8] {
        control(AAPParser.ctlOneBudANC, on ? 0x01 : 0x02)
    }

    /// Uyarlanir gurultu seviyesi, ham bayt (0...100'e kirpilir). Yon belirsiz: bkz. `AAPEvent.adaptiveStrength`. [deneysel]
    public static func setAdaptiveStrength(wire: UInt8) -> [UInt8] {
        control(AAPParser.ctlAdaptiveStrength, min(wire, 100))
    }
}

// MARK: - Cihaz durumu

/// AAP'den okunan kulaklik durumu; QCY'deki `QcyDeviceState`in AirPods karsiligi. Saf deger tipi.
public struct AirPodsDeviceState: Equatable, Sendable, Codable {
    public var listeningMode: ListeningMode?
    public var listeningModeCycleMask: UInt8?
    public var earDetectionEnabled: Bool?
    public var conversationalAwareness: Bool?
    public var oneBudANC: Bool?
    public var adaptiveStrengthWire: UInt8?
    /// Takan kisi su an konusuyor mu (konusma farkindaligi bildirimi).
    public var isSpeaking = false
    public var primaryPlacement: AAPPodPlacement?
    public var secondaryPlacement: AAPPodPlacement?
    public var primaryIsLeft: Bool?
    public var left: AAPBatteryEntry?
    public var right: AAPBatteryEntry?
    public var caseBox: AAPBatteryEntry?
    public var single: AAPBatteryEntry?
    public var info: AAPDeviceInfo?

    public init() {}

    public mutating func apply(_ event: AAPEvent) {
        switch event {
        case .battery(let entries):
            for e in entries {
                switch e.component {
                case .left: left = e
                case .right: right = e
                case .caseBox: caseBox = e
                case .single: single = e
                }
            }
        case .earDetection(let primary, let secondary):
            primaryPlacement = primary; secondaryPlacement = secondary
        case .budRole(let primaryIsLeft): self.primaryIsLeft = primaryIsLeft
        case .listeningMode(let mode): listeningMode = mode
        case .listeningModeCycle(let mask): listeningModeCycleMask = mask
        case .conversationalAwarenessSetting(let on): conversationalAwareness = on
        case .conversationActivity(let activity):
            switch activity {
            case .speaking: isSpeaking = true
            case .stopped, .normalVolume: isSpeaking = false
            case .other: break
            }
        case .earDetectionSetting(let on): earDetectionEnabled = on
        case .oneBudANC(let on): oneBudANC = on
        case .adaptiveStrength(let wire): adaptiveStrengthWire = wire
        case .deviceInfo(let info): self.info = info
        case .handshakeAccepted, .handshakeRejected, .disconnected, .unhandled: break
        }
    }

    /// Sol / sag yerlesimi; yalniz birincil kulaklik bilindiginde. [deneysel]
    public var leftPlacement: AAPPodPlacement? { placement(isLeft: true) }
    public var rightPlacement: AAPPodPlacement? { placement(isLeft: false) }

    private func placement(isLeft: Bool) -> AAPPodPlacement? {
        guard let primaryIsLeft else { return nil }
        return (primaryIsLeft == isLeft) ? primaryPlacement : secondaryPlacement
    }

    /// Kulakta olan kulaklik sayisi; iki yerlesim de bilinmiyorsa nil. Yon bilgisi gerekmez.
    public var podsInEar: Int? {
        guard let a = primaryPlacement, let b = secondaryPlacement else { return nil }
        return [a, b].filter { $0 == .inEar }.count
    }

    /// Pil okumasi; hic pil kaydi yoksa nil. Bagli olmayan (`disconnected`) bilesen yuzdesi gosterilmez. [deneysel]
    public func batteryReading(at time: Date) -> BatteryReading? {
        guard left != nil || right != nil || caseBox != nil || single != nil else { return nil }
        func pct(_ e: AAPBatteryEntry?) -> Int? { e.flatMap { $0.state == .disconnected ? nil : $0.percent } }
        func chg(_ e: AAPBatteryEntry?) -> Bool { e?.state.isCharging ?? false }
        return BatteryReading(left: pct(left), right: pct(right), caseLevel: pct(caseBox), overall: pct(single),
                              leftCharging: chg(left), rightCharging: chg(right),
                              caseCharging: chg(caseBox) || chg(single),
                              source: .markaOzel, timestamp: time)
    }
}

// MARK: - Oturum (saf durum makinesi)

/// Bir AAP baglantisinin protokol mantigi: ne zaman ne gonderilir, gelen paket durumu nasil gunceller.
/// Kanal acma / yazma `AirPodsLink`'te; burada yalniz bayt dizileri girer cikar.
/// Cizirti / ses akisini bozmamak icin: acilista yalniz 2 paket (el sikisma + bildirim istegi), hazir olunca bir kez
/// ozellik bildirimi (yalniz Uyarlanir / konusma farkindaligi olan bilinen modeller), sonra yalniz kullanici komutu.
public struct AAPSession: Sendable {
    public enum Phase: Equatable, Sendable { case idle, handshaking, ready, closed }

    public struct Step: Equatable, Sendable {
        public var events: [AAPEvent] = []
        /// Sirayla yazilacak paketler.
        public var send: [[UInt8]] = []
    }

    public private(set) var phase: Phase = .idle
    public private(set) var state = AirPodsDeviceState()
    public let model: AppleModel?
    private var featureSent = false

    public init(model: AppleModel? = nil) { self.model = model }

    /// Kanal acilinca cagrilir; gonderilecek ilk paketler.
    public mutating func begin() -> [[UInt8]] {
        guard phase == .idle else { return [] }
        phase = .handshaking
        return [AAPPacket.handshake, AAPPacket.requestNotifications]
    }

    /// Gelen tek L2CAP veri birimini isler.
    public mutating func receive(_ bytes: [UInt8]) -> Step {
        var step = Step()
        guard phase == .handshaking || phase == .ready, let event = AAPParser.parse(bytes) else { return step }
        step.events = [event]
        switch event {
        case .handshakeRejected, .disconnected:
            phase = .closed
            return step
        default:
            break
        }
        state.apply(event)
        if phase == .handshaking {
            phase = .ready
            if !featureSent, let model, model.supports(.adaptive) || model.supports(.conversationAwareness) {
                featureSent = true
                step.send.append(AAPPacket.featureEnable)
            }
        }
        return step
    }

    /// Kanal kapandi / koptu.
    public mutating func close() { phase = .closed }

    // MARK: Komutlar: nil = gonderme (hazir degil, model desteklemiyor ya da durum zaten bu).

    public func listeningModeCommand(_ mode: ListeningMode) -> [UInt8]? {
        guard phase == .ready, state.listeningMode != mode else { return nil }
        if let model {
            guard model.listeningModes.contains(mode) else { return nil }
        } else if mode == .uyarlanir {
            return nil
        }
        return AAPPacket.setListeningMode(mode)
    }

    public func conversationalAwarenessCommand(_ on: Bool) -> [UInt8]? {
        guard phase == .ready, model?.supports(.conversationAwareness) == true,
              state.conversationalAwareness != on else { return nil }
        return AAPPacket.setConversationalAwareness(on)
    }

    public func earDetectionCommand(_ on: Bool) -> [UInt8]? {
        guard phase == .ready, model?.supports(.earDetection) == true, state.earDetectionEnabled != on else { return nil }
        return AAPPacket.setEarDetection(on)
    }

    public func oneBudANCCommand(_ on: Bool) -> [UInt8]? {
        guard phase == .ready, model?.supports(.oneBudANC) == true, state.oneBudANC != on else { return nil }
        return AAPPacket.setOneBudANC(on)
    }

    public func adaptiveStrengthCommand(wire: UInt8) -> [UInt8]? {
        guard phase == .ready, model?.supports(.adaptiveStrength) == true,
              state.adaptiveStrengthWire != min(wire, 100) else { return nil }
        return AAPPacket.setAdaptiveStrength(wire: wire)
    }
}
