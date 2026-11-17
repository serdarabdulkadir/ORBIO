// Liquid Glass (macOS 26+) ile `.regularMaterial` yedegi. Renkler yalniz sistem renkleridir.
import SwiftUI

/// Karolari tek cam kabinde toplar (macOS 26+); eski surumde duz kapsayici.
struct GlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// Yuvarlak koseli cam karo.
    @ViewBuilder
    func glassTile(cornerRadius: CGFloat = 28, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Hap seklinde cam.
    @ViewBuilder
    func glassCapsule(interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }

    /// Daire seklinde cam (kapali dugme).
    @ViewBuilder
    func glassCircle(interactive: Bool = true) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: Circle())
        } else {
            self.background(.regularMaterial, in: Circle())
        }
    }
}

/// Animasyon yardimcilari: Reduce Motion aciksa yay/olcek yerine kisa soluklasma kullanilir.
enum Motion {
    static func spring(_ reduce: Bool) -> Animation {
        reduce ? .easeInOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.82)
    }
    static func ease(_ reduce: Bool) -> Animation {
        .easeInOut(duration: reduce ? 0.1 : 0.25)
    }
}

/// Basilma efekti: hafif kuculme ve soluklasma.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
