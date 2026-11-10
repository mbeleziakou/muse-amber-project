import SwiftUI
import AppKit

// MARK: - Glass surface

/// Glassmorphism surface: translucent fill, top-left sheen, gradient rim, soft depth.
struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var active: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(Color.white.opacity(active ? 0.045 : 0.03))
                    shape.fill(LinearGradient(colors: [.white.opacity(0.05), .clear],
                                              startPoint: .topLeading, endPoint: .center))
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(active ? 0.16 : 0.10), .white.opacity(0.03), .white.opacity(0.05)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
            .animation(.easeOut(duration: 0.2), value: active)
    }
}

extension View {
    func glass(_ radius: CGFloat, active: Bool = false) -> some View { modifier(GlassSurface(radius: radius, active: active)) }
}

// MARK: - Border glow (cursor-tracking mesh-gradient rim)

struct BorderGlow: ViewModifier {
    var radius: CGFloat
    var colors: [Color]
    var sweepOnAppear = false
    var forced: Bool = false
    var edgeSensitivity: Double = 0.30
    var coneSpread: Double = 0.25

    @State private var size: CGSize = .zero
    @State private var angle: Double = 45
    @State private var edge: Double = 0
    @State private var hovering = false
    @State private var sweepStart: Date?

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { size = g.size } })
            .overlay {
                TimelineView(.animation(paused: sweepStart == nil)) { tl in
                    let (a, e) = current(at: tl.date)
                    glow(angle: a, edge: forced ? max(e, 0.7) : e)
                }
                .allowsHitTesting(false)
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    guard size.width > 0, size.height > 0 else { return }
                    let cx = size.width / 2, cy = size.height / 2
                    let dx = p.x - cx, dy = p.y - cy
                    let prox = min(1, max(abs(dx) / cx, abs(dy) / cy))
                    var deg = atan2(dy, dx) * 180 / .pi + 90
                    if deg < 0 { deg += 360 }
                    angle = deg
                    edge = prox
                    if !hovering { withAnimation(.easeOut(duration: 0.25)) { hovering = true } }
                case .ended:
                    withAnimation(.easeInOut(duration: 0.75)) { hovering = false }
                }
            }
            .onAppear {
                if sweepOnAppear && !Theme.reduceMotion { sweepStart = .now }
            }
    }

    /// Sweep: angle 110°→465° over ~3.75 s while proximity rises then fades (as in the original).
    private func current(at date: Date) -> (Double, Double) {
        guard let s = sweepStart else { return (angle, hovering || forced ? edge : 0) }
        let t = date.timeIntervalSince(s)
        if t > 4.0 { DispatchQueue.main.async { sweepStart = nil }; return (angle, hovering ? edge : 0) }
        let inC = { (x: Double) in x * x * x }
        let outC = { (x: Double) in 1 - pow(1 - x, 3) }
        var v: Double
        if t < 1.5 { v = 50 * inC(t / 1.5) } else { v = 50 + 50 * outC(min(1, (t - 1.5) / 2.25)) }
        let a = (465 - 110) * (v / 100) + 110
        var e: Double
        if t < 0.5 { e = outC(t / 0.5) } else if t < 2.5 { e = 1 } else { e = 1 - inC(min(1, (t - 2.5) / 1.5)) }
        return (a, e)
    }

    @ViewBuilder private func glow(angle: Double, edge: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let borderOpacity = max(0, min(1, (edge - (edgeSensitivity + 0.2)) / (1 - (edgeSensitivity + 0.2))))
        let lightOpacity = max(0, min(1, (edge - edgeSensitivity) / (1 - edgeSensitivity)))
        let mesh = AngularGradient(colors: colors + [colors.first ?? .white], center: .center, angle: .degrees(angle - 90))
        let cone = AngularGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: coneSpread),
            .init(color: .clear, location: coneSpread + 0.15),
            .init(color: .clear, location: 1 - coneSpread - 0.15),
            .init(color: .black, location: 1 - coneSpread),
            .init(color: .black, location: 1),
        ], center: .center, angle: .degrees(angle - 90))
        ZStack {
            // soft outer light
            shape.stroke(mesh, lineWidth: 6).blur(radius: 10).opacity(lightOpacity * (forced ? 0.35 : 0.7))
            // crisp coloured rim
            shape.strokeBorder(mesh, lineWidth: 1.5).opacity(borderOpacity)
        }
        .mask(Rectangle().fill(cone).padding(-40))
        .compositingGroup()
        .blendMode(.plusLighter)
    }
}

