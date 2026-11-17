// Ayarlar > Cihaz sayfasi: gruplu form bolumleri. Yalnizca cihazin dogruladigi yetenekler etkindir.
import SwiftUI
import EkosistemCore

struct DeviceSettingsPage: View {
    let model: AppModel
    let device: Device
    /// Cihaz unutulunca secimi sifirlamak icin.
    let onForget: () -> Void

    @State private var confirmForget = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var d: Device { device }
    private var q: QcyDeviceState { model.qcyState(for: d.id) }
    private var connected: Bool { d.state == .bagliBuMac }
    private var isQcy: Bool { model.isQcy(d) }

    var body: some View {
        Form {
            header
            if q.mode != nil || isQcy || q.wearing == nil { soundMode }
            if isQcy { equalizer }
            if isQcy || q.wearing != nil { detectionAndGame }
            if isQcy { touchControls }
            if isQcy { storageNote }
            autoSwitch
            forget
        }
        .formStyle(.grouped)
        .navigationTitle(d.name)
        .animation(Motion.ease(reduceMotion), value: q.mode)
    }

    // MARK: Ust kart

    private var header: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: d.symbol)
                    .font(.title)
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                    Label(d.state.label, systemImage: connected ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(connected ? Color.green : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48)
            .accessibilityElement(children: .combine)

            SettingsBatteryColumns(battery: d.battery, showChannels: isQcy || d.profile != .standart)
            LabeledContent("Son güncelleme") {
                Text(d.battery.map { Format.time.string(from: $0.timestamp) } ?? "--").monospacedDigit()
            }
            if isQcy { linkRow }
        }
    }

    @ViewBuilder
    private var linkRow: some View {
        let status = model.qcyLink(for: d.id)
        LabeledContent("Kontrol kanalı") {
            switch status {
            case .hazir:
                Label(model.isRemoteControlled(d.id) ? "Kontrol: telefon üzerinden" : "Bağlı", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            case .baglaniyor:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(QcyLinkNote.waitingText).foregroundStyle(.secondary) }
            case .kapali:
                Label("Kapalı", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
            }
        }
        if status == .kapali {
            SettingsNote(QcyLinkNote.closedText)
            Button("Tekrar dene") { model.retryQcyLink(d) }.frame(minHeight: 44, alignment: .leading)
        }
    }

    // MARK: Ses modu

    private var soundMode: some View {
        Section {
            if let mode = q.mode {
                Picker("Ses modu", selection: Binding(get: { mode }, set: { model.setListeningMode(d, $0) })) {
                    ForEach(d.availableListeningModes, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .disabled(!connected)

                if mode == .gurultuEngeli, isQcy {
                    Picker("Gürültü engeli türü", selection: Binding(
                        get: { q.scene ?? .uyarlanir }, set: { model.send(.scene($0), to: d) })) {
                        ForEach(QcyNoiseScene.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .disabled(!connected || q.scene == nil)
                }
                if mode == .seffaf, isQcy { transparencyPicker }
            } else if isQcy {
                LabeledContent("Ses modu") {
                    Text(model.qcyLink(for: d.id) == .kapali ? "Kontrol kanalı kapalı" : "Kulaklıktan veri bekleniyor…")
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Ses modu") { Text("--").foregroundStyle(.secondary) }
                SettingsNote("Bu cihazdan okunan ses ayarı yok.")
            }
        } header: {
            Text("Ses modu")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if q.mode != nil && !connected { SettingsNote("Ses ayarları için kulaklığın bu Mac'e bağlı olması gerekir.") }
                if d.profile == .apple { SettingsNote("Uyarlanır mod yalnızca Apple profilli cihazlarda kullanılabilir.") }
            }
        }
    }

    private var transparencyPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Şeffaflık seviyesi")
            Picker("Şeffaflık seviyesi", selection: Binding<Int?>(
                get: { q.transparencyLevel.flatMap { (1...5).contains($0) ? $0 : nil } },
                set: { if let v = $0 { model.send(.transparencyLevel(QcyTransparency.clamp(v)), to: d) } })) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .disabled(!connected)
            SettingsNote(q.transparencyLevel == nil
                         ? "Seviye kulaklıktan okunmadı (--)."
                         : "1 az, 5 çok. Değer yazıldıktan sonra kulaklıktan geri okunur.")
        }
    }

    // MARK: Ekolayzer

    private var equalizer: some View {
        Section {
            Picker("Hazır ayar", selection: Binding<QcyEqPreset?>(
                get: { q.eqPreset },
                set: { if let v = $0 { model.setEqPreset(d, v) } })) {
                if q.eqPreset == nil { Text("--").tag(QcyEqPreset?.none) }
                ForEach(QcyEqPreset.all, id: \.self) { Text($0.name).tag(Optional($0)) }
            }
            .disabled(!connected)
            .accessibilityLabel("Ekolayzer hazır ayarı")
            .accessibilityValue(q.eqPreset?.name ?? "bilinmiyor")
            if q.eqPreset == nil { SettingsNote("Seçili ayar kulaklıktan okunmadı (--).") }
            CustomEqEditor(enabled: connected) { model.setCustomEq(d, $0) }
        } header: {
            Text("Ekolayzer")
        }
    }

    // MARK: Algilama ve oyun

    private var detectionAndGame: some View {
        Section("Algılama ve oyun") {
            if let wearing = q.wearing {
                Toggle("Kulak algılama", isOn: Binding(
                    get: { wearing.enabled }, set: { model.send(.wearingDetection($0), to: d) }))
                    .disabled(!connected)
                SettingsNote("Kapalıyken kulaklığı çıkarmak ya da takmak müziği kendiliğinden durdurmaz / sürdürmez.")
            } else if d.isQcyVerified(.earDetection) {
                Toggle("Kulak algılama", isOn: Binding(
                    get: { q.earDetection ?? false }, set: { model.send(.earDetection($0), to: d) }))
                    .disabled(!connected || q.earDetection == nil)
                if q.earDetection == nil { SettingsNote("Durum kulaklıktan okunmadı (--).") }
            }
            if d.isQcyVerified(.gameMode) {
                Toggle("Oyun / düşük gecikme modu", isOn: Binding(
                    get: { q.gameMode ?? false }, set: { model.setGameMode(d, $0) }))
                    .disabled(!connected || q.gameMode == nil)
                if q.gameMode == nil { SettingsNote("Durum kulaklıktan okunmadı (--).") }
            }
        }
    }

    // MARK: Dokunmatik

    @ViewBuilder
    private var touchControls: some View {
        Section {
            Text("Dokunmatik kontroller").font(.headline)
            if q.keys == nil { SettingsNote("Tuş eşlemesi kulaklıktan okunmadı (--).") }
        }
        touchSection("Sol kulaklık", side: .left)
        touchSection("Sağ kulaklık", side: .right)
        if model.canRestoreTouch(d) {
            Section {
                Button("Önceki değere dön") { model.restoreTouch(d) }
                    .disabled(!connected).frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    private func touchSection(_ title: String, side: QcyTouchSide) -> some View {
        Section(title) {
            ForEach(QcyTouchGesture.allCases, id: \.self) { g in
                Picker(g.label, selection: Binding<QcyKeyFunction?>(
                    get: { q.keys?.function(side: side, gesture: g) },
                    set: { if let f = $0 { model.setTouch(d, side: side, gesture: g, function: f) } })) {
                    if q.keys?.function(side: side, gesture: g) == nil { Text("--").tag(QcyKeyFunction?.none) }
                    ForEach(QcyKeyFunction.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                .disabled(!connected)
            }
        }
    }

    private var storageNote: some View {
        Section {
            SettingsNote("Ayar kulaklığın kendisinde saklanır; başka cihaza takınca korunur.", symbol: "info.circle")
        }
    }

    // MARK: Otomatik gecis

    private var autoSwitch: some View {
        let s = model.settings(for: d.id)
        return Section {
            Picker("Otomatik geçiş", selection: Binding(
                get: { s.autoSwitch }, set: { v in model.update(d.id) { $0.autoSwitch = v } })) {
                ForEach(AutoSwitchRule.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .frame(minHeight: 32)
            SettingsNote("Otomatik geçiş sessiz değildir: kısa bildirim ve 30 saniyelik \"Geri al\" gösterilir.")
            Toggle("Yakınlık bildirimi", isOn: Binding(
                get: { s.proximityCard }, set: { v in model.update(d.id) { $0.proximityCard = v } }))
            SettingsNote("Kulaklık menzile girince ekranın ortasında pil kartı çıkar. Zaten bu Mac'e bağlıysa, ekran kilitliyse ya da son 60 saniyede gösterildiyse çıkmaz.")
        } header: {
            Text("Otomatik geçiş ve yakınlık")
        }
    }

    // MARK: Unut

    private var forget: some View {
        Section {
            Button("Bu cihazı unut…", role: .destructive) { confirmForget = true }
                .frame(minHeight: 44, alignment: .leading)
                .confirmationDialog("\(d.name) unutulsun mu?", isPresented: $confirmForget) {
                    Button("Unut", role: .destructive) { model.forget(d.id); onForget() }
                    Button("Vazgeç", role: .cancel) {}
                } message: {
                    Text("Cihaz ve ayarları bu uygulamadan kaldırılır. Sistem eşlemesi silinmez.")
                }
        } footer: {
            SettingsNote("Cihaz ve ayarları bu uygulamadan kaldırılır. Sistem Bluetooth eşlemesi silinmez.")
        }
    }
}

extension QcyTouchGesture {
    var label: String {
        switch self {
        case .single: "Tek dokunuş"
        case .double: "Çift dokunuş"
        case .triple: "Üç dokunuş"
        }
    }
}

/// Ozel 10 bant ekolayzer: dikey kaydiricilar (-8...8 dB), Sifirla ve Uygula.
private struct CustomEqEditor: View {
    let enabled: Bool
    let onApply: ([Int]) -> Void

    @State private var gains = [Double](repeating: 0, count: QcyCustomEq.frequencies.count)
    @State private var applied = false

    private static func freqLabel(_ hz: Int) -> String { hz >= 1000 ? "\(hz / 1000)k" : "\(hz)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Özel ekolayzer")
            HStack(alignment: .top, spacing: 4) {
                ForEach(gains.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text("\(Int(gains[i]))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { gains[i] }, set: { gains[i] = $0; applied = false }),
                               in: Double(QcyCustomEq.gainRange.lowerBound)...Double(QcyCustomEq.gainRange.upperBound), step: 1)
                            .frame(width: 110)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 28, height: 110)
                            .accessibilityLabel("\(QcyCustomEq.frequencies[i]) Hz")
                            .accessibilityValue("\(Int(gains[i])) dB")
                        Text(Self.freqLabel(QcyCustomEq.frequencies[i])).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(!enabled)
            HStack {
                Button("Sıfırla") { gains = [Double](repeating: 0, count: gains.count); applied = false }
                    .frame(minHeight: 44)
                Spacer(minLength: 8)
                Button("Uygula") { onApply(gains.map { Int($0) }); applied = true }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .disabled(!enabled)
            }
            SettingsNote(applied
                         ? "Gönderildi; kulaklıktan geri okunmaz, etkisini dinleyerek kontrol edin."
                         : "Bantlar 31 Hz – 16 kHz, ±8 dB.")
        }
    }
}
