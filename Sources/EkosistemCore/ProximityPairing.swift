// AirPods / Beats "Proximity Pairing" BLE reklam cozucu (Continuity tipi 0x07).
// Yontem kaynagi: furiousMAC/continuity (messages/proximity_pairing.md) ve
// Martin vd. PETS arastirmalari. Kod bagimsiz yazildi; GPL projelerden kopya yok.
// Son 16 bayt sifreli: cozulmez, yalnizca atlanir.
// Model kimlikleri: gorunum sirasi (big-endian) bayt dizisi, ornek AirPods Pro = 0E 20 -> 0x0E20.
// Kimlik / yetenek tablosu icin kaynaklar ve dogrulama durumu: docs/airpods.md.

import Foundation

/// Pil seviyesi; 0...10 araligi x10 yuzde, 15 (0xF) "bilinmiyor".
public enum BatteryLevel: Equatable, Sendable {
    case percent(Int)
    case unknown

    init(nibble: UInt8) {
        switch nibble {
        case 0...10: self = .percent(Int(nibble) * 10)
        default: self = .unknown
        }
    }
}

public struct ProximityPairingInfo: Equatable, Sendable {
    public let model: UInt16
    public let modelName: String?
    public let rawStatus: UInt8
    public let left: BatteryLevel
    public let right: BatteryLevel
    public let caseBattery: BatteryLevel
    public let leftCharging: Bool
    public let rightCharging: Bool
    public let caseCharging: Bool
    /// Deneysel: kendi cihazla dogrulanacak (docs/arastirma.md).
    public let leftInEar: Bool
    public let rightInEar: Bool
    public let lidCounter: UInt8
    public let color: UInt8
    /// Tek parca cihazlarin (Max, Solo, Studio...) tek pil degeri (alt nibble). [deneysel]
    public let headsetBattery: BatteryLevel
    /// Tek parca cihazda sarj (sarj nibble'inin bit 0'i). [deneysel]
    public let headsetCharging: Bool
    /// Durum bayti bit 5: AirPods Max'te "takili". Diger modellerde anlami yok. [deneysel]
    public let headsetWorn: Bool
    /// Durum bayti bit 4 / bit 2: bir / iki kulaklik kutuda. [deneysel]
    public let onePodInCase: Bool
    public let bothPodsInCase: Bool

    /// Katalogdaki model kaydi; bilinmeyen kimlik icin nil.
    public var modelInfo: AppleModel? { AppleModelCatalog.model(forID: model) }
}

public enum ProximityPairingParser {
    public static let appleCompanyID: UInt16 = 0x004C
    static let messageType: UInt8 = 0x07
    static let expectedLength: UInt8 = 0x19 // 25 bayt yuk

    /// Bilinen model kimliklerinin adlari (katalogdan turetilir; eksik model nil ad dondurur).
    static var knownModels: [UInt16: String] {
        Dictionary(uniqueKeysWithValues: AppleModelCatalog.all.map { ($0.id, $0.name) })
    }

    /// `manufacturerData`: CoreBluetooth `CBAdvertisementDataManufacturerDataKey` degeri
    /// (ilk 2 bayt sirket kimligi, little-endian).
    public static func parse(manufacturerData data: [UInt8]) -> ProximityPairingInfo? {
        guard data.count >= 2 else { return nil }
        let company = UInt16(data[0]) | (UInt16(data[1]) << 8)
        guard company == appleCompanyID else { return nil }
        return parse(continuityPayload: Array(data.dropFirst(2)))
    }

    /// `p`: sirket kimligi sonrasi Continuity yuku. Birden fazla TLV olabilir; tip 0x07 aranir.
    public static func parse(continuityPayload p: [UInt8]) -> ProximityPairingInfo? {
        var i = 0
        while i + 1 < p.count {
            let type = p[i], len = Int(p[i + 1])
            let start = i + 2
            guard start + len <= p.count else { return nil }
            if type == messageType {
                return decodeBody(Array(p[start..<start + len]))
            }
            i = start + len
        }
        return nil
    }