extension View {
    func borderGlow(radius: CGFloat, colors: [Color], sweep: Bool = false, forced: Bool = false) -> some View {
        modifier(BorderGlow(radius: radius, colors: colors, sweepOnAppear: sweep, forced: forced))
    }
}

// MARK: - Gooey nav

struct GooeyNav<ID: Hashable>: View {
    struct Item: Identifiable { var id: ID; var label: String; var icon: String? = nil }
    var items: [Item]
    @Binding var selection: ID
    var compact = false

    @State private var frames: [ID: CGRect] = [:]
    @State private var from: CGRect?
    @State private var start: Date?
    @State private var drops: [Drop] = []
    @State private var shownActive: ID?

    struct Drop { var angle: Double; var distance: Double; var radius: Double; var delay: Double }
    private let duration = 0.62

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(items) { item in
                let active = (shownActive ?? selection) == item.id
                HStack(spacing: 6) {
                    if let icon = item.icon { Image(systemName: icon) }
                    Text(item.label)
                }
                .font(.system(size: compact ? 12.5 : 13.5, weight: .medium))
                .foregroundStyle(active ? Theme.onAccent : Theme.text2)
                .padding(.horizontal, compact ? 12 : 15).padding(.vertical, compact ? 6 : 8)
                .background(GeometryReader { g in
                    Color.clear.preference(key: GooeyFrames<ID>.self, value: [item.id: g.frame(in: .named("gooey"))])
                })
                .contentShape(Capsule())
                .onTapGesture { select(item.id) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .coordinateSpace(name: "gooey")
        .onPreferenceChange(GooeyFrames<ID>.self) { frames = $0 }
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if start == nil, let r = frames[selection] {
                    Capsule().fill(Theme.accent)
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        .shadow(color: .white.opacity(0.18), radius: 8)
                }
                if start != nil { goo.padding(-24) }
            }
        }
        .padding(compact ? 4 : 5)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
        .overlay(Capsule().inset(by: 1).stroke(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: shownActive)
    }

    private var goo: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            Canvas { ctx, _ in
                guard let target = frames[selection] else { return }
                ctx.addFilter(.alphaThreshold(min: 0.5, color: Theme.accent))
                ctx.addFilter(.blur(radius: 5))
                ctx.drawLayer { c in
                    c.translateBy(x: 24, y: 24)
                    let t = start.map { min(1, tl.date.timeIntervalSince($0) / duration) } ?? 1
                    let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                    func pill(_ r: CGRect, _ s: CGFloat) {
                        guard s > 0.02 else { return }
                        let w = r.width * s, h = r.height * max(s, 0.55)
                        c.fill(Path(roundedRect: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h), cornerRadius: h / 2), with: .color(.black))
                    }
                    if let from, t < 1 {
                        pill(from, CGFloat(1 - min(1, t * 1.6)))
                        let mid = CGRect(x: from.minX + (target.minX - from.minX) * e, y: target.minY,
                                         width: from.width + (target.width - from.width) * e, height: target.height)
                        pill(mid, CGFloat(0.62 + 0.38 * abs(0.5 - t) * 2))
                        pill(target, CGFloat(max(0, (t - 0.35) / 0.65)))
                    } else {
                        pill(target, 1)
                    }
                    for d in drops where t > d.delay {
                        let k = min(1, (t - d.delay) / (1 - d.delay))
                        let out = sin(k * .pi)
                        let p = CGPoint(x: target.midX + cos(d.angle) * d.distance * out,
                                        y: target.midY + sin(d.angle) * d.distance * out * 0.55)
                        let r = d.radius * (1 - k * 0.6)
                        c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.black))
                    }
                    if t >= 1 { DispatchQueue.main.async { start = nil; from = nil; shownActive = nil } }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func select(_ id: ID) {
        guard id != selection else { return }
        if Theme.reduceMotion { selection = id; return }
        from = frames[selection]
        shownActive = selection
        drops = (0..<12).map { i in
            Drop(angle: Double(i) / 12 * 2 * .pi + .random(in: -0.3...0.3),
                 distance: .random(in: 18...34), radius: .random(in: 2.5...5), delay: .random(in: 0.3...0.45))
        }
        start = .now
        selection = id
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.5) { shownActive = nil }
    }
}

