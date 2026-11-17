// QCY (MeloBuds) protokolu: BLE reklamindaki pil + kontrol adresi ve A001 servisindeki komut cercevesi.
// Kaynak: topluluk tersine muhendisligi (OpenQCY-Desktop, N70) ve MeloBuds Pro uzerinde dogrulanan reklam paketi.
import Foundation

public struct QcyAdvertisement: Equatable, Sendable {
    public static let companyID: UInt16 = 0x521C

    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var leftCharging: Bool
    public var rightCharging: Bool
    public var caseCharging: Bool
    /// Kulakligin klasik Bluetooth adresi ("84:AC:60:20:9D:3A"), eslesmis cihazla eslemek icin.
    public var controlAddress: String?

    /// `manufacturerData`: CoreBluetooth'un verdigi ham veri (ilk iki bayt sirket kimligi, kucuk uclu: 1C 52).
    public static func parse(manufacturerData: [UInt8]) -> QcyAdvertisement? {
        guard manufacturerData.count >= 2 + 8,
              UInt16(manufacturerData[0]) | UInt16(manufacturerData[1]) << 8 == companyID else { return nil }
        let d = Array(manufacturerData.dropFirst(2))
        // Ham deger 0 = kutu / kulaklik okumasi yok (ornegin kutu yanda degil).
        func level(_ raw: UInt8) -> Int? { raw == 0 ? nil : min(Int(raw & 0x7F), 100) }
        var address: String?
        if d.count >= 17 {
            let bytes = [d[12], d[11], d[13], d[16], d[15], d[14]]
            if bytes.contains(where: { $0 != 0 }) { address = bytes.map { String(format: "%02X", $0) }.joined(separator: ":") }
        }
        return QcyAdvertisement(left: level(d[5]), right: level(d[6]), caseLevel: level(d[7]),
                                leftCharging: d[5] & 0x80 != 0, rightCharging: d[6] & 0x80 != 0,
                                caseCharging: d[7] & 0x80 != 0, controlAddress: address)
    }

    public func reading(at time: Date) -> BatteryReading {
        BatteryReading(left: left, right: right, caseLevel: caseLevel,
                       leftCharging: leftCharging, rightCharging: rightCharging, caseCharging: caseCharging,
                       source: .markaOzel, timestamp: time)
    }
}

/// A001 servisi: `1001` komut (yaz), `1002` yanit (bildirim).
public enum QcyGatt {
    public static let service = "A001"
    public static let command = "1001"
    public static let response = "1002"
}

public enum QcyPacket {
    /// `FF <govde uzunlugu> <opcode> <parametre uzunlugu> <parametreler>`
    public static func pack(opcode: UInt8, _ parameters: [UInt8]) -> [UInt8] {
        [0xFF, UInt8(parameters.count + 2), opcode, UInt8(parameters.count)] + parameters
    }

    /// Istek: `FF 03 FE 01 <opcode>`
    public static func request(opcode: UInt8) -> [UInt8] { pack(opcode: 0xFE, [opcode]) }

    /// Yanit paketindeki (opcode, parametre) bloklari. Bozuk paket bos doner.
    public static func parse(_ packet: [UInt8]) -> [(opcode: UInt8, parameters: [UInt8])] {
        guard packet.count >= 4, packet[0] == 0xFF, Int(packet[1]) + 2 == packet.count else { return [] }
        var out: [(UInt8, [UInt8])] = []
        var i = 2
        while i < packet.count {
            guard i + 2 <= packet.count else { return [] }
            let op = packet[i], len = Int(packet[i + 1])
            i += 2
            guard i + len <= packet.count else { return [] }
            out.append((op, Array(packet[i..<i + len])))
            i += len
        }
        return out
    }
}

public enum QcyNoise {
    public static let opcode: UInt8 = 0x17

    /// Kapali (normal) / gurultu engeli (uyarlanir sahne) / seffaf. `.uyarlanir` desteklenmez.
    public static func setMode(_ mode: ListeningMode) -> [UInt8]? {
        switch mode {
        case .gurultuEngeli: QcyPacket.pack(opcode: opcode, [0x01, 0x05, 0x00])
        case .kapali: QcyPacket.pack(opcode: opcode, [0x02, 0x00, 0x00])
        case .seffaf: QcyPacket.pack(opcode: opcode, [0x03, 0x01, 0x04])
        case .uyarlanir: nil
        }
    }

