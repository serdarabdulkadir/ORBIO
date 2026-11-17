// Yaklasma pil karti: odak calmayan NSPanel, ekranin alt ortasi, Dock'un 16 pt ustu, 360x220.
import AppKit
import SwiftUI
import Observation
import EkosistemCore

/// Kartin canli durumu: icerik, baglanma asamasi ve cihaz (pil/durum canli gelir).
@MainActor
@Observable
final class CardModel {
    enum Phase: Equatable { case normal, connecting, connected, failed }
    var content: CardContent
    var device: Device
    var phase: Phase = .normal
    init(content: CardContent, device: Device) { self.content = content; self.device = device }
}

struct ProximityCardView: View {
    let model: CardModel
    let connect: () -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var device: Device { model.device }
    /// Canli pil varsa onu, yoksa kart icerigindeki degeri kullanir.
    private var battery: BatteryReading {
        if let b = device.battery, b.hasAnyValue { return b }
        return model.content.battery
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text(device.name).font(.system(size: 15, weight: .semibold))
                HStack {
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Kapat")
                }
            }
            HStack {
                let b = battery
                if b.left != nil || b.right != nil {
                    column("airpods.pro.left", .sol, b.left, b.leftCharging)
                    column("airpods.pro.right", .sag, b.right, b.rightCharging)
                } else if b.overall != nil {
                    column(device.symbol, .genel, b.overall, false)
                }
                // Kutu pili yoksa kutu sutunu hic gosterilmez.
                if b.caseLevel != nil {
                    column("airpods.chargingcase", .kutu, b.caseLevel, b.caseCharging)
                }
            }
            action
                .frame(height: 32)
        }
        .padding(16)
        .frame(width: 360, height: 220)
        .glassTile(cornerRadius: 36)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.phase)
    }

    @ViewBuilder private var action: some View {
        switch model.phase {
        case .normal:
            Button("Bu Mac'e bağla", action: connect).buttonStyle(.borderedProminent).controlSize(.large)
        case .connecting:
            Button(action: {}) {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Bağlanıyor…") }
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(true)
        case .connected:
            Label("Bağlandı", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.green)
                .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
        case .failed:
            HStack(spacing: 10) {
                Label("Bağlanamadı", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13)).foregroundStyle(.orange)
                Button("Tekrar dene", action: connect).buttonStyle(.borderedProminent).controlSize(.regular)
            }
        }
    }

    private func column(_ symbol: String, _ channel: BatteryChannel, _ level: Int?, _ charging: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                if charging { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(.green) }
                Text(Format.percent(level))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle((level ?? 100) <= LowBatteryMonitor.alertThreshold ? Color.red : Color.primary)
            }
            Text(channel.label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .opacity(battery.isStale(at: Date()) ? 0.45 : 1)
    }
}

@MainActor
final class ProximityCardController {
    enum Anchor { case bottom, top, center }

    private var panel: NSPanel?
    private let size: NSSize
    private let anchor: Anchor

    init(size: NSSize = NSSize(width: 360, height: 220), anchor: Anchor = .bottom) {
        self.size = size
        self.anchor = anchor
    }

    func show(model: CardModel, connect: @escaping () -> Void, close: @escaping () -> Void) {
        present(ProximityCardView(model: model, connect: connect, close: close))
    }

    /// Herhangi bir SwiftUI icerigini odak calmayan yuzen panelde gosterir.
    func present<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let panel = self.panel ?? makePanel()
        panel.contentView = host
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visible.midX - size.width / 2
        let y: CGFloat = switch anchor {
        case .bottom: visible.minY + 16
        case .top: visible.maxY - size.height - 12
        case .center: visible.midY - size.height / 2
        }
        let target = NSPoint(x: x, y: y)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        panel.setFrameOrigin(reduce ? target : NSPoint(x: target.x, y: target.y - 24))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
            if !reduce { panel.animator().setFrameOrigin(target) }
        }
        self.panel = panel
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }
}
