// Turkce arayuz metinleri ve simge eslemeleri (projede ceviri sistemi yok; tek yerde toplandi).
import SwiftUI
import EkosistemCore

extension DeviceState {
    var label: String {
        switch self {
        case .bagliBuMac: "Bu Mac'e bağlı"
        case .bagliTelefon: "Telefona bağlı"
        case .bagliDegil: "Bağlı değil"
        case .yakinda: "Yakınında"
        case .bilinmiyor: "Durum bilinmiyor"
        }
    }
}

extension ListeningMode {
    var label: String {
        switch self {
        case .kapali: "Kapalı"
        case .gurultuEngeli: "Gürültü engeli"
        case .seffaf: "Şeffaf"
        case .uyarlanir: "Uyarlanır"
        }
    }
}

extension QcyNoiseScene {
    var label: String {
        switch self {
        case .uyarlanir: "Uyarlanır"
        case .kapaliAlan: "Kapalı alan"
        case .yolculuk: "Yolculuk"
        case .gurultulu: "Gürültülü"
        case .ruzgarKarsiti: "Rüzgar karşıtı"
        }
    }
}

extension AutoSwitchRule {
    var label: String {
        switch self {
        case .hicbirZaman: "Hiçbir zaman"
        case .telefondaCagriGelince: "Telefonda çağrı gelince"
        case .medyaBaslayanCihaza: "Medya başlayan cihaza"
        }
    }
}

extension BatteryChannel {
    var label: String {
        switch self {
        case .sol: "Sol"
        case .sag: "Sağ"
        case .kutu: "Kutu"
        case .genel: "Pil"
        }
    }
}

extension Device {
    /// Kulaklik rozeti simgesi.
    /// Adindan kulak ici (TWS) oldugu anlasilan cihazlar: buds, pods, qcy, tws...
    private var isInEar: Bool {
        let n = name.lowercased()
        return ["buds", "pods", "qcy", "tws", "earbud", "melo", "air"].contains { n.contains($0) }
    }

    var symbol: String {
        switch profile {
        case .apple: "airpods.pro"
        case .tws: "earbuds"
        case .standart: isInEar ? "airpods.pro" : "headphones"
        }
    }
}

enum Format {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func percent(_ value: Int?) -> String { value.map { "%\($0)" } ?? "--" }
}
