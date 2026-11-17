// Panelin "Telefon" gorunumu: bagli telefon, arama karti, yeni arama, son aramalar, kisi arama.
// Veri yalnizca eslesmis ve bagli telefondan gelir; yoksa bos durum gosterilir.
import SwiftUI
import EkosistemCore

enum PanelTab: String, CaseIterable {
    case kulaklik, telefon
    var title: String { self == .kulaklik ? "Kulaklık" : "Telefon" }
    var symbol: String { self == .kulaklik ? "earbuds" : "smartphone" }
}

/// "Kulaklık | Telefon" 2'li segment: cam hap, kayan secim.
struct PanelSegment: View {
    let selection: PanelTab
    let ringing: Bool
    let onSelect: (PanelTab) -> Void
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let on = tab == selection
                Button { onSelect(tab) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 12, weight: .semibold))
                        Text(tab.title).font(.system(size: 12, weight: .semibold))
                        if tab == .telefon && ringing {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                        }
                    }
                    .foregroundStyle(on ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if on { Capsule().fill(.white).matchedGeometryEffect(id: "secim", in: ns) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .glassCapsule()
        .animation(Motion.spring(reduceMotion), value: selection)
    }
}

/// Kirmizi / yesil dolgulu arama dugmesi.
struct CallActionButton: View {
    let title: String
    let symbol: String
    let color: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Capsule().fill(color.opacity(enabled ? 1 : 0.35)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

/// Arama durumu (panelde ve yuzen kartta ortak): ad/numara, durum ya da sure, eylemler.
struct CallCardBody: View {
    let phone: PhoneModel

    var body: some View {
        let call = phone.snapshot.call
        let canManage = phone.snapshot.allows(.cagriYonetimi)
        let contact = phone.contact(for: call.numara)
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let contact {
                    ContactAvatar(record: contact, size: 40)
                } else if ContactText.initial(call.kisiAdi ?? "") != nil {
                    ContactAvatar(record: nil, name: call.kisiAdi, size: 40)
                } else {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(Color.blue))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(call)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    subtitle(call).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if phone.snapshot.isRinging {
                if canManage {
                    HStack(spacing: 8) {
                        CallActionButton(title: "Reddet", symbol: "phone.down.fill", color: .red) { phone.reject() }
                        CallActionButton(title: "Cevapla", symbol: "phone.fill", color: .green) { phone.answer() }
                    }
                } else {
                    Text("Yanıtlamak için telefonda \"Çağrı yönetimi\" iznini açın.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if canManage {
                let hanging = phone.hangupPhase == .kapatiliyor
                CallActionButton(title: hanging ? "Kapatılıyor…" : "Kapat", symbol: "phone.down.fill",
                                 color: .red, enabled: !hanging) { phone.hangup() }
            }
            if let error = phone.callError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { phone.dismissCallError() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Kapat")
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15)))
            }
            Text("Ses telefonda ya da kulaklığınızda kalır; bu Mac'in mikrofonu ve hoparlörü kullanılmaz.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if call.durum != .bosta {
                Label("Görüşme sırasında kulaklığı telefona geçirin; görüşme bitince Mac'e dönmeyi önereceğiz. Otomatik geçiş için Ayarlar'daki kuralı kullanın.",
                      systemImage: "earbuds")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func title(_ call: CallState) -> String {
        phone.contact(for: call.numara)?.ad ?? call.kisiAdi ?? call.numara ?? "Bilinmeyen numara"
    }

    @ViewBuilder
    private func subtitle(_ call: CallState) -> some View {
        let who = phone.phoneName
        switch call.durum {
        case .caliyor: Text(call.yon == .gelen ? "\(who) üzerinden gelen arama" : "\(who) çalıyor")
        case .araniyor: Text("Aranıyor…")
        case .acik:
            if let start = phone.callStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let t = max(0, Int(ctx.date.timeIntervalSince(start)))
                    Text(String(format: "%02d:%02d", t / 60, t % 60)).monospacedDigit()
                }
            } else {
                Text("Görüşme sürüyor")
            }
        case .bosta: Text("")
        }
    }
}

struct PhoneView: View {
    let model: AppModel
    private var phone: PhoneModel { model.phone }

