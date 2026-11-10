import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let bg = Color.black
    static let field = Color(hex: 0x121212)
    static let surface = Color(hex: 0x1C1C1E)
    static let surface2 = Color(hex: 0x2C2C2E)
    static let text = Color.white
    static let text2 = Color(hex: 0x8E8E93)
    static let accent = Color(hex: 0xF4F4F5)
    static let onAccent = Color(hex: 0x18161D)
    static let amber = Color(hex: 0xEEBC41)
    static let mint = Color(hex: 0x64D2A4)
    static let record = Color(hex: 0xFF453A)
    static let success = Color(hex: 0x30D158)
    static let spark = Color(hex: 0xE7B656)

    static let cardPalette: [UInt32] = [
        0x784B34, // rust
        0x766F3B, // olive
        0x8A6A2E, // mustard
        0x84503A, // terracotta
        0x4F6447, // muted green
        0x6A4552, // plum
    ]

    static func cardIndex(for id: UUID) -> Int {
        let u = id.uuid
        let bytes = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        let sum = bytes.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
        return sum % cardPalette.count
    }

    /// Deterministic colour indices for a strip; neighbours never share a colour.
    static func cardIndices(for ids: [UUID]) -> [Int] {
        var out: [Int] = []
        for id in ids {
            var i = cardIndex(for: id)
            if let prev = out.last, prev == i { i = (i + 1) % cardPalette.count }
            out.append(i)
        }
        return out
    }

    static func cardGlow(_ index: Int) -> [Color] {
        let base = Color(hex: cardPalette[index % cardPalette.count])
        return [.white, base.mix(.white, 0.55), spark.mix(.white, 0.3), base.mix(.white, 0.75)]
    }

    static func cardGradient(_ index: Int) -> LinearGradient {
        let base = Color(hex: cardPalette[index % cardPalette.count])
        return LinearGradient(colors: [base.opacity(1), base.mix(.black, 0.18)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var morph: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
    }
    static var content: Animation { .easeOut(duration: 0.18) }
}

extension Color {
    func mix(_ other: Color, _ t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB,
                     red: a.redComponent * (1 - t) + b.redComponent * t,
                     green: a.greenComponent * (1 - t) + b.greenComponent * t,
                     blue: a.blueComponent * (1 - t) + b.blueComponent * t)
    }
}

/// Content entrance: opacity + blur 4→0 + scale 0.96→1.
struct BlurFade: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active && !Theme.reduceMotion ? 4 : 0)
            .scaleEffect(active && !Theme.reduceMotion ? 0.96 : 1)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false)).animation(Theme.content)
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat = 6
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 4), y: 0))
    }
}

struct PillButtonStyle: ButtonStyle {
    var fill: Color = Theme.surface
    var fg: Color = Theme.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(fg)
            .background(Capsule().fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
