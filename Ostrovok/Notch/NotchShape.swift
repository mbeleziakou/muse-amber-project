import SwiftUI

/// Black shape growing out of the notch: concave "ears" on top, rounded bottom.
/// Drawn centred on the top edge of its rect.
struct NotchShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var ear: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(width, height), .init(radius, ear)) }
        set {
            width = newValue.first.first
            height = newValue.first.second
            radius = newValue.second.first
            ear = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = max(0, width), h = max(0, height)
        let e = max(0, min(ear, h / 2))
        let r = max(0, min(radius, h - e, w / 2))
        let x0 = rect.midX - w / 2, x1 = rect.midX + w / 2, top = rect.minY
        var p = Path()
        p.move(to: CGPoint(x: x0 - e, y: top))
        p.addQuadCurve(to: CGPoint(x: x0, y: top + e), control: CGPoint(x: x0, y: top))
        p.addLine(to: CGPoint(x: x0, y: top + h - r))
        p.addQuadCurve(to: CGPoint(x: x0 + r, y: top + h), control: CGPoint(x: x0, y: top + h))
        p.addLine(to: CGPoint(x: x1 - r, y: top + h))
        p.addQuadCurve(to: CGPoint(x: x1, y: top + h - r), control: CGPoint(x: x1, y: top + h))
        p.addLine(to: CGPoint(x: x1, y: top + e))
        p.addQuadCurve(to: CGPoint(x: x1 + e, y: top), control: CGPoint(x: x1, y: top))
        p.closeSubpath()
        return p
    }
}