    public static func parseMode(_ parameters: [UInt8]) -> ListeningMode? {
        guard let first = parameters.first else { return nil }
        switch first {
        case 0x01: return .gurultuEngeli
        case 0x02: return .kapali
        case 0x03: return .seffaf
        default: return nil
        }
    }
}

/// Seffaf mod seviyesi: `FF 05 17 03 03 01 <seviye>`. Kaynak: MeloBuds Pro'da seviye=04 yazildi ve cihaz aynen geri bildirdi.
/// Hangi degerin ne kadar seffaflik verdigi DOGRULANMAMISTIR; arayuz 1...8 araligina sinirlar (1 az, 8 cok).
public enum QcyTransparency {
    public static let range: ClosedRange<Int> = 1...8
    public static let defaultLevel = 4

    public static func clamp(_ level: Int) -> UInt8 { UInt8(min(max(level, range.lowerBound), range.upperBound)) }

    public static func packet(level: Int) -> [UInt8] {
        QcyPacket.pack(opcode: QcyNoise.opcode, [0x03, 0x01, clamp(level)])
    }

    /// Seffaf yanitin 3. bayti seviye; baska modda ya da kisa pakette nil.
    public static func parseLevel(_ parameters: [UInt8]) -> Int? {
        guard parameters.count >= 3, parameters[0] == 0x03 else { return nil }
        return Int(parameters[2])
    }
}

/// Gurultu engelleme sahnesi: `0x17` parametreleri `01 <sahne> <deger>`.
/// Kaynak: OpenQCY-Desktop (N70 uzerinde eslendi); MeloBuds Pro'da yalniz Uyarlanir (`01 05 00`) cihazdan gorulmustur.
public enum QcyNoiseScene: String, Sendable, CaseIterable, Equatable {
    case uyarlanir, kapaliAlan, yolculuk, gurultulu, ruzgarKarsiti

    var bytes: (scene: UInt8, value: UInt8) {
        switch self {
        case .uyarlanir: (0x05, 0x00)
        case .kapaliAlan: (0x01, 0x02)
        case .yolculuk: (0x02, 0x02)
        case .gurultulu: (0x03, 0x02)
        case .ruzgarKarsiti: (0x04, 0x00)
        }
    }

    /// `01 <sahne> <deger>`; sahne ve deger tabloyla birebir eslesmezse nil.
    public static func parse(_ parameters: [UInt8]) -> QcyNoiseScene? {
        guard parameters.count >= 3, parameters[0] == 0x01 else { return nil }
        return allCases.first { $0.bytes.scene == parameters[1] && $0.bytes.value == parameters[2] }
    }

    public var packet: [UInt8] {
        QcyPacket.pack(opcode: QcyNoise.opcode, [0x01, bytes.scene, bytes.value])
    }
}

/// Kulak algilama (`0x2C`). Okuma: `<durum 00/01> <muzik> <anc> [ton]`.
/// Yazma: `<durum 01 acik / 02 kapali> <muzik> <anc> [ton 01/02]`.
/// Muzik / ANC eylem baytlarinin anlami kaynakta belgelenmemistir: yalnizca cihazdan okunan deger aynen geri yazilir.
public struct QcyWearingDetection: Equatable, Sendable {
    public static let opcode: UInt8 = 0x2C
    public var enabled: Bool
    public var musicAction: UInt8
    public var ancAction: UInt8
    public var toneEnabled: Bool?

    public init(enabled: Bool, musicAction: UInt8, ancAction: UInt8, toneEnabled: Bool?) {
        self.enabled = enabled; self.musicAction = musicAction
        self.ancAction = ancAction; self.toneEnabled = toneEnabled
    }

    public static func parse(_ p: [UInt8]) -> QcyWearingDetection? {
        guard p.count == 3 || p.count == 4 else { return nil }
        let on: Bool
        switch p[0] {
        case 0x01: on = true
        case 0x00, 0x02: on = false
        default: return nil
        }
        return QcyWearingDetection(enabled: on, musicAction: p[1], ancAction: p[2],
                                   toneEnabled: p.count == 4 ? p[3] == 0x01 : nil)
    }

