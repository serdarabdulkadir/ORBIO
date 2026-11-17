// Denetim Merkezi tarzi karolar: kulaklik, pil halkalari, ses modu, dairesel dugmeler.
import SwiftUI
import EkosistemCore

/// Kompakt cihaz hapi: yuvarlak simge (secili = beyaz dolu), ad ve durum.
struct DevicePill: View {
    let device: Device
    let selected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .frame(width: 36, height: 36)
                    .background { if selected { Circle().fill(.white) } else { Circle().fill(.quaternary) } }
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        if device.state == .bagliBuMac {
                            Circle().fill(Color.green).frame(width: 5, height: 5)
                        }
                        Text(device.state.label)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCapsule(interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.spring(reduceMotion), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Karo basligi (Pil, Ses modu, Ses).
struct TileTitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13, weight: .semibold)) }
}

/// Ince halka gosterge. Dusuk pilde kirmizi, bilinmeyende "--", soluk okumada saydam.
struct BatteryRing: View {
    let title: String
    let level: Int?
    let charging: Bool
    let stale: Bool
    var size: CGFloat = 54

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var low: Bool { (level ?? 100) <= LowBatteryMonitor.alertThreshold }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(low ? Color.red.opacity(0.18) : Color.white.opacity(0.15), lineWidth: 5)
                if let level {
                    Circle()
                        .trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(low ? Color.red.opacity(0.85) : Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? .easeInOut(duration: 0.1) : .easeInOut(duration: 0.7), value: level)
                }
                HStack(spacing: 1) {
                    if charging {
                        Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.green)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                    Text(Format.percent(level))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(low ? Color.red.opacity(0.9) : Color.primary)
                }
            }
            .frame(width: size, height: size)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .opacity(stale ? 0.45 : 1)
        .animation(Motion.ease(reduceMotion), value: stale)
        .animation(Motion.ease(reduceMotion), value: low)
        .animation(Motion.spring(reduceMotion), value: charging)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) pil \(Format.percent(level))")
    }
}

struct BatteryTile: View {
    let battery: BatteryReading?
    let now: Date
    /// Veri yokken karo soluk "--" halkalariyla kalir.
    var placeholder = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// En az bir gercek pil degeri var mi (yoksa karo gosterilmez).
    static func hasValue(_ b: BatteryReading?) -> Bool {
        guard let b else { return false }
        return b.left != nil || b.right != nil || b.caseLevel != nil || b.overall != nil
    }

