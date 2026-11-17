// QCY pil ozelligi (0008): 3 bayt = sol, sag, kutu; bit7 = sarj, alt 7 bit = yuzde (0 = okuma yok).
// Kaynak: resmi uygulama APK'si (docs/qcy-protokol-cozum.md bolum 1.2); MeloBuds Pro'da cihazda DOGRULANMADI.
// Gorev: GATT bagliyken reklam taramasi olmadan pil degeri (tarama cizirtiya yol acar).
import Foundation

public enum QcyBatteryCharacteristic {
    public static let uuid = "0008"

    public static func parse(_ bytes: [UInt8], at time: Date) -> BatteryReading? {
        guard bytes.count >= 3 else { return nil }
        func level(_ raw: UInt8) -> Int? { raw & 0x7F == 0 ? nil : min(Int(raw & 0x7F), 100) }
        let l = level(bytes[0]), r = level(bytes[1]), c = level(bytes[2])
        guard l != nil || r != nil || c != nil else { return nil }
        return BatteryReading(left: l, right: r, caseLevel: c,
                              leftCharging: bytes[0] & 0x80 != 0, rightCharging: bytes[1] & 0x80 != 0,
                              caseCharging: bytes[2] & 0x80 != 0, source: .markaOzel, timestamp: time)
    }
}

extension QcyBatteryCharacteristic {
    /// 0008 degerini, telefona iletilen "reklam" biciminde (1C 52 + 17 bayt) yeniden kurar: tarama kapaliyken
    /// telefon arayuzu de guncel pil gorur. `controlAddress`: "84:AC:60:20:9D:3A".
    public static func syntheticAdvertisement(_ bytes: [UInt8], controlAddress: String) -> [UInt8]? {
        guard bytes.count >= 3 else { return nil }
        let octets = controlAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard octets.count == 6 else { return nil }
        var d = [UInt8](repeating: 0, count: 17)
        d[5] = bytes[0]; d[6] = bytes[1]; d[7] = bytes[2]
        // QcyAdvertisement.parse adres sirasi: d12 d11 d13 d16 d15 d14
        d[12] = octets[0]; d[11] = octets[1]; d[13] = octets[2]
        d[16] = octets[3]; d[15] = octets[4]; d[14] = octets[5]
        return [0x1C, 0x52] + d
    }
}
