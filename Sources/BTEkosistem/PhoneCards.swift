// Yuzen kartlar: gelen arama, "Baglandi" onayi. Yaklasma karti ile ayni cam dili ve panel altyapisi.
import SwiftUI
import Observation
import EkosistemCore

/// Gelen arama bildirim karti (kapanma/cevaplama sonrasi AppModel kapatir).
struct IncomingCallCardView: View {
    let phone: PhoneModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Gelen arama").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.system(size: 15)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Kapat")
            }
            CallCardBody(phone: phone)
        }
        .padding(14)
        .frame(width: 360)
        .glassTile(cornerRadius: 28)
    }
}

/// Kulaklik bu Mac'e baglandiginda ~3 sn gorunen kart.
@MainActor
@Observable
final class ConnectedCardModel {
    var device: Device
    init(device: Device) { self.device = device }
}

struct ConnectedCardView: View {
    let model: ConnectedCardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let device = model.device
        let b = device.battery
        let stale = b?.isStale(at: Date()) ?? false
        VStack(spacing: 12) {
            Text(device.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            HStack(spacing: 0) {
                if let b, b.left == nil, b.right == nil, b.caseLevel == nil, let o = b.overall {
                    BatteryRing(title: "Pil", level: o, charging: b.isCharging(.genel), stale: stale).frame(maxWidth: .infinity)
                } else {
                    if let l = b?.left { BatteryRing(title: "Sol", level: l, charging: b?.leftCharging ?? false, stale: stale).frame(maxWidth: .infinity) }
                    if let r = b?.right { BatteryRing(title: "Sağ", level: r, charging: b?.rightCharging ?? false, stale: stale).frame(maxWidth: .infinity) }
                    if let c = b?.caseLevel { BatteryRing(title: "Kutu", level: c, charging: b?.caseCharging ?? false, stale: stale).frame(maxWidth: .infinity) }
                }
            }
            .frame(minHeight: 54)
            Label("Bağlandı", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.green)
        }
        .padding(16)
        .frame(width: 360, height: 220)
        .glassTile(cornerRadius: 36)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.device.battery)
    }
}

/// Eslesme dosyalari (kimlik, pin) yukleme durumu (okuma arka planda; arayuz donmaz). Hazir/bosta iken gorunmez.
struct KeychainStatusRow: View {
    let phone: PhoneModel

    var body: some View {
        switch phone.keychainState {
        case .bosta, .hazir:
            EmptyView()
        case .bekleniyor, .yavasBekleniyor, .reddedildi:
            let denied = phone.keychainState == .reddedildi
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if denied {
                        Image(systemName: "lock.trianglebadge.exclamationmark.fill").foregroundStyle(.orange)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(denied ? "Eşleşme dosyası okunamadı" : "Eşleşme bilgisi yükleniyor")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(denied ? "~/Library/Application Support/BTrack/peer klasörünün izinlerini kontrol edin." : "Birkaç saniye sürebilir.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if phone.keychainState != .bekleniyor {
                    Button("Tekrar dene") { phone.retryKeychain() }.buttonStyle(.link).font(.footnote)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassTile(cornerRadius: 22)
        }
    }
}

/// "Şimdi çalıyor": telefondaki medya oturumu ve uzaktan kontrol düğmeleri (komut telefona media.cmd gider).
struct NowPlayingCard: View {
    let phone: PhoneModel
    let earbudOnBoth: Bool

    var body: some View {
        let m = phone.snapshot.media
        let active = m?.oturum ?? false
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Şimdi çalıyor").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if earbudOnBoth, m?.caliyor == true {
                    Text("Telefondan çalıyor").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if active, let m {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.baslik ?? m.uygulama ?? "Medya").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let a = m.sanatci { Text(a).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                    if let u = m.uygulama, m.baslik != nil { Text(u).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1) }
                }
                HStack(spacing: 22) {
                    Spacer()
                    button("backward.fill", "Önceki", MediaCmd.onceki)
                    button(m.caliyor ? "pause.fill" : "play.fill", m.caliyor ? "Duraklat" : "Oynat", MediaCmd.oynatDuraklat)
                    button("forward.fill", "Sonraki", MediaCmd.sonraki)
                    Spacer()
                }
            } else {
                Text("Telefonda çalan yok").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: 22)
    }

    private func button(_ symbol: String, _ label: String, _ cmd: String) -> some View {
        Button { phone.sendMedia(cmd) } label: { Image(systemName: symbol).font(.system(size: 16)) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// "Telefon sesi": telefonun medya sesi kaydiricisi + sessiz dugmesi (vol.set telefona gider).
struct PhoneVolumeCard: View {
    let phone: PhoneModel

    var body: some View {
        let v = phone.snapshot.phoneVolume
        let muted = v?.sessiz ?? false
        let level = Double(v?.seviye ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            Text("Telefon sesi").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Slider(value: Binding(get: { level }, set: { phone.setPhoneVolume(Int($0.rounded())) }), in: 0...100)
                    .disabled(v == nil)
                    .accessibilityLabel("Telefon sesi")
                    .accessibilityValue("%\(Int(level))")
                Button { phone.setPhoneMuted(!muted) } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(v == nil)
                .accessibilityLabel(muted ? "Telefon sesini aç" : "Telefonu sessize al")
            }
            if v == nil { Text("Telefon ses bilgisi bekleniyor").font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: 22)
    }
}
