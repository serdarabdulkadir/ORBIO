// Menu cubugu paneli (MenuBarExtra .window): Denetim Merkezi karo dili.
import SwiftUI
import EkosistemCore

struct PanelView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Iki sekme AYNI sabit yukseklikte: pencere boyutu sekme / icerik degisince oynamaz (menu cubugundan kopmaz).
    static let height: CGFloat = 580

    var body: some View {
        GlassGroup(spacing: 8) {
            VStack(spacing: 8) {
                PanelSegment(selection: model.panelTab, ringing: model.phone.isRinging) { model.setPanelTab($0) }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        if model.permission != .verildi && model.panelTab == .kulaklik { permissionRow }
                        if let banner = model.banner { bannerRow(banner) }
                        if model.panelTab == .telefon {
                            PhoneView(model: model)
                        } else {
                            headphoneContent
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .id(model.panelTab)
                    .transition(.opacity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(Motion.ease(reduceMotion), value: model.panelTab)
                bottomStrip
            }
            .padding(12)
            .task(id: (model.primary?.id ?? "") + (model.primary?.state.rawValue ?? "")) {
                model.volume.setHeadphone(address: model.primary?.id, name: model.primary?.name ?? "")
            }
        }
        .frame(width: 344, height: Self.height)
    }

    @ViewBuilder
    private var headphoneContent: some View {
        if let device = model.primary {
            let isQcy = model.isQcy(device)
            let q = model.qcyState(for: device.id)
            let link = model.qcyLink(for: device.id)
            let hasBattery = BatteryTile.hasValue(device.battery)
            let hasMode = q.mode != nil
            // Tek satirlik bilgi seridi: kanal kapali / veri bekleniyor (ayrinti .help ve Ayarlar'da).
            if isQcy && (!hasBattery || !hasMode) {
                QcyLinkStrip(status: link, retry: { model.retryQcyLink(device) })
            }
            devicePills(device)
            if let action = model.controlOwnerAction(for: device) { controlOwnerRow(device, action) }
            // QCY icin Pil ve Ses modu karolari her zaman gorunur; veri yoksa soluk kalir.
            if hasBattery || isQcy {
                BatteryTile(battery: device.battery, now: Date(), placeholder: !hasBattery)
            }
            let s = model.settings(for: device.id)
            if isQcy || model.supportsDeviceControl(device) {
                ListeningModeTile(modes: device.availableListeningModes, selection: s.listeningMode,
                                  enabled: hasMode && device.state == .bagliBuMac,
                                  dataMissing: !hasMode,
                                  scene: q.scene,
                                  onSceneSelect: { model.send(.scene($0), to: device) },
                                  transparency: q.transparencyLevel,
                                  onTransparency: { model.send(.transparencyLevel(QcyTransparency.clamp($0)), to: device) }) { mode in
                    model.setListeningMode(device, mode)
                }
            }
            if let apple = model.appleModel(for: device), !apple.listeningModes.isEmpty {
                let a = model.airPods(for: device.id)
                ListeningModeTile(modes: apple.listeningModes, selection: a?.listeningMode ?? .kapali,
                                  enabled: a?.listeningMode != nil && device.state == .bagliBuMac,
                                  dataMissing: a?.listeningMode == nil,
                                  adaptiveStrength: apple.supports(.adaptiveStrength) ? a?.adaptiveStrengthWire : nil,
                                  onAdaptiveStrength: apple.supports(.adaptiveStrength)
                                      ? { model.sendAirPods(.adaptiveStrength($0), to: device) } : nil) { mode in
                    model.sendAirPods(.listeningMode(mode), to: device)
                }
            }
            if model.volume.isSupported {
                VolumeRow(volume: model.volume)
            }
            toggleGrid(device, s)
        } else {
            emptyState
        }
    }

    /// Cihaz hapi + sagda kucuk "Telefona gonder / Buraya bagla"; ikinci cihaz varsa altinda hap.
    @ViewBuilder
    private func devicePills(_ primary: Device) -> some View {
        let busy = model.engine.transferringDeviceID != nil
        HStack(spacing: 6) {
            DevicePill(device: primary, selected: true) {}
            if primary.state == .bagliBuMac {
                PillButton(title: busy ? phaseText : "Telefona gönder", symbol: busy ? nil : "iphone",
                           action: busy ? nil : { model.transfer(primary.id, to: .telefon) })
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                PillButton(title: busy ? phaseText : "Buraya bağla", symbol: busy ? nil : "laptopcomputer",
                           action: busy ? nil : { model.transfer(primary.id, to: .buMac) })
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        if let second = model.secondary {
            DevicePill(device: second, selected: false) { model.selectedID = second.id }
        }
    }

    // MARK: Parcalar

    private var permissionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(model.permission == .reddedildi ? "Bluetooth izni reddedildi." : "Bluetooth izni bekleniyor.")
                .font(.system(size: 12))
            Spacer(minLength: 0)
            Button("Sistem Ayarları'nda aç") { model.openBluetoothPrivacySettings() }
                .buttonStyle(.link).font(.system(size: 12))
        }
        .padding(12)
        .glassTile(cornerRadius: 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func bannerRow(_ b: Banner) -> some View {
        HStack(spacing: 8) {
            Image(systemName: b.symbol).foregroundStyle(Color.accentColor)
            Text(b.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action = b.action, let title = b.actionTitle {
                Button(title) { model.perform(action) }.buttonStyle(.link).font(.system(size: 12, weight: .semibold))
            }
            Button { model.dismissBanner() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(PressableStyle()).foregroundStyle(.secondary)
                .accessibilityLabel("Kapat")
        }
        .padding(12)
        .glassTile(cornerRadius: 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var phaseText: String {
        switch model.engine.transferPhase {
        case .bosta: ""
        case .birakIsteniyor: "Telefondan bırakması isteniyor"
        case .baglaniyor(let n): n > 1 ? "Tekrar deneniyor" : "Bağlanıyor"
        case .geriAliniyor: "Geri alınıyor"
        }
    }

    private func toggleGrid(_ device: Device, _ s: DeviceSettings) -> some View {
        var items: [(title: String, symbol: String, isOn: Bool, action: () -> Void)] = []
        let q = model.qcyState(for: device.id)
        if let wearing = q.wearing {
            items.append(("Kulak algılama", "ear", wearing.enabled, { model.send(.wearingDetection(!wearing.enabled), to: device) }))
        }
        if let multipoint = q.multipoint {
            items.append(("Çift cihaz", "laptopcomputer.and.iphone", multipoint, { model.send(.multipoint(!multipoint), to: device) }))
        }
        if let apple = model.appleModel(for: device), let a = model.airPods(for: device.id) {
            if apple.supports(.earDetection), let on = a.earDetectionEnabled {
                items.append(("Kulak algılama", "ear", on, { model.sendAirPods(.earDetection(!on), to: device) }))
            }
            if apple.supports(.conversationAwareness), let on = a.conversationalAwareness {
                items.append(("Konuşma farkındalığı", "waveform.and.mic", on, { model.sendAirPods(.conversationalAwareness(!on), to: device) }))
            }
            if apple.supports(.oneBudANC), let on = a.oneBudANC {
                items.append(("Tek kulak ANC", "person.crop.circle.fill", on, { model.sendAirPods(.oneBudANC(!on), to: device) }))
            }
        }
        items.append(("Otomatik geçiş", "arrow.left.arrow.right", s.autoSwitch != .hicbirZaman, {
            model.update(device.id) { $0.autoSwitch = $0.autoSwitch == .hicbirZaman ? .telefondaCagriGelince : .hicbirZaman }
        }))
        items.append(("Yakınlık", "dot.radiowaves.left.and.right", s.proximityCard, { model.update(device.id) { $0.proximityCard.toggle() } }))
        items.append(("Sessiz", "bell.slash.fill", s.silent, { model.update(device.id) { $0.silent.toggle() } }))
        return HStack(alignment: .top, spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                CircleToggle(title: item.title, symbol: item.symbol, isOn: item.isOn, diameter: 46, labelSize: 10, action: item.action)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .glassTile()
    }

    /// Kontrol sahibi satiri: telefon uzerinden mi dogrudan mi + devir dugmesi.
    private func controlOwnerRow(_ device: Device, _ action: AppModel.ControlOwnerAction) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action == .macAl ? "iphone" : "laptopcomputer").foregroundStyle(.secondary).font(.system(size: 11))
            Text(action == .macAl ? "Telefon üzerinden" : "Doğrudan bu Mac'ten").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action == .macAl ? "Kontrolü Mac'e al" : "Kontrolü telefona ver") {
                model.performControlOwnerAction(action, for: device)
            }
            .buttonStyle(.link).font(.system(size: 12, weight: .semibold))
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .glassTile(cornerRadius: 16)
    }

    private var emptyState: some View {
        Text(model.bluetoothOff ? "Mac'in Bluetooth'u kapalı"
                                : "Henüz cihaz yok. Kulaklığınızın kutusunu Mac'in yanında açın.")
            .font(.system(size: 13)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(24)
            .glassTile()
    }

    private var bottomStrip: some View {
        HStack(spacing: 8) {
            PillButton(title: "Güncel \(model.engine.lastUpdate.map(Format.time.string(from:)) ?? "--")", symbol: nil)
            Spacer(minLength: 0)
            PillButton(title: "Ayarlar", symbol: "gearshape") {
                NSApp.activate()
                openSettings()
            }
            PillButton(title: "Yenile", symbol: "arrow.clockwise") { model.refresh() }
        }
    }
}
