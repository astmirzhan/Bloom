import SwiftUI

/// A slice of a ring with rounded corners: the selection pill and the
/// sub-ring. Angles are radians clockwise from 12 o'clock (as in
/// `RadialGeometry`); the shape is centred in its rect.
struct BandShape: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var startAngle: Double
    var endAngle: Double
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        Self.path(center: CGPoint(x: rect.midX, y: rect.midY), inner: innerRadius, outer: outerRadius,
                  from: startAngle, to: endAngle, corner: cornerRadius)
    }

    /// The band between two radii and two angles, corners rounded by up to
    /// `corner` points (less when the band is too thin or too short).
    static func path(center: CGPoint, inner: CGFloat, outer: CGFloat, from start: Double, to end: Double,
                     corner: CGFloat) -> Path {
        let point = { (angle: Double, radius: CGFloat) in
            RadialGeometry.viewPoint(angle: angle, radius: radius, center: center)
        }
        let sweep = end - start
        let c = max(0, min(corner, (outer - inner) / 2, CGFloat(sweep) * inner / 2 - 0.5))
        let outerTrim = Double(c / outer), innerTrim = Double(c / max(inner, 1))

        var path = Path()
        path.move(to: point(start + outerTrim, outer))
        addArc(&path, center: center, radius: outer, from: start + outerTrim, to: end - outerTrim)
        path.addQuadCurve(to: point(end, outer - c), control: point(end, outer))
        path.addLine(to: point(end, inner + c))
        path.addQuadCurve(to: point(end - innerTrim, inner), control: point(end, inner))
        addArc(&path, center: center, radius: inner, from: end - innerTrim, to: start + innerTrim)
        path.addQuadCurve(to: point(start, inner + c), control: point(start, inner))
        path.addLine(to: point(start, outer - c))
        path.addQuadCurve(to: point(start + outerTrim, outer), control: point(start, outer))
        path.closeSubpath()
        return path
    }

    /// Lines along an arc, one segment per 2°: smooth at these sizes.
    private static func addArc(_ path: inout Path, center: CGPoint, radius: CGFloat, from start: Double, to end: Double) {
        let steps = max(1, Int(abs(end - start) / (.pi / 90)))
        for k in 1...steps {
            let angle = start + (end - start) * Double(k) / Double(steps)
            path.addLine(to: RadialGeometry.viewPoint(angle: angle, radius: radius, center: center))
        }
    }
}

extension BandShape {
    /// The petal for slice `index` of `count`: inside the disc's
    /// rim, with an even gap to its neighbours. The glass and the paint on
    /// top both use this, so they line up exactly.
    static func petal(_ index: Int, of count: Int, geometry g: RadialGeometry) -> BandShape {
        let span = g.span(count: count)
        let mid = g.centerAngle(ofSlice: index, count: count)
        let (inner, outer) = petalRadii(g)
        let halfGap = count > 1 ? Double(WheelTheme.petalGap / 2 / ((inner + outer) / 2)) : 0
        return BandShape(innerRadius: inner, outerRadius: outer, startAngle: mid - span / 2 + halfGap,
                         endAngle: mid + span / 2 - halfGap, cornerRadius: WheelTheme.petalCorner)
    }

    /// Where a petal's label sits: halfway between its inner and outer edges.
    static func petalLabelRadius(_ g: RadialGeometry) -> CGFloat {
        let (inner, outer) = petalRadii(g)
        return (inner + outer) / 2
    }

    /// A petal's inner and outer edges: just outside the centre well, and
    /// `petalRim` inside the disc's edge.
    static func petalRadii(_ g: RadialGeometry) -> (inner: CGFloat, outer: CGFloat) {
        (g.innerRadius + 4, g.outerRadius - WheelTheme.petalRim)
    }
}

extension WheelAccent {
    var color: Color { Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }
}