    var body: some View {
        let stale = battery?.isStale(at: now) ?? false
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TileTitle(text: "Pil")
                Spacer(minLength: 0)
                if Self.isCharging(battery) {
                    Text("Şarj oluyor")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.green.opacity(0.95))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                if Self.isLow(battery) {
                    Text("Düşük pil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.95))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.18)))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            HStack(spacing: 0) {
                if placeholder {
                    ForEach(["Sol", "Sağ", "Kutu"], id: \.self) { t in
                        BatteryRing(title: t, level: nil, charging: false, stale: true, size: 46).frame(maxWidth: .infinity)
                    }
                } else if let b = battery, b.left == nil, b.right == nil, b.caseLevel == nil, let overall = b.overall {
                    BatteryRing(title: "Pil", level: overall, charging: b.isCharging(.genel), stale: stale, size: 46)
                        .frame(maxWidth: .infinity)
                } else {
                    if let l = battery?.left {
                        BatteryRing(title: "Sol", level: l, charging: battery?.leftCharging ?? false, stale: stale, size: 46)
                            .frame(maxWidth: .infinity)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    if let r = battery?.right {
                        BatteryRing(title: "Sağ", level: r, charging: battery?.rightCharging ?? false, stale: stale, size: 46)
                            .frame(maxWidth: .infinity)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    if let c = battery?.caseLevel {
                        BatteryRing(title: "Kutu", level: c, charging: battery?.caseCharging ?? false, stale: stale, size: 46)
                            .frame(maxWidth: .infinity)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .glassTile()
        .animation(Motion.ease(reduceMotion), value: Self.isLow(battery))
        .animation(Motion.ease(reduceMotion), value: Self.isCharging(battery))
    }

    /// Gosterilen halkalardan en az biri sarj oluyor mu.
    static func isCharging(_ b: BatteryReading?) -> Bool {
        guard let b else { return false }
        if b.left == nil, b.right == nil, b.caseLevel == nil, b.overall != nil { return b.isCharging(.genel) }
        return (b.left != nil && b.leftCharging) || (b.right != nil && b.rightCharging) || (b.caseLevel != nil && b.caseCharging)
    }

    /// Gosterilen degerlerden en az biri esik veya altinda mi.
    static func isLow(_ b: BatteryReading?) -> Bool {
        guard let b else { return false }
        return [b.left, b.right, b.caseLevel, b.overall].contains { ($0 ?? 100) <= LowBatteryMonitor.alertThreshold }
    }
}

struct ListeningModeTile: View {
    let modes: [ListeningMode]
    let selection: ListeningMode
    let enabled: Bool
    /// Cihazdan ses modu okunmadi: secim vurgulanmaz, karo pasif kalir.
    var dataMissing = false
    var scene: QcyNoiseScene? = nil
    var onSceneSelect: ((QcyNoiseScene) -> Void)? = nil
    /// Cihazdan okunan seffaflik seviyesi; kaydirici yalniz Seffaf secilince ve `onTransparency` verilince gorunur.
    var transparency: Int? = nil
    var onTransparency: ((Int) -> Void)? = nil
    /// AirPods uyarlanir mod gurultu seviyesi (ham AAP degeri); secici yalniz Uyarlanir secilince ve `onAdaptiveStrength` verilince gorunur.
    var adaptiveStrength: UInt8? = nil
    var onAdaptiveStrength: ((UInt8) -> Void)? = nil
    let onSelect: (ListeningMode) -> Void

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func symbol(_ mode: ListeningMode) -> String {
        switch mode {
        case .kapali: "circle.slash"
        case .gurultuEngeli: "person.crop.circle.fill"
        case .seffaf: "person.wave.2.fill"
        case .uyarlanir: "sparkles"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TileTitle(text: "Ses modu").padding(.leading, 10).padding(.top, 4)
            selector
            if !dataMissing, selection == .gurultuEngeli, let scene, let onSceneSelect {
                Divider().opacity(0.5).padding(.horizontal, 10)
                NoiseSceneSelector(selection: scene, onSelect: onSceneSelect)
                    .padding(.bottom, 2)
            } else if !dataMissing, selection == .seffaf, let onTransparency {
                Divider().opacity(0.5).padding(.horizontal, 10)
                TransparencySlider(level: transparency, onCommit: onTransparency)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            } else if !dataMissing, selection == .uyarlanir, let onAdaptiveStrength {
                Divider().opacity(0.5).padding(.horizontal, 10)
                AdaptiveStrengthSelector(wire: adaptiveStrength, onCommit: onAdaptiveStrength)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile()
        .animation(Motion.spring(reduceMotion), value: selection)
        .opacity(enabled ? 1 : 0.5)
        .animation(Motion.ease(reduceMotion), value: enabled)
        .disabled(!enabled)
    }

    private var selector: some View {
        HStack(spacing: 4) {
            ForEach(modes, id: \.self) { mode in
                let isSel = !dataMissing && mode == selection
                Button {
                    withAnimation(Motion.spring(reduceMotion)) { onSelect(mode) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol(mode)).font(.system(size: 16, weight: .semibold))
                        Text(mode.label)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(isSel ? Color.accentColor : Color.primary)
                    .background {
                        if isSel {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white)
                                .matchedGeometryEffect(id: "secim", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(isSel ? .isSelected : [])
            }
        }
    }
}

/// Gurultu engelleme sahne secici: "Ses modu" karosunun icinde, yalnizca cihazdan sahne okunduysa gosterilir.
struct NoiseSceneSelector: View {
    let selection: QcyNoiseScene
    let onSelect: (QcyNoiseScene) -> Void

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func symbol(_ scene: QcyNoiseScene) -> String {
        switch scene {
        case .uyarlanir: "wand.and.stars"
        case .kapaliAlan: "house.fill"
        case .yolculuk: "tram.fill"
        case .gurultulu: "waveform"
        case .ruzgarKarsiti: "wind"
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 4)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(QcyNoiseScene.allCases, id: \.self) { scene in
                let isSel = scene == selection
                Button {
                    withAnimation(Motion.spring(reduceMotion)) { onSelect(scene) }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: symbol(scene)).font(.system(size: 15, weight: .semibold))
                            .frame(height: 18)
                        Text(scene.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSel ? Color.accentColor : Color.primary)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSel ? Color.white.opacity(0.92) : Color.primary.opacity(0.06))
                    }
                    .overlay {
                        if isSel {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scene.label)
                .accessibilityAddTraits(isSel ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .animation(Motion.spring(reduceMotion), value: selection)
    }
}

/// Dairesel acma/kapama dugmesi: acik = beyaz dolu daire + vurgu simgesi, kapali = cam.
struct CircleToggle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let symbol: String
    let isOn: Bool
    var diameter: CGFloat = 56
    var labelSize: CGFloat = 11
    let action: () -> Void

    var body: some View {
        VStack(spacing: diameter < 50 ? 4 : 6) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: diameter < 50 ? 17 : 20, weight: .semibold))
                    .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                    .frame(width: diameter, height: diameter)
                    .background { if isOn { Circle().fill(.white) } }
                    .modifier(OffGlass(isOn: isOn))
                    .contentShape(Circle())
                    .animation(Motion.spring(reduceMotion), value: isOn)
            }
            .buttonStyle(PressableStyle())
            Text(title)
                .font(.system(size: labelSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct OffGlass: ViewModifier {
    let isOn: Bool
    func body(content: Content) -> some View {
        if isOn { content } else { content.glassCircle() }
    }
}

struct PillButton: View {
    let title: String
    let symbol: String?
    var action: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        if let action {
            Button(action: action) { label.glassCapsule(interactive: true).contentShape(Capsule()) }
                .buttonStyle(PressableStyle())
        } else {
            label.glassCapsule().foregroundStyle(.secondary)
        }
    }
}

/// QCY kontrol kanali durum satiri: baglanirken ilerleme, kapaliyken neden + "Tekrar dene".
struct QcyLinkNote: View {
    let status: QcyLinkStatus
    let retry: () -> Void

    static let closedText = "Kontrol kanalı kapalı. Kulaklık başka bir cihazın kontrolünde olabilir: telefondaki ORBIO uygulamasını kapatıp Yenile'ye basın."
    static let waitingText = "Kulaklıktan veri bekleniyor…"

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if status == .kapali {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 12))
                Text(Self.closedText).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Tekrar dene", action: retry).buttonStyle(.link).font(.system(size: 11, weight: .semibold))
            } else {
                ProgressView().controlSize(.small)
                Text(Self.waitingText).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}

extension QcyKeyFunction {
    var label: String {
        switch self {
        case .none: "İşlev yok"
        case .playPause: "Oynat / duraklat"
        case .previous: "Önceki parça"
        case .next: "Sonraki parça"
        case .voiceAssistant: "Sesli asistan"
        case .volumeUp: "Sesi artır"
        case .volumeDown: "Sesi azalt"
        case .gameMode: "Oyun modu"
        }
    }
}

extension QcyTouchSlot {
    var label: String {
        let side = self.side == .left ? "Sol kulaklık" : "Sağ kulaklık"
        let gesture: String
        switch self.gesture {
        case .single: gesture = "tek dokunuş"
        case .double: gesture = "çift dokunuş"
        case .triple: gesture = "üç dokunuş"
        }
        return "\(side), \(gesture)"
    }
}

/// Ayarlar > "Dokunmatik kontroller": her jest icin acilir menu; veri yoksa nedenini yazar.
struct TouchControlsTile: View {
    let keys: QcyKeyMap?
    let link: QcyLinkStatus
    let enabled: Bool
    let canRestore: Bool
    let onSelect: (QcyTouchSlot, QcyKeyFunction) -> Void
    let onRestore: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TileTitle(text: "Dokunmatik kontroller")
                Text("MeloBuds Pro'da deneysel")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                Spacer(minLength: 0)
            }
            if let keys, !keys.slots.isEmpty {
                ForEach(keys.slots, id: \.self) { gesture in
                    HStack {
                        Text(gesture.label).font(.system(size: 13))
                        Spacer(minLength: 12)
                        Picker(gesture.label, selection: Binding<QcyKeyFunction?>(
                            get: { keys.function(side: gesture.side, gesture: gesture.gesture) },
                            set: { if let f = $0 { onSelect(gesture, f) } })) {
                            if keys.function(side: gesture.side, gesture: gesture.gesture) == nil { Text("Bilinmiyor").tag(Optional<QcyKeyFunction>.none) }
                            ForEach(QcyKeyFunction.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                        .disabled(!enabled)
                    }
                }
                HStack {
                    Text("Değişiklik kulaklığa kaydedilir.").font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Önceki değere dön", action: onRestore)
                        .buttonStyle(.link).font(.system(size: 12, weight: .semibold))
                        .disabled(!canRestore || !enabled)
                }
            } else if keys != nil {
                Text("Bu kulaklık bilinen dokunmatik jestleri bildirmedi.").font(.footnote).foregroundStyle(.secondary)
            } else if link == .hazir {
                Text("Kulaklık tuş eşlemesini (000D) vermedi; dokunmatik ayarlar okunamadı.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                QcyLinkNote(status: link, retry: onRetry)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: 22)
        .opacity(keys == nil ? 0.6 : 1)
    }
}

/// Tek satirlik bilgi seridi (panelin ustunde, bir kez): kanal kapali ya da veri bekleniyor.
struct QcyLinkStrip: View {
    let status: QcyLinkStatus
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if status == .kapali {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 11))
                Text("Kontrol başka bir cihazda (telefon?)").font(.system(size: 12))
                Spacer(minLength: 0)
                Button("Tekrar dene", action: retry).buttonStyle(.link).font(.system(size: 12, weight: .semibold))
            } else {
                ProgressView().controlSize(.mini)
                Text(QcyLinkNote.waitingText).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .glassTile(cornerRadius: 16)
        .help(status == .kapali ? QcyLinkNote.closedText : QcyLinkNote.waitingText)
    }
}

/// Seffaflik seviyesi secici: 5 kademe (1...5). Seviye-etki eslesmesi DOGRULANMADI; gosterilen deger cihazdan gelir.
struct TransparencySlider: View {
    let level: Int?
    let onCommit: (Int) -> Void

    private let steps = 1...5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Şeffaflık seviyesi · deneysel").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 4) {
                ForEach(Array(steps), id: \.self) { n in
                    let isSel = level.map { min($0, 5) } == n
                    Button { onCommit(n) } label: {
                        Text("\(n)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(isSel ? Color.accentColor : Color.primary)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSel ? Color.white.opacity(0.92) : Color.primary.opacity(0.06))
                            }
                            .overlay {
                                if isSel { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5) }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Şeffaflık seviyesi \(n)")
                    .accessibilityAddTraits(isSel ? .isSelected : [])
                }
            }
        }
    }
}

/// AirPods uyarlanir mod gurultu seviyesi: 3 secenek (ham AAP degeri 0 / 50 / 100; yon cihazda dogrulanmadi).
struct AdaptiveStrengthSelector: View {
    let wire: UInt8?
    let onCommit: (UInt8) -> Void

    private let options: [(title: String, wire: UInt8)] = [("Düşük", 0), ("Orta", 50), ("Yüksek", 100)]

    private func isSelected(_ value: UInt8) -> Bool {
        guard let wire else { return false }
        return options.min { abs(Int($0.wire) - Int(wire)) < abs(Int($1.wire) - Int(wire)) }?.wire == value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Uyarlanır şiddet · deneysel").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 4) {
                ForEach(options, id: \.wire) { option in
                    let isSel = isSelected(option.wire)
                    Button { onCommit(option.wire) } label: {
                        Text(option.title)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(isSel ? Color.accentColor : Color.primary)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSel ? Color.white.opacity(0.92) : Color.primary.opacity(0.06))
                            }
                            .overlay {
                                if isSel { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5) }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Uyarlanır şiddet \(option.title)")
                    .accessibilityAddTraits(isSel ? .isSelected : [])
                }
            }
        }
    }
}

/// Basliksiz tek satir ses karosu: hoparlor ikonu + kaydirici + cikis dugmesi.
struct VolumeRow: View {
    let volume: SystemVolume
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var speakerSymbol: String {
        switch volume.level {
        case ..<0.001: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.white).frame(width: max(28, w * volume.level))
                    Image(systemName: speakerSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.65))
                        .frame(width: 28, height: 28)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in volume.set(g.location.x / max(w, 1)) })
            }
            .frame(height: 28)
            .accessibilityElement()
            .accessibilityLabel("Ses")
            .accessibilityValue("%\(Int((volume.level * 100).rounded()))")
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: volume.set(volume.level + 0.0625)
                case .decrement: volume.set(volume.level - 0.0625)
                @unknown default: break
                }
            }
            Button { volume.toggleOutput() } label: {
                Image(systemName: volume.outputSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
                    .glassCircle(interactive: volume.headphoneAvailable)
            }
            .buttonStyle(PressableStyle())
            .disabled(!volume.headphoneAvailable)
            .opacity(volume.headphoneAvailable ? 1 : 0.6)
            .help(volume.headphoneActive ? "Sesi Mac hoparlörüne al" : "Sesi kulaklığa al")
            .accessibilityLabel(volume.headphoneActive ? "Sesi Mac hoparlörüne al" : "Sesi kulaklığa al")
            .accessibilityValue(volume.outputName)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .glassTile()
    }
}
