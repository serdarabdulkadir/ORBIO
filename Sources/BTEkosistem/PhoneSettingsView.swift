// Ayarlar > Telefon: eslesmis telefon, baglanti, telefondan gelen izinler, eslesmeyi kaldir.
import SwiftUI
import EkosistemCore

struct PhoneSettingsView: View {
    let model: AppModel
    @State private var confirmUnpair = false
    private var phone: PhoneModel { model.phone }

    var body: some View {
        GlassGroup(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Telefon")
                    .font(.system(size: 26, weight: .semibold))
                    .padding(.horizontal, 4).padding(.bottom, 4)

                if let code = phone.sasCode { PairingView(phone: phone, code: code) }
                else if !phone.isPaired { PairingCodeCard(phone: phone) }

                if phone.keyMismatch {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Eşleşme anahtarı değişti", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                        Text("Eşleşmiş telefondan farklı bir anahtarla bağlanma denendi ve reddedildi. Telefonu değiştirdiyseniz eşleşmeyi kaldırıp yeniden eşleyin; aksi halde ağınızda başka biri deniyor olabilir.")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Uyarıyı kapat") { phone.dismissKeyMismatch() }.buttonStyle(.link).font(.footnote)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassTile(cornerRadius: 22)
                }

                KeychainStatusRow(phone: phone)

                if let w = phone.storageWarning {
                    Text(w).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                toggleRow

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(get: { phone.bubbleEnabled }, set: { phone.bubbleEnabled = $0 })) {
                        Text("Arama baloncuğu").font(.system(size: 13, weight: .semibold))
                    }
                    .toggleStyle(.switch)
                    Text("Telefonda arama sürerken panel kapalı olsa bile ekranın sağ üstünde sürüklenebilir bir kapsül gösterir.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassTile(cornerRadius: 22)

                row("Eşleşmiş telefon") {
                    Text(phone.pin?.name ?? "Yok").foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                row("Bağlantı") { connectionLabel }
                row("Yerel ağda yayın") { listenerLabel }
                if phone.listenerStatus == .yerelAgReddedildi {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Yerel Ağ izni reddedildi: telefon bu Mac'i ağda bulamaz. Sistem Ayarları > Gizlilik ve Güvenlik > Yerel Ağ bölümünden ORBIO'ya izin verin.")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Sistem Ayarları'nda aç") { model.openLocalNetworkPrivacySettings() }
                            .buttonStyle(.link).font(.footnote)
                    }
                    .padding(.horizontal, 4)
                }

                Text("Telefondan gelen izinler")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.top, 8)
                permRow("Çağrı yönetimi", .cagriYonetimi, note: "Cevapla, reddet, kapat ve numara çevirme")
                permRow("Kişiler", .kisiler, note: "Rehber (ad, numara, fotoğraf, favori) sayfa sayfa şifreli kanaldan okunur; Mac diske yazmaz")
                permRow("Arama geçmişi", .aramaGecmisi, note: "Gelen, giden ve cevapsız aramalar")
                Text("İzinler telefondaki uygulamadan verilir ve varsayılan olarak kapalıdır. Kulaklık geçişi bu izinlere bağlı değildir.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mac'ten yapılan aramalarda ses telefonda ya da kulaklığınızda kalır; bu Mac'in mikrofonu ve hoparlörü kullanılmaz.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                if phone.isPaired {
                    Button { confirmUnpair = true } label: {
                        Text("Eşleşmeyi kaldır")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.red)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .glassCapsule(interactive: true).contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.horizontal, 4).padding(.top, 8)
                    .confirmationDialog("\(phone.phoneName) ile eşleşme kaldırılsın mı?", isPresented: $confirmUnpair) {
                        Button("Kaldır", role: .destructive) { phone.unpair() }
                        Button("Vazgeç", role: .cancel) {}
                    } message: {
                        Text("Telefonun anahtarı bu Mac'ten silinir. Yeniden bağlanmak için telefonda da eşleşmeyi kaldırıp yeniden eşlemeniz gerekir.")
                    }
                } else {
                    Text("\"Telefonu eşle\" ile kod üretin, telefondaki ORBIO'da bu Mac'i seçip kodu girin; ardından iki ekranda görünen onay kodunun aynı olduğunu onaylarsınız.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.startPhoneOnDemand() }
    }

    // MARK: Parcalar

    private var toggleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { phone.isEnabled }, set: { phone.setEnabled($0) })) {
                Text("Telefon kanalı").font(.system(size: 13, weight: .semibold))
            }
            .toggleStyle(.switch)
            Text("Kapalıyken Mac ağda yayın yapmaz ve telefon bağlanamaz.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: 22)
    }

    @ViewBuilder
    private var connectionLabel: some View {
        if phone.sasCode != nil {
            Label("Eşleşme onayı bekleniyor", systemImage: "hourglass").foregroundStyle(.orange)
        } else if phone.isConnected {
            Label("Bağlı", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Text("Bağlı değil").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var listenerLabel: some View {
        switch phone.listenerStatus {
        case .durdu: Text("Kapalı").foregroundStyle(.secondary)
        case .baslatiliyor: Text("Başlatılıyor…").foregroundStyle(.secondary)
        case .dinliyor: Label("Açık", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.secondary)
        case .yerelAgReddedildi: Label("Yerel Ağ izni yok", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .hata(let t): Text(t).foregroundStyle(.orange).lineLimit(2)
        }
    }

    private func permRow(_ title: String, _ p: PeerPermission, note: String) -> some View {
        let known = phone.isConnected && phone.snapshot.perm != nil
        let on = phone.snapshot.allows(p)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 12)
                if !known {
                    Text("Bilinmiyor").foregroundStyle(.secondary)
                } else {
                    Label(on ? "Açık" : "Kapalı", systemImage: on ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(on ? Color.green : Color.secondary)
                }
            }
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: 22)
    }

    private func row(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: 22)
    }
}
