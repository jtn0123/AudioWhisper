import SwiftUI

/// Mountain outlines for the Aurora styles: a rounded-crest window over each
/// mountain's value buckets, sampled on a fixed horizontal grid.
enum AuroraGeometry {
    static let steps = 56
    /// How far between-bucket interpolation moves from a cosine ease toward a
    /// cubic B-spline (both stay inside the knots' range, so no overshoot).
    private static let knotBlend = 0.6
    /// Broadens and rounds the crest while the tails stay tangent to the axis.
    private static let crestShape = 1.15

    /// One mountain's values, sliced out of the concatenated array.
    static func lobe(_ values: [Double], _ lobe: Int) -> [Double] {
        let start = AuroraLobes.offset(of: lobe)
        return Array(values[start..<(start + AuroraLobes.sizes[lobe])])
    }

    /// Normalised half-height (0…1) of one mountain on the path grid.
    static func profile(_ values: [Double], lobe: Int) -> [Double] {
        let slice = Self.lobe(values, lobe)
        let center = AuroraLobes.centers[lobe], spread = AuroraLobes.spreads[lobe]
        return (0...steps).map { step in
            let position = Double(step) / Double(steps)
            let scaled = position * Double(slice.count - 1)
            let index = min(slice.count - 2, Int(scaled))
            let distance = min(1, abs(position - center) / spread)
            return window(distance) * value(slice, index, scaled - Double(index))
        }
    }

    static func xs(_ size: CGSize, margin: CGFloat) -> [CGFloat] {
        (0...steps).map { margin + (size.width - 2 * margin) * CGFloat($0) / CGFloat(steps) }
    }

    /// Closed shape: upper edge at mid − up[i], lower edge at mid + down[i].
    static func lens(_ xs: [CGFloat], mid: CGFloat, up: [CGFloat], down: [CGFloat]) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: xs[0], y: mid))
        appendSmooth(&path, zip(xs, up).map { CGPoint(x: $0, y: mid - $1) })
        appendSmooth(&path, zip(xs, down).reversed().map { CGPoint(x: $0, y: mid + $1) })
        path.closeSubpath()
        return path
    }

    /// Open upper edge only, for rims and glints.
    static func edge(_ xs: [CGFloat], mid: CGFloat, offsets: [CGFloat]) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: xs[0], y: mid))
        appendSmooth(&path, zip(xs, offsets).map { CGPoint(x: $0, y: mid - $1) })
        return path
    }

    static func scaled(_ profile: [Double], _ factor: CGFloat) -> [CGFloat] {
        profile.map { CGFloat($0) * factor }
    }

    // MARK: - Private

    private static func window(_ distance: Double) -> Double {
        pow(max(0, cos(pow(distance, crestShape) * .pi / 2)), 1.4)
    }

    private static func value(_ knots: [Double], _ index: Int, _ fraction: Double) -> Double {
        let low = knots[index], high = knots[index + 1]
        let eased = low + (high - low) * (1 - cos(fraction * .pi)) / 2
        return eased + (bspline(knots, index, fraction) - eased) * knotBlend
    }

    /// Uniform cubic B-spline; ends clamp by repeating the first/last knot.
    private static func bspline(_ knots: [Double], _ index: Int, _ fraction: Double) -> Double {
        func knot(_ offset: Int) -> Double { knots[min(knots.count - 1, max(0, index + offset))] }
        let squared = fraction * fraction, cubed = squared * fraction, rest = 1 - fraction
        return (rest * rest * rest * knot(-1) + (3 * cubed - 6 * squared + 4) * knot(0)
            + (-3 * cubed + 3 * squared + 3 * fraction + 1) * knot(1) + cubed * knot(2)) / 6
    }

    /// Catmull-Rom through `points`, continuing the current subpath.
    private static func appendSmooth(_ path: inout Path, _ points: [CGPoint]) {
        guard points.count > 1 else { return }
        path.addLine(to: points[0])
        for index in 0..<(points.count - 1) {
            let before = points[max(0, index - 1)], start = points[index]
            let end = points[index + 1], after = points[min(points.count - 1, index + 2)]
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + (end.x - before.x) / 6, y: start.y + (end.y - before.y) / 6),
                          control2: CGPoint(x: end.x - (after.x - start.x) / 6, y: end.y - (after.y - start.y) / 6))
        }
    }
}
