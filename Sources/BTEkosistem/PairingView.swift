// Eslesme onayi: Mac ve telefondaki 6 haneli kod ayni mi? (MITM korumasi, docs/telefon-kanali.md bolum 6)
import SwiftUI

struct PairingView: View {
    let phone: PhoneModel
    let code: String

    private var spaced: String {
        code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Telefon eşleşmek istiyor").font(.system(size: 13, weight: .semibold))
            Text(spaced)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .accessibilityLabel("Eşleşme kodu \(code.map(String.init).joined(separator: " "))")
            Text("Telefonda görünen kod bununla aynı mı? Farklıysa ağda biri araya girmiş olabilir; eşleşmeyin.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { phone.confirmSAS(accepted: false) } label: {
                    Text("Farklı").font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .glassCapsule(interactive: true).contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                Button { phone.confirmSAS(accepted: true) } label: {
                    Text("Aynı").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Capsule().fill(Color.green)).contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassTile(cornerRadius: 22)
    }
}

/// Panel kapaliyken gelen eslesme isteginin yuzen karti.
struct PairingCardView: View {
    let phone: PhoneModel
    var body: some View {
        Group {
            if let code = phone.sasCode { PairingView(phone: phone, code: code) }
        }
        .padding(8)
        .frame(width: 360)
    }
}

/// "Telefonu esle": Mac'te uretilen tek kullanimlik kodu buyuk ve geri sayimla gosterir (telefonda girilir).
struct PairingCodeCard: View {
    let phone: PhoneModel

    var body: some View {
        VStack(spacing: 10) {
            if let code = phone.pairingCode, let expires = phone.pairingExpiresAt {
                Text("Bu kodu telefondaki ORBIO'ya girin").font(.system(size: 13, weight: .semibold))
                Text(code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code)
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .accessibilityLabel("Eşleşme kodu \(code.map(String.init).joined(separator: " "))")
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(expires.timeIntervalSince(ctx.date).rounded(.up)))
                    Text(String(format: "%d:%02d içinde geçerli", left / 60, left % 60))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                }
                Text("Telefonda Telefon sekmesi > Mac'i seçin > Eşleştir. Kod tek kullanımlıktır; 3 yanlış denemede iptal olur.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("İptal") { phone.cancelPairing() }.buttonStyle(.link).font(.system(size: 12))
            } else {
                if let note = phone.pairingNote {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                Button { phone.beginPairing() } label: {
                    Text("Telefonu eşle")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(Capsule().fill(Color.accentColor)).contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassTile(cornerRadius: 22)
    }
}