    static func decodeBody(_ b: [UInt8]) -> ProximityPairingInfo? {
        // b[0]=onek 0x01, b[1..2]=model (big-endian gorunum), b[3]=durum,
        // b[4]=pil (ust/alt nibble), b[5]=sarj bitleri (ust nibble) + kutu pili (alt nibble),
        // b[6]=kapak sayaci, b[7]=renk, b[8]=0x00, b[9...]=sifreli.
        guard b.count >= 9, b[0] == 0x01 else { return nil }
        let model = (UInt16(b[1]) << 8) | UInt16(b[2])
        let status = b[3]
        // Durum bayti bit 5: "birincil kulaklik soldaki" (cevirme). Deneysel.
        let flipped = (status & 0x20) != 0
        let podA = BatteryLevel(nibble: b[4] >> 4)
        let podB = BatteryLevel(nibble: b[4] & 0x0F)
        let chargeBits = b[5] >> 4
        let chargeA = (chargeBits & 0x02) != 0
        let chargeB = (chargeBits & 0x01) != 0
        // Kulakta bitleri [deneysel]: durum bit 3 ve bit 1. Hangisinin sol oldugu: (cevirme degeri) XOR
        // (bit 6 = "reklami yayinlayan kulaklik kutuda"). Sozlesme: capod davranisiyla uyumlu, kendi cihazda dogrulanacak.
        let thisInCase = (status & 0x40) != 0
        let inEar3 = (status & 0x08) != 0
        let inEar1 = (status & 0x02) != 0
        let leftUsesBit3 = (!flipped) != thisInCase
        let inEarA = inEar3
        let inEarB = inEar1

        return ProximityPairingInfo(
            model: model,
            modelName: AppleModelCatalog.model(forID: model)?.name,
            rawStatus: status,
            left: flipped ? podB : podA,
            right: flipped ? podA : podB,
            caseBattery: BatteryLevel(nibble: b[5] & 0x0F),
            leftCharging: flipped ? chargeB : chargeA,
            rightCharging: flipped ? chargeA : chargeB,
            caseCharging: (chargeBits & 0x04) != 0,
            leftInEar: leftUsesBit3 ? inEarA : inEarB,
            rightInEar: leftUsesBit3 ? inEarB : inEarA,
            lidCounter: b[6],
            color: b[7],
            headsetBattery: BatteryLevel(nibble: b[4] & 0x0F),
            headsetCharging: (chargeBits & 0x01) != 0,
            headsetWorn: (status & 0x20) != 0,
            onePodInCase: (status & 0x10) != 0,
            bothPodsInCase: (status & 0x04) != 0
        )
    }
}

// MARK: - Model katalogu (AirPods / Beats)
// Kimlikler: Proximity Pairing 0x07 reklamindaki 16-bit model (gorunum sirasi). Kaynaklar ve dogrulama durumu
// docs/airpods.md'de. Yetenekler topluluk belgelerinden (capod PodModel tablosu, LibrePods belgeleri: yalnizca
// olgu okundu, kod kopyalanmadi) ve Apple destek sayfalarindan; cihazda sinanmadi.

public enum AppleFamily: String, Sendable, Codable {
    case airpods, beats
}

/// Pil / kulaklik duzeni: `trueWireless` = sol + sag (+ kutu); `headset` = tek parca ya da boyun kablolu (tek pil).
public enum AppleForm: String, Sendable, Codable {
    case trueWireless, headset
}

/// Bir bilginin dayanagi.
public enum AppleVerification: String, Sendable, Codable {
    /// En az iki bagimsiz kaynakta (topluluk listeleri / yayimlanmis arastirma) tutarli; cihazimizda henuz sinanmadi.
    case dogrulandiKaynak
    /// Tek kaynak ya da cikarim; kendi cihazda dogrulanmadan guvenilmez.
    case deneysel
}

public struct AppleCapabilities: OptionSet, Sendable, Codable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    /// Kapali / gurultu engeli / seffaf secimi.
    public static let noiseControl = AppleCapabilities(rawValue: 1 << 0)
    /// "Uyarlanir" modu (noiseControl ile birlikte).
    public static let adaptive = AppleCapabilities(rawValue: 1 << 1)
    public static let earDetection = AppleCapabilities(rawValue: 1 << 2)
    public static let caseBattery = AppleCapabilities(rawValue: 1 << 3)
    /// Konusma farkindaligi (Conversational Awareness).
    public static let conversationAwareness = AppleCapabilities(rawValue: 1 << 4)
    /// Tek kulaklikla gurultu engeli secenegi.
    public static let oneBudANC = AppleCapabilities(rawValue: 1 << 5)
    /// Uyarlanir mod gurultu seviyesi (ozel gurultu kontrolu, AAP 0x2E).
    public static let adaptiveStrength = AppleCapabilities(rawValue: 1 << 6)
    public static let personalizedVolume = AppleCapabilities(rawValue: 1 << 7)
    public static let sleepDetection = AppleCapabilities(rawValue: 1 << 8)
}