private struct GooeyFrames<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }
    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) { value.merge(nextValue()) { $1 } }
}

// MARK: - Animated list

/// Rows spring into view (pop: y±12, scale 0.8 → 1, staggered).
struct PopIn: ViewModifier {
    var index: Int
    var stagger: Double = 0.05
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || Theme.reduceMotion ? 1 : 0.8)
            .offset(y: shown || Theme.reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(Theme.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.62).delay(Double(min(index, 10)) * stagger)) {
                    shown = true
                }
            }
    }
}

extension View {
    func popIn(_ index: Int) -> some View { modifier(PopIn(index: index)) }

    /// Smooth fade at the top and bottom edges of a scroll area (smootherstep).
    func edgeFade(top: CGFloat = 40, bottom: CGFloat = 56) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(stops: fadeStops(), startPoint: .top, endPoint: .bottom).frame(height: top)
                Rectangle()
                LinearGradient(stops: fadeStops(), startPoint: .bottom, endPoint: .top).frame(height: bottom)
            }
        }
    }
}

private func fadeStops() -> [Gradient.Stop] {
    var out: [Gradient.Stop] = []
    for i in 0...8 {
        let t = Double(i) / 8
        let k: Double = t * t * t * (t * (t * 6 - 15) + 10)
        out.append(Gradient.Stop(color: Color.black.opacity(k), location: t))
    }
    return out
}

/// Gliding selection highlight shared across rows.
struct ListSelection: ViewModifier {
    var selected: Bool
    var namespace: Namespace.ID
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content.background {
            if selected {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.28)))
                    .matchedGeometryEffect(id: "list-selection", in: namespace)
            }
        }
    }
}

// MARK: - Icon motion

enum IconMotion { case bounce, spin, pulse }

/// Every icon reacts: bounce on hover/press, optional spin (gear) or gentle pulse.
struct AnimatedIcon: ViewModifier {
    var motion: IconMotion = .bounce
    var trigger: AnyHashable? = nil
    @State private var hovers = 0
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce.down, value: hovers)
            .symbolEffect(.bounce, value: trigger)
            .rotationEffect(.degrees(motion == .spin && hovering ? 90 : 0))
            .scaleEffect(hovering && motion != .spin ? 1.06 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: hovering)
            .onHover { h in
                hovering = h
                if h && !Theme.reduceMotion { hovers += 1 }
            }
    }
}

extension View {
    func animatedIcon(_ motion: IconMotion = .bounce, trigger: AnyHashable? = nil) -> some View {
        modifier(AnimatedIcon(motion: motion, trigger: trigger))
    }
}

/// Copy button that morphs into a checkmark for a moment.
struct CopyIconButton: View {
    var text: () -> String
    var size: CGFloat = 28
    @State private var copied = false
    var body: some View {
        Button {
            Clip.copy(text())
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { copied = false } }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(copied ? Theme.success : Theme.text2)
        }
        .buttonStyle(CircleButtonStyle(size: size))
        .animatedIcon()
        .help("Copy")
        .accessibilityLabel(copied ? "Copied" : "Copy")
    }
}