    /// Yalnizca acma / kapama degisir; diger baytlar mevcut okumadan korunur.
    public func setEnabledPacket(_ enabled: Bool) -> [UInt8] {
        var params: [UInt8] = [enabled ? 0x01 : 0x02, musicAction, ancAction]
        if let toneEnabled { params.append(toneEnabled ? 0x01 : 0x02) }
        return QcyPacket.pack(opcode: Self.opcode, params)
    }
}

/// Dokunmatik taraf. Kaynak: docs/qcy-protokol-cozum.md bolum 3.1 (QCY resmi uygulamasi, APK).
public enum QcyTouchSide: UInt8, CaseIterable, Sendable { case left, right }

/// Dokunus turu. Dort dokunus / uzun basis eventID'leri (7-10) yalniz eski V1 sabitlerinde; dogrulanmadigi icin yok.
public enum QcyTouchGesture: UInt8, CaseIterable, Sendable { case single = 1, double = 3, triple = 5 }

/// Tus islevi kodlari (doktaki bolum 3.2; modele gore degisebilir). ANC degistir vb. kodlar bulunamadi.
public enum QcyKeyFunction: UInt8, CaseIterable, Sendable {
    case none = 0, playPause = 1, previous = 2, next = 3, voiceAssistant = 4
    case volumeUp = 5, volumeDown = 6, gameMode = 7
}

/// Taraf + dokunus cifti (eventID 1...6).
public struct QcyTouchSlot: Hashable, Sendable {
    public let side: QcyTouchSide
    public let gesture: QcyTouchGesture
    public init(side: QcyTouchSide, gesture: QcyTouchGesture) { self.side = side; self.gesture = gesture }

    public static var all: [QcyTouchSlot] {
        QcyTouchGesture.allCases.flatMap { g in QcyTouchSide.allCases.map { QcyTouchSlot(side: $0, gesture: g) } }
    }
    public var eventID: UInt8 { QcyTouchKeys.eventID(side: side, gesture: gesture) }
}

/// `000D` olay kimlikleri ve `[eventID, islevKodu]` cifti: 1/2 tek, 3/4 cift, 5/6 uc dokunus (sol/sag).
public enum QcyTouchKeys {
    public static func eventID(side: QcyTouchSide, gesture: QcyTouchGesture) -> UInt8 {
        gesture.rawValue + (side == .right ? 1 : 0)
    }

    /// Doktaki yazma biçimi: ornek sol cift dokunus -> oynat/duraklat = `03 01`.
    public static func packet(side: QcyTouchSide, gesture: QcyTouchGesture, function: QcyKeyFunction) -> [UInt8] {
        [eventID(side: side, gesture: gesture), function.rawValue]
    }

    public static func slot(eventID: UInt8) -> QcyTouchSlot? {
        QcyTouchSlot.all.first { $0.eventID == eventID }
    }
}

/// `000D` ozelligi (okuma + yazma): `<eventID> <islev>` ciftleri. Ham baytlar aynen saklanir;
/// bir dokunus degisince yalnizca o cift degisir, kalan baytlar (taninmayan anahtarlar, dolgu) korunur.
public struct QcyKeyMap: Equatable, Sendable {
    public static let characteristic = "000D"
    /// Ayni eslemeyi `1002` yanitinda veren opcode.
    public static let opcode: UInt8 = 0x2B
    public let bytes: [UInt8]

    /// Bos ya da tek sayida bayt gecersizdir.
    public init?(bytes: [UInt8]) {
        guard bytes.count >= 2, bytes.count % 2 == 0 else { return nil }
        self.bytes = bytes
    }

    private func index(of key: UInt8) -> Int? {
        stride(from: 0, to: bytes.count, by: 2).first { bytes[$0] == key }
    }

    /// Cihazda bulunan dokunuslar (eventID'si esleme icinde olanlar).
    public var slots: [QcyTouchSlot] { QcyTouchSlot.all.filter { index(of: $0.eventID) != nil } }

    /// Okunan islev; eventID yoksa ya da kod taninmiyorsa nil.
    public func function(side: QcyTouchSide, gesture: QcyTouchGesture) -> QcyKeyFunction? {
        guard let i = index(of: QcyTouchKeys.eventID(side: side, gesture: gesture)) else { return nil }
        return QcyKeyFunction(rawValue: bytes[i + 1])
    }