public struct AppleModel: Equatable, Sendable {
    public let id: UInt16
    public let name: String
    public let family: AppleFamily
    public let form: AppleForm
    public let capabilities: AppleCapabilities
    /// Model kimliginin (reklam kodu) dayanagi.
    public let idVerification: AppleVerification
    /// AAP kontrol kanalinin bu modelde calistiginin dayanagi: `dogrulandiKaynak` = topluluk bu modelde calistirdi;
    /// `deneysel` = protokol genel ama bu modelde bildirilmemis (Beats'te kendi protokolleri olabilir).
    public let aapVerification: AppleVerification
    /// Apple model numaralari (AAP cihaz bilgisindeki "A3048" gibi); bos olabilir.
    public let modelNumbers: [String]

    /// Bu modelde secilebilir dinleme modlari; ses modu yoksa bos.
    public var listeningModes: [ListeningMode] {
        guard capabilities.contains(.noiseControl) else { return [] }
        var modes: [ListeningMode] = [.kapali, .gurultuEngeli, .seffaf]
        if capabilities.contains(.adaptive) { modes.append(.uyarlanir) }
        return modes
    }

    public func supports(_ capability: AppleCapabilities) -> Bool { capabilities.contains(capability) }
    public var hasCase: Bool { capabilities.contains(.caseBattery) }
}

public enum AppleModelCatalog {
    private typealias C = AppleCapabilities
    private static let plain: C = [.earDetection, .caseBattery]
    private static let pro1: C = [.noiseControl, .oneBudANC, .earDetection, .caseBattery]
    private static let pro2: C = [.noiseControl, .adaptive, .conversationAwareness, .oneBudANC, .adaptiveStrength,
                                  .personalizedVolume, .sleepDetection, .earDetection, .caseBattery]
    private static let beatsANC: C = [.noiseControl]

    private static func m(_ id: UInt16, _ name: String, _ family: AppleFamily, _ form: AppleForm, _ caps: C,
                          id idV: AppleVerification, aap aapV: AppleVerification = .deneysel,
                          numbers: [String] = []) -> AppleModel {
        AppleModel(id: id, name: name, family: family, form: form, capabilities: caps,
                   idVerification: idV, aapVerification: aapV, modelNumbers: numbers)
    }

