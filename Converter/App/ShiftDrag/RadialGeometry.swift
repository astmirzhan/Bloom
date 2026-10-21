import CoreGraphics
import Foundation

/// Sizes of the radial menu and the maths that maps a point to a slice.
///
/// Angles are in radians, measured clockwise from 12 o'clock; slice 0 is
/// centred at the top. Points are relative to the ring's centre with y up
/// (AppKit's convention). The SwiftUI view, which has y down, flips y.
struct RadialGeometry: Equatable {
    var innerRadius: CGFloat = 54
    var outerRadius: CGFloat = 148
    var subInnerRadius: CGFloat = 154
    var subOuterRadius: CGFloat = 220
    /// Widest a sub-ring slice may be (about 28°).
    var maxSubSpan: Double = .pi / 6.5
    /// Extra reach beyond the sub-ring that still counts as inside it.
    var subSlack: CGFloat = 16

    /// Side of the square window that holds the ring and its sub-ring.
    var panelSide: CGFloat { 2 * (subOuterRadius + subSlack) }

    enum Hit: Equatable {
        /// The hole in the middle: dropping there cancels.
        case center
        case slice(Int)
        case subSlice(Int)
        case outside
    }

    func span(count: Int) -> Double {
        2 * .pi / Double(max(count, 1))
    }

    func centerAngle(ofSlice index: Int, count: Int) -> Double {
        Double(index) * span(count: count)
    }

    func subSpan(members: Int) -> Double {
        min(maxSubSpan, 2 * .pi / Double(max(members, 1)))
    }

    /// Centre angle of member `index` of a sub-ring fanned out around the
    /// parent slice's centre.
    func subCenterAngle(member index: Int, members: Int, parent: Int, count: Int) -> Double {
        let s = subSpan(members: members)
        return centerAngle(ofSlice: parent, count: count) - s * Double(members) / 2 + s * (Double(index) + 0.5)
    }

    /// What's under `point`. `openGroup` is the slice whose sub-ring is open
    /// and how many members it has.
    func hit(_ point: CGPoint, count: Int, openGroup: (parent: Int, members: Int)? = nil) -> Hit {
        let radius = hypot(point.x, point.y)
        let angle = Self.clockwiseAngle(of: point)
        if radius < innerRadius { return .center }
        if radius < subInnerRadius {
            guard count > 0 else { return .outside }
            let s = span(count: count)
            return .slice(Int(((angle + s / 2) / s).rounded(.down)) % count)
        }
        if let group = openGroup, group.members > 0, radius <= subOuterRadius + subSlack {
            let s = subSpan(members: group.members)
            let offset = Self.signedDifference(angle, centerAngle(ofSlice: group.parent, count: count))
                + s * Double(group.members) / 2
            if offset >= 0 && offset < s * Double(group.members) {
                return .subSlice(min(Int(offset / s), group.members - 1))
            }
        }
        return .outside
    }

    /// Clockwise angle from 12 o'clock of a y-up point, in [0, 2π).
    static func clockwiseAngle(of point: CGPoint) -> Double {
        let angle = atan2(Double(point.x), Double(point.y))
        return angle < 0 ? angle + 2 * .pi : angle
    }

    /// `a - b`, wrapped into (-π, π].
    static func signedDifference(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d <= -.pi { d += 2 * .pi }
        return d
    }

    /// A point at `angle` and `radius` in y-down view coordinates around `center`.
    static func viewPoint(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
    }
}

/// How the wheel looks. Classic is Bloom's own: one glass disc with thin
/// dividers. Petals is a smaller disc holding separate light petals,
/// lit orange under the pointer, with a tick as the pointer reaches one.
enum WheelTheme: String, CaseIterable, Identifiable {
    case classic, petals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .petals: return "Petals"
        }
    }

    var geometry: RadialGeometry {
        switch self {
        case .classic: return RadialGeometry()
        case .petals: return RadialGeometry(innerRadius: 50, outerRadius: 125, subInnerRadius: 131, subOuterRadius: 197)
        }
    }

    // Sizes in points.
    /// Band of grey glass between a petal's outer edge and the disc's rim.
    static let petalRim: CGFloat = 10
    /// Gap between neighbouring petals, measured at mid-petal.
    static let petalGap: CGFloat = 6
    /// Larger pinches the petal's short inner edge into a waist.
    static let petalCorner: CGFloat = 11
}

/// The Petals style's highlight colour: the petal under the pointer, an
/// open group, the chosen sub-ring item and the current ring's dot.
enum WheelAccent: String, CaseIterable, Identifiable {
    case blue, burgundy, orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .burgundy: return "Burgundy"
        case .blue: return "Blue"
        case .orange: return "Orange"
        }
    }

    /// sRGB: a sky blue #3E9BF2 (deep enough for white text), a deep wine
    /// #9E2945, a warm orange #FF6A1A.
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .burgundy: return (0.62, 0.16, 0.27)
        case .blue: return (0.24, 0.61, 0.95)
        case .orange: return (1.0, 0.42, 0.1)
        }
    }
}