    /// Yalnizca ilgili cift degisir; eventID yoksa nil.
    public func setting(side: QcyTouchSide, gesture: QcyTouchGesture, to function: QcyKeyFunction) -> QcyKeyMap? {
        guard let i = index(of: QcyTouchKeys.eventID(side: side, gesture: gesture)) else { return nil }
        var copy = bytes
        copy[i + 1] = function.rawValue
        return QcyKeyMap(bytes: copy)
    }
}

/// Cihazdan okunan QCY durumu (yalnizca okunanlar dolu).
public struct QcyDeviceState: Equatable, Sendable {
    public var mode: ListeningMode?
    public var scene: QcyNoiseScene?
    public var wearing: QcyWearingDetection?
    /// Cift cihaz (`0x24`): cihazdan okunan deger; hic okunmadiysa nil. 1 = acik, 0 / 2 = kapali.
    /// Not: gercek MeloBuds Pro `00` dondu; bunun "kapali" mi "desteklenmiyor" mu oldugu dogrulanmamistir.
    public var multipoint: Bool?
    /// Seffaf mod seviyesi (yalnizca mod seffafken cihazdan okunur).
    public var transparencyLevel: Int?
    /// Tus eslemesi (`000D` okumasi ya da `0x2B` yaniti).
    public var keys: QcyKeyMap?
    /// Oyun / dusuk gecikme modu (`0x09`); okunmadiysa nil.
    public var gameMode: Bool?
    /// Kulak algilama ac/kapa (`0x06`); okunmadiysa nil. (`wearing` = `0x2C` eylemleri, ayri.)
    public var earDetection: Bool?
    /// Secili EQ on ayari (`0x22`); okunmadiysa nil.
    public var eqPreset: QcyEqPreset?

    public init(mode: ListeningMode? = nil, scene: QcyNoiseScene? = nil, wearing: QcyWearingDetection? = nil,
                multipoint: Bool? = nil, keys: QcyKeyMap? = nil, transparencyLevel: Int? = nil,
                gameMode: Bool? = nil, earDetection: Bool? = nil, eqPreset: QcyEqPreset? = nil) {
        self.gameMode = gameMode; self.earDetection = earDetection; self.eqPreset = eqPreset
        self.transparencyLevel = transparencyLevel
        self.mode = mode; self.scene = scene; self.wearing = wearing
        self.multipoint = multipoint; self.keys = keys
    }

    /// `0x24` parametresi: 1 acik, 0 / 2 kapali, baska deger tanimsiz.
    public static func parseMultipoint(_ parameters: [UInt8]) -> Bool? {
        switch parameters.first {
        case 0x01: true
        case 0x00, 0x02: false
        default: nil
        }
    }

    /// Yanit blogunu isler; durum degistiyse true.
    @discardableResult
    public mutating func apply(opcode: UInt8, parameters: [UInt8]) -> Bool {
        let before = self
        switch opcode {
        case QcyNoise.opcode:
            guard let m = QcyNoise.parseMode(parameters) else { break }
            mode = m
            scene = m == .gurultuEngeli ? QcyNoiseScene.parse(parameters) : nil
            transparencyLevel = m == .seffaf ? QcyTransparency.parseLevel(parameters) : nil
        case QcyWearingDetection.opcode:
            if let w = QcyWearingDetection.parse(parameters) { wearing = w }
        case QcyCommand.multipointOpcode:
            if let m = Self.parseMultipoint(parameters) { multipoint = m }
        case QcyKeyMap.opcode:
            if let k = QcyKeyMap(bytes: parameters) { keys = k }
        case QcyGameMode.opcode:
            if let g = QcySwitch.parse(parameters) { gameMode = g }
        case QcyEarDetection.opcode:
            if let e = QcySwitch.parse(parameters) { earDetection = e }
        case QcyEqPreset.opcode:
            if let p = QcyEqPreset.parse(parameters) { eqPreset = p }
        default: break
        }
        return self != before
    }

    /// `000D` ozelliginin ham okumasi.
    @discardableResult
    public mutating func apply(keyMapBytes: [UInt8]) -> Bool {
        let before = self
        if let k = QcyKeyMap(bytes: keyMapBytes) { keys = k }
        return self != before
    }