    var body: some View {
        VStack(spacing: 12) {
            if let code = phone.sasCode {
                PairingView(phone: phone, code: code)
            }
            if phone.keyMismatch { mismatchRow }
            KeychainStatusRow(phone: phone)
            if !phone.isPaired {
                unpairedState
            } else {
                phoneTile
                if phone.isConnected {
                    if phone.snapshot.isInCall { callCard }
                    NowPlayingCard(phone: phone, earbudOnBoth: earbudOnBoth)
                    PhoneVolumeCard(phone: phone)
                    PhoneContactsTile(phone: phone)
                } else {
                    disconnectedState
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: phone.isConnected)
        .animation(.easeOut(duration: 0.2), value: phone.snapshot.call)
        .onAppear { model.startPhoneOnDemand() }
    }

    // MARK: Karolar

    private var phoneTile: some View {
        HStack(spacing: 10) {
            Image(systemName: "smartphone")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36).background(Circle().fill(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(phone.phoneName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    if phone.isConnected { Circle().fill(Color.green).frame(width: 5, height: 5) }
                    Text(phone.isConnected ? (phone.connectionPath == .bluetooth ? "Bağlı · Bluetooth" : "Bağlı · Wi-Fi") : "Bağlı değil")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if phone.isConnected && phone.connectionPath == .bluetooth {
                    Text("Yalnız Bluetooth, dosya aktarımı kapalı")
                        .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if phone.isConnected, let s = phone.snapshot.phone {
                HStack(spacing: 8) {
                    Image(systemName: "cellularbars", variableValue: Double(max(0, min(4, s.sinyal))) / 4)
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .accessibilityLabel("Sinyal \(s.sinyal) / 4")
                    HStack(spacing: 2) {
                        if s.sarj { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(.green) }
                        Text(Format.percent(s.pil))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(s.pil <= LowBatteryMonitor.alertThreshold ? Color.red : Color.primary)
                    }
                }
            }
        }
        .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCapsule()
        .accessibilityElement(children: .combine)
    }

    /// Kulaklik hem bu Mac'e hem telefona bagli mi.
    private var earbudOnBoth: Bool {
        phone.snapshot.earbuds.values.contains { $0.baglanti == .telefon }
            && model.engine.devices.contains { $0.state == .bagliBuMac }
    }

    private var callCard: some View {
        CallCardBody(phone: phone)
            .padding(14)
            .glassTile(cornerRadius: 22)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Bos durumlar

    private var unpairedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "smartphone").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text("Telefonu eşle").font(.system(size: 14, weight: .semibold))
            Text("\"Telefonu eşle\" ile 6 haneli kod üretin, telefondaki ORBIO'da bu Mac'i seçip kodu girin; sonra iki ekranda görünen onay kodunu karşılaştırın. İki cihaz aynı Wi-Fi ağında olmalıdır.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if phone.sasCode == nil { PairingCodeCard(phone: phone) }
            listenerNote
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassTile()
    }

    private var disconnectedState: some View {
        VStack(spacing: 8) {
            Text("Telefon şu an bağlı değil.").font(.system(size: 13, weight: .semibold))
            Text("Telefonun aynı Wi-Fi ağında olduğundan ve uygulamanın açık olduğundan emin olun; bağlantı kendiliğinden yeniden kurulur.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            listenerNote
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .glassTile()
    }

    @ViewBuilder
    private var listenerNote: some View {
        switch phone.listenerStatus {
        case .yerelAgReddedildi:
            VStack(spacing: 6) {
                Label("Yerel Ağ izni reddedildi", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                Text("Telefon bu Mac'i ağda bulamaz. Sistem Ayarları > Gizlilik ve Güvenlik > Yerel Ağ bölümünden ORBIO'ya izin verin.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Sistem Ayarları'nda aç") { model.openLocalNetworkPrivacySettings() }
                    .buttonStyle(.link).font(.system(size: 12))
            }
        case .hata(let text):
            Label("Ağ dinleyicisi çalışmıyor: \(text)", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.orange).multilineTextAlignment(.center)
        case .durdu:
            Text("Telefon kanalı kapalı (Ayarlar > Telefon).").font(.system(size: 11)).foregroundStyle(.secondary)
        case .baslatiliyor, .dinliyor:
            EmptyView()
        }
    }

    private var mismatchRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Eşleşme anahtarı değişti", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
            Text("Eşleşmiş telefondan farklı bir anahtarla bağlanma denendi ve reddedildi. Telefonu değiştirdiyseniz Ayarlar > Telefon'dan eşleşmeyi kaldırıp yeniden eşleyin; aksi halde ağınızda başka biri deniyor olabilir.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Kapat") { phone.dismissKeyMismatch() }.buttonStyle(.link).font(.system(size: 11))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: 20)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
