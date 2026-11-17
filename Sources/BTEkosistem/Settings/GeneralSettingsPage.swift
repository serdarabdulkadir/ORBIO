// Ayarlar > Genel: Bluetooth izni ve uygulama bilgisi.
import SwiftUI

struct GeneralSettingsPage: View {
    let model: AppModel

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        Form {
            Section("Bluetooth") {
                LabeledContent("Bluetooth izni") {
                    Label(model.permission.label,
                          systemImage: model.permission == .verildi ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.permission == .verildi ? Color.green : Color.orange)
                }
                if model.permission != .verildi {
                    Button("Sistem Ayarları'nda aç") { model.openBluetoothPrivacySettings() }
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            Section("Hakkında") {
                LabeledContent("Uygulama", value: "ORBIO")
                LabeledContent("Sürüm", value: version ?? "--")
                SettingsNote("Bluetooth kulaklıklarınız için pil, ses modu ve cihazlar arası geçiş.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Genel")
    }
}