    public func applying(_ command: QcyCommand) -> QcyDeviceState {
        var s = self
        switch command {
        case .mode(let m):
            s.mode = m; s.scene = m == .gurultuEngeli ? .uyarlanir : nil
            s.transparencyLevel = m == .seffaf ? QcyTransparency.defaultLevel : nil
        case .scene(let sc): s.mode = .gurultuEngeli; s.scene = sc; s.transparencyLevel = nil
        case .transparencyLevel(let l):
            s.mode = .seffaf; s.scene = nil; s.transparencyLevel = Int(QcyTransparency.clamp(Int(l)))
        case .wearingDetection(let on): s.wearing?.enabled = on
        case .multipoint(let on): s.multipoint = on
        case .gameMode(let on): s.gameMode = on
        case .earDetection(let on): s.earDetection = on
        case .eqPreset(let p): s.eqPreset = p
        case .touch(let side, let g, let f): if let k = s.keys?.setting(side: side, gesture: g, to: f) { s.keys = k }
        case .customEq: s.eqPreset = nil
        case .keys(let k): s.keys = k
        }
        return s
    }
}

/// Cihaza yazilabilen komutlar.
public enum QcyCommand: Equatable, Sendable {
    public static let multipointOpcode: UInt8 = 0x24

    case mode(ListeningMode)
    case scene(QcyNoiseScene)
    case wearingDetection(Bool)
    /// Cift cihaz: `FF 03 24 01 <01 acik / 02 kapali>` (OpenQCY Toggle).
    case multipoint(Bool)
    /// Oyun / dusuk gecikme modu (`0x09`).
    case gameMode(Bool)
    /// Kulak algilama ac/kapa (`0x06`); `wearingDetection` (`0x2C` eylemleri) ile ayri.
    case earDetection(Bool)
    /// EQ hazir ayari (indeks 0...5, `QcyEqPreset`).
    case eqPreset(QcyEqPreset)
    /// Ozel 10 bant EQ (dB, -8...8; `QcyCustomEq.packets`). Geri okuma dogrulamasi yok.
    case customEq([Int])
    /// Seffaf mod seviyesi (1...8'e sinirlanir); yalniz Ses modu karosundaki kaydirici yazar.
    case transparencyLevel(UInt8)
    /// Tek dokunusun islevi; diger anahtarlar okunan degerle aynen korunur.
    case touch(QcyTouchSide, QcyTouchGesture, QcyKeyFunction)
    /// Tum esleme (ornegin "onceki degere don").
    case keys(QcyKeyMap)

    /// Yazilacak paket; bilinmeyen / okunmamis durumda nil (yazilmaz).
    public func packet(state: QcyDeviceState) -> [UInt8]? {
        switch self {
        case .mode(let m): QcyNoise.setMode(m)
        case .scene(let s): s.packet
        case .wearingDetection(let on): state.wearing?.setEnabledPacket(on)
        case .multipoint(let on): QcyPacket.pack(opcode: Self.multipointOpcode, [on ? 0x01 : 0x02])
        case .transparencyLevel(let l): QcyTransparency.packet(level: Int(l))
        case .gameMode(let on): QcyGameMode.packet(enabled: on)
        case .earDetection(let on): QcyEarDetection.packet(enabled: on)
        case .eqPreset(let p): p.packet
        case .customEq(let gains): QcyCustomEq.packets(gains: gains).first
        case .touch(let side, let g, let f): state.keys?.setting(side: side, gesture: g, to: f)?.bytes
        case .keys(let k): k.bytes
        }
    }

    /// Paket `1001` yerine `000D` ozelligine yazilir.
    public var writesKeyMap: Bool {
        switch self {
        case .touch, .keys: true
        default: false
        }
    }

    /// Dogrulanmamis degerli komutlar: arayuz iyimser degismez, yalnizca geri okunan deger gosterilir.
    public var verifiedByReadback: Bool {
        switch self {
        case .multipoint, .transparencyLevel, .touch, .keys: true
        default: false
        }
    }

    /// Yazma sonrasi okunacak opcode (tus eslemesi icin `000D` dogrudan okunur).
    public var readbackOpcode: UInt8 {
        switch self {
        case .mode, .scene, .transparencyLevel: QcyNoise.opcode
        case .wearingDetection: QcyWearingDetection.opcode
        case .multipoint: Self.multipointOpcode
        case .gameMode: QcyGameMode.opcode
        case .earDetection: QcyEarDetection.opcode
        case .eqPreset, .customEq: QcyEqPreset.opcode
        case .touch, .keys: QcyKeyMap.opcode
        }
    }