    /// Tum bilinen modeller. `dogrulandiKaynak` kimlikleri: capod model tablosu + furiousMAC / eski topluluk listeleri
    /// ile tutarli; `deneysel`: yalniz capod tablosu (docs/airpods.md).
    public static let all: [AppleModel] = [
        // AirPods
        m(0x0220, "AirPods (1. nesil)", .airpods, .trueWireless, plain, id: .dogrulandiKaynak, numbers: ["A1523", "A1722"]),
        m(0x0F20, "AirPods (2. nesil)", .airpods, .trueWireless, plain, id: .dogrulandiKaynak, numbers: ["A2031", "A2032"]),
        m(0x1320, "AirPods (3. nesil)", .airpods, .trueWireless, plain, id: .dogrulandiKaynak, numbers: ["A2564", "A2565"]),
        m(0x1920, "AirPods 4", .airpods, .trueWireless, plain.union(.sleepDetection), id: .deneysel,
          numbers: ["A3050", "A3053", "A3054"]),
        m(0x1B20, "AirPods 4 (ANC)", .airpods, .trueWireless, pro2,
          id: .deneysel, numbers: ["A3055", "A3056", "A3057"]),
        m(0x0E20, "AirPods Pro", .airpods, .trueWireless, pro1, id: .dogrulandiKaynak, aap: .dogrulandiKaynak,
          numbers: ["A2083", "A2084"]),
        m(0x1420, "AirPods Pro (2. nesil, Lightning)", .airpods, .trueWireless, pro2, id: .dogrulandiKaynak,
          numbers: ["A2698", "A2699", "A2931"]),
        m(0x2420, "AirPods Pro (2. nesil, USB-C)", .airpods, .trueWireless, pro2, id: .deneysel,
          aap: .dogrulandiKaynak, numbers: ["A3047", "A3048", "A3049"]),
        m(0x2720, "AirPods Pro 3", .airpods, .trueWireless, pro2, id: .deneysel, aap: .dogrulandiKaynak),
        m(0x0A20, "AirPods Max (Lightning)", .airpods, .headset, [.noiseControl, .earDetection], id: .dogrulandiKaynak,
          numbers: ["A2096"]),
        m(0x1F20, "AirPods Max (USB-C)", .airpods, .headset, [.noiseControl, .earDetection], id: .deneysel,
          numbers: ["A3184"]),
        m(0x2D20, "AirPods Max 2", .airpods, .headset,
          [.noiseControl, .adaptive, .conversationAwareness, .adaptiveStrength, .personalizedVolume, .earDetection],
          id: .deneysel),
        m(0x3620, "AirPods (5. nesil)", .airpods, .trueWireless,
          [.noiseControl, .adaptive, .conversationAwareness, .adaptiveStrength, .earDetection, .caseBattery],
          id: .deneysel),
        m(0x3020, "AirPods (5. nesil, kablosuz kutu)", .airpods, .trueWireless,
          [.noiseControl, .adaptive, .conversationAwareness, .adaptiveStrength, .earDetection, .caseBattery],
          id: .deneysel),
        // Beats
        m(0x0320, "Powerbeats3", .beats, .headset, [], id: .dogrulandiKaynak),
        m(0x0D20, "Powerbeats4", .beats, .headset, [], id: .deneysel),
        m(0x0520, "BeatsX", .beats, .headset, [], id: .dogrulandiKaynak),
        m(0x0620, "Beats Solo3", .beats, .headset, [], id: .dogrulandiKaynak),
        // Yalniz ilk bayt (0x09) kaynakta dogrulanmis; ikinci bayt ailenin ortak 0x20 degeri varsayildi.
        m(0x0920, "Beats Studio3", .beats, .headset, beatsANC, id: .deneysel),
        m(0x0B20, "Powerbeats Pro", .beats, .trueWireless, plain, id: .dogrulandiKaynak),
        m(0x0C20, "Beats Solo Pro", .beats, .headset, beatsANC, id: .dogrulandiKaynak),
        m(0x1020, "Beats Flex", .beats, .headset, [], id: .dogrulandiKaynak),
        m(0x1120, "Beats Studio Buds", .beats, .trueWireless, beatsANC.union(.caseBattery), id: .dogrulandiKaynak),
        m(0x1220, "Beats Fit Pro", .beats, .trueWireless, beatsANC.union([.earDetection, .caseBattery]),
          id: .dogrulandiKaynak),
        m(0x1620, "Beats Studio Buds+", .beats, .trueWireless, beatsANC.union(.caseBattery), id: .deneysel),
        m(0x1720, "Beats Studio Pro", .beats, .headset, beatsANC, id: .deneysel),
        m(0x1D20, "Powerbeats Pro 2", .beats, .trueWireless,
          beatsANC.union([.earDetection, .caseBattery, .sleepDetection]), id: .deneysel),
        m(0x2520, "Beats Solo 4", .beats, .headset, [], id: .deneysel),
        m(0x2620, "Beats Solo Buds", .beats, .trueWireless, [.caseBattery], id: .deneysel),
        m(0x3820, "Beats 360", .beats, .headset, beatsANC, id: .deneysel),
    ]

    private static let byID: [UInt16: AppleModel] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func model(forID id: UInt16) -> AppleModel? { byID[id] }

    /// AAP cihaz bilgisindeki Apple model numarasindan ("A3048") modeli bulur; bos / bilinmeyen icin nil.
    public static func model(forModelNumber number: String) -> AppleModel? {
        let key = number.trimmingCharacters(in: .whitespaces).uppercased()
        guard !key.isEmpty else { return nil }
        return all.first { $0.modelNumbers.contains(key) }
    }
}
