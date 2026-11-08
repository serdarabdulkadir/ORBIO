// AirPods / Beats "Proximity Pairing" BLE reklam cozucu (Continuity tipi 0x07).
// Yontem kaynagi: furiousMAC/continuity (messages/proximity_pairing.md) ve
// Martin vd. PETS arastirmalari. Kod bagimsiz yazildi; GPL projelerden kopya yok.
// Son 16 bayt sifreli: cozulmez, yalnizca atlanir.

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
}

public enum ProximityPairingParser {
    public static let appleCompanyID: UInt16 = 0x004C
    static let messageType: UInt8 = 0x07
    static let expectedLength: UInt8 = 0x19 // 25 bayt yuk

    /// Bilinen model kimlikleri (kucuk; eksik model nil ad dondurur).
    static let knownModels: [UInt16: String] = [
        0x2002: "AirPods (1. nesil)",
        0x200F: "AirPods (2. nesil)",
        0x2013: "AirPods (3. nesil)",
        0x200E: "AirPods Pro",
        0x2014: "AirPods Pro (2. nesil)",
        0x200A: "AirPods Max",
    ]

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
        // Kulakta bitleri (deneysel): 0x02 birincil, 0x08 ikincil.
        let inEarA = (status & 0x08) != 0
        let inEarB = (status & 0x02) != 0

        return ProximityPairingInfo(
            model: model,
            modelName: knownModels[model],
            rawStatus: status,
            left: flipped ? podB : podA,
            right: flipped ? podA : podB,
            caseBattery: BatteryLevel(nibble: b[5] & 0x0F),
            leftCharging: flipped ? chargeB : chargeA,
            rightCharging: flipped ? chargeA : chargeB,
            caseCharging: (chargeBits & 0x04) != 0,
            leftInEar: flipped ? inEarB : inEarA,
            rightInEar: flipped ? inEarA : inEarB,
            lidCounter: b[6],
            color: b[7]
        )
    }
}