    /// Cihazdan okunan durum komutun beklenen sonucunu veriyor mu (yazma sonrasi dogrulama).
    public func isSatisfied(by state: QcyDeviceState) -> Bool {
        switch self {
        case .multipoint(let on): state.multipoint == on
        case .gameMode(let on): state.gameMode == on
        case .earDetection(let on): state.earDetection == on
        case .eqPreset(let p): state.eqPreset == p
        case .transparencyLevel(let l): state.mode == .seffaf && state.transparencyLevel == Int(QcyTransparency.clamp(Int(l)))
        case .customEq: true
        case .touch(let side, let g, let f): state.keys?.function(side: side, gesture: g) == f
        case .keys(let k): state.keys == k
        case .mode(let m): state.mode == m
        case .scene(let s): state.scene == s
        case .wearingDetection(let on): state.wearing?.enabled == on
        }
    }
}

// MARK: - Dogrulanmis ek komutlar (docs/arastirma-2.md bolum 4)

/// Yetenegin kanit duzeyi: cihazda kayitla dogrulandi / resmi uygulamanin APK'sindan okundu, cihazda denenmedi.
public enum QcyEvidence: Sendable { case deviceVerified, apkOnly }

/// QCY yetenekleri. `isVerified` yalnizca arastirmada "Dogrulandi" isaretli olanlar icin true.
/// `apkDerived` olanlar (dokunus, EQ) dogrulanmis sayilmaz ama "APK'dan okundu · cihazda denenmedi"
/// rozetiyle etkindir (docs/qcy-protokol-cozum.md).
public enum QcyCapability: String, CaseIterable, Sendable {
    case gameMode, earDetection, eqPreset, eqCustom, transparencyLevels, multipoint, touchControls

    public var isVerified: Bool {
        switch self {
        case .gameMode, .earDetection: true
        case .eqPreset, .eqCustom, .transparencyLevels, .multipoint, .touchControls: false
        }
    }

    /// APK'dan cikarilan, cihazda denenmemis ama etkinlestirilen yetenekler.
    public var isApkDerived: Bool {
        switch self {
        case .eqPreset, .eqCustom, .touchControls: true
        default: false
        }
    }

    /// Arayuzde etkin mi: dogrulanmis ya da APK kaynakli.
    public var isEnabled: Bool { isVerified || isApkDerived }

    public var evidence: QcyEvidence { isVerified ? .deviceVerified : .apkOnly }

    public static var verified: [QcyCapability] { allCases.filter(\.isVerified) }
}

/// `01` acik, `02` kapali (`00` okumada kapali).
enum QcySwitch {
    static func parse(_ parameters: [UInt8]) -> Bool? {
        switch parameters.first {
        case 0x01: true
        case 0x00, 0x02: false
        default: nil
        }
    }
    static func packet(opcode: UInt8, _ on: Bool) -> [UInt8] { QcyPacket.pack(opcode: opcode, [on ? 0x01 : 0x02]) }
}

/// Oyun / dusuk gecikme modu: `FF 03 09 01 <01 acik / 02 kapali>`.
public enum QcyGameMode {
    public static let opcode: UInt8 = 0x09
    public static func packet(enabled: Bool) -> [UInt8] { QcySwitch.packet(opcode: opcode, enabled) }
    public static func parse(_ parameters: [UInt8]) -> Bool? { QcySwitch.parse(parameters) }
}

/// Kulak algilama ac/kapa: `FF 03 06 01 <01 acik / 02 kapali>`. (`0x2C` eylemleri icin `QcyWearingDetection`.)
public enum QcyEarDetection {
    public static let opcode: UInt8 = 0x06
    public static func packet(enabled: Bool) -> [UInt8] { QcySwitch.packet(opcode: opcode, enabled) }
    public static func parse(_ parameters: [UInt8]) -> Bool? { QcySwitch.parse(parameters) }
}

