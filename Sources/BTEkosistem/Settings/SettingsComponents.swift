// Ayarlar penceresi ortak parcalari: pil sutunlari, yetenek rozeti, bilgi notu.
import SwiftUI
import EkosistemCore

/// Sol / Sag / Kutu pil degerleri; bilinmeyen '--'. Yalnizca bilinen metrik gosterilir, uydurma yok.
struct SettingsBatteryColumns: View {
    let battery: BatteryReading?
    let showChannels: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let b = battery, !showChannels, b.left == nil, b.right == nil, b.caseLevel == nil, let o = b.overall {
                column("Pil", o, b.isCharging(.genel))
            } else {
                column("Sol", battery?.left, battery?.leftCharging ?? false)
                column("Sağ", battery?.right, battery?.rightCharging ?? false)
                column("Kutu", battery?.caseLevel, battery?.caseCharging ?? false)
            }
        }
    }

    private func column(_ title: String, _ level: Int?, _ charging: Bool) -> some View {
        let low = (level ?? 100) <= LowBatteryMonitor.alertThreshold
        return VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if charging { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green) }
                Text(Format.percent(level))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(level != nil && low ? Color.red : Color.primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(level.map { "yüzde \($0)" + (charging ? ", şarj oluyor" : "") } ?? "bilinmiyor")
    }
}

/// Satir altina dusen aciklama metni.
struct SettingsNote: View {
    let text: String
    var symbol: String?

    init(_ text: String, symbol: String? = nil) { self.text = text; self.symbol = symbol }

    var body: some View {
        Group {
            if let symbol { Label(text, systemImage: symbol) } else { Text(text) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