/// EQ hazir ayari (docs/qcy-protokol-cozum.md bolum 4.1, 6 ayar, indeks 0...5). Adlar APK yedek JSON'undan;
/// MeloBuds Pro'nun kendi indeksleri bulunamadi. Yazma: `0x22` paketi, eqIndex = indeks, bantlar tablodan.
public struct QcyEqPreset: Equatable, Sendable, Hashable {
    public static let opcode: UInt8 = 0x22
    public static let range: ClosedRange<Int> = 0...5
    public static var all: [QcyEqPreset] { range.compactMap { QcyEqPreset(index: $0) } }

    private static let table: [(en: String, tr: String, bands: [Int])] = [
        ("Default", "Varsayılan", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Pop", "Pop", [-6, 5, -3, -2, 5, 4, -4, -3, 6, 4]),
        ("Bass", "Bas", [8, 7, 5, 4, 0, 0, 0, 0, 0, 0]),
        ("Rock", "Rock", [7, 6, 2, 1, -3, -4, 2, 1, 4, 5]),
        ("Soft", "Yumuşak", [5, -5, -4, -4, 3, 2, 4, 4, 0, 0]),
        ("Classic", "Klasik", [6, 7, 1, 2, -1, 1, -4, -6, -7, -8]),
    ]

    public let index: Int

    public init?(index: Int) {
        guard Self.range.contains(index) else { return nil }
        self.index = index
    }

    public var englishName: String { Self.table[index].en }
    /// Turkce etiket (Varsayilan, Pop, Bas, Rock, Yumusak, Klasik).
    public var name: String { Self.table[index].tr }
    /// 31 Hz...16 kHz, 10 bant, dB.
    public var bands: [Int] { Self.table[index].bands }

    /// `0x22` paketi: eqIndex = indeks, master 0, 10 bant tablosu.
    public var packet: [UInt8] {
        QcyCustomEq.packets(gains: bands, eqIndex: UInt8(index)).first ?? []
    }

    /// Eski (000B) yazma yuku: `[eqType] + 10 isaretli bayt`.
    public var legacyPayload: [UInt8] { [UInt8(index)] + bands.map { UInt8(bitPattern: Int8($0)) } }

    /// Ilk bayt on ayar indeksi; 0...5 disi (ornegin 255 = ozel) ya da bos ise nil.
    public static func parse(_ parameters: [UInt8]) -> QcyEqPreset? {
        guard let first = parameters.first else { return nil }
        return QcyEqPreset(index: Int(first))
    }
}

/// Ozel 10 bant EQ (bolum 4.2): `FF N <cmd> <len> <eqIndex> <master uint16 LE> { bant }...`
/// cmd 0x22: bant 7 bayt (freq, kazanc x100 int16, Q x100, tur); cmd 0x20: 6 bayt (turu yok).
/// Q ve tur kaynakta bantlara gore verilmedi: Q = 1.00 ve tur 255 (belirtilmemis) kullanilir (DOGRULANMADI).
public enum QcyCustomEq {
    public static let frequencies: [Int] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let gainRange: ClosedRange<Int> = -8...8
    /// 255 = ozel / son kullanilan.
    public static let customIndex: UInt8 = 255
    public static let defaultQ = 100
    public static let unspecifiedType: UInt8 = 255

    public enum Format: Sendable { case multiEq2, multiEq
        public var opcode: UInt8 { self == .multiEq2 ? 0x22 : 0x20 }
        var bandSize: Int { self == .multiEq2 ? 7 : 6 }
    }

    /// 10 banda sinirlar: eksikler 0, fazlalar atilir, her deger -8...8.
    public static func normalized(_ gains: [Int]) -> [Int] {
        (0..<frequencies.count).map { i in
            i < gains.count ? min(max(gains[i], gainRange.lowerBound), gainRange.upperBound) : 0
        }
    }

    private static func le16(_ v: Int) -> [UInt8] {
        let u = UInt16(bitPattern: Int16(clamping: v))
        return [UInt8(u & 0xFF), UInt8(u >> 8)]
    }

    /// Cihaza sirayla yazilacak paketler (tek paket).
    public static func packets(gains: [Int], eqIndex: UInt8 = customIndex, format: Format = .multiEq2) -> [[UInt8]] {
        var body: [UInt8] = [eqIndex] + le16(0)
        for (f, g) in zip(frequencies, normalized(gains)) {
            body += le16(f) + le16(g * 100) + le16(defaultQ)
            if format == .multiEq2 { body.append(unspecifiedType) }
        }
        return [QcyPacket.pack(opcode: format.opcode, body)]
    }
}
