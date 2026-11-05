import SwiftUI

/// Canvas painting for the Aurora styles.
///
/// Colour is a horizontal field that crawls left → right. Each mountain samples
/// its own slice of the palette (`lobeBands`), so the three mountains always
/// keep three distinct hues; the crawl only shimmers within each slice.
enum AuroraRenderer {
    typealias Geo = AuroraGeometry
    typealias Band = (low: Double, high: Double)

    /// Fraction of a ping-pong cycle visible across the strip.
    static let span = 0.42
    /// Palette slice per mountain, in stop units (0…4): wide, left, right.
    static let lobeBands: [Band] = [(1.65, 2.35), (0.0, 0.75), (3.25, 4.0)]
    static let fullBand: Band = (0.0, 4.0)
    static let margin: CGFloat = 12

    static func draw(_ shape: AuroraShape, palette: AuroraPalette, engine: AuroraEngine,
                     in context: inout GraphicsContext, size: CGSize) {
        switch shape {
        case .horizon: drawHorizon(palette, engine, &context, size)
        case .lens: drawLens(palette, engine, &context, size)
        }
    }

    // MARK: - Colour field

    /// Colour at strip position u is f(u·span − crawl), so as crawl grows the
    /// pattern moves right. Ping-pong within the band, so it never wraps.
    static func field(_ stops: [AuroraRGB], crawl: Double, band: Band, alpha: Double) -> Gradient {
        Gradient(stops: (0...12).map { step in
            let location = Double(step) / 12
            let phase = location * span - crawl
            let pingPong = 1 - abs(2 * (phase - floor(phase)) - 1)
            let color = AuroraPalette.sample(stops, at: band.low + (band.high - band.low) * pingPong)
            return .init(color: color.color(alpha), location: location)
        })
    }

    static func across(_ gradient: Gradient, _ size: CGSize) -> GraphicsContext.Shading {
        .linearGradient(gradient, startPoint: CGPoint(x: margin, y: 0),
                        endPoint: CGPoint(x: size.width - margin, y: 0))
    }

    static func alphaRamp(_ pairs: [(Double, Double)]) -> Gradient {
        Gradient(stops: pairs.map { .init(color: .white.opacity($0.0), location: $0.1) })
    }

    // MARK: - Primitives

    /// Additively fill `path` with a horizontal field whose alpha is shaped
    /// vertically by `mask`, running from `rows.lowerBound` (top) to `rows.upperBound`.
    static func fill2D(_ context: inout GraphicsContext, _ path: Path, field: GraphicsContext.Shading,
                       mask: Gradient, rows: ClosedRange<CGFloat>) {
        var glass = context
        glass.blendMode = .plusLighter
        let bounds = path.boundingRect.insetBy(dx: -2, dy: -2)
        glass.drawLayer { layer in
            layer.fill(path, with: field)
            layer.blendMode = .destinationIn
            layer.fill(Path(bounds), with: .linearGradient(mask, startPoint: CGPoint(x: 0, y: rows.lowerBound),
                                                            endPoint: CGPoint(x: 0, y: rows.upperBound)))
        }
    }

    static let rimWidth: CGFloat = 1.15

    /// Stroke with the colour field, faded toward the mountain's tips.
    static func rim(_ context: inout GraphicsContext, _ path: Path, field: GraphicsContext.Shading,
                    size: CGSize, lobe: Int) {
        let center = AuroraLobes.centers[lobe], spread = AuroraLobes.spreads[lobe]
        let low = max(0, center - spread), high = min(1, center + spread)
        let tips = alphaRamp([(0, low), (0.85, low + (center - low) * 0.45), (1, center),
                              (0.85, center + (high - center) * 0.55), (0, high)])
        context.drawLayer { layer in
            layer.stroke(path, with: field, style: StrokeStyle(lineWidth: rimWidth, lineCap: .round, lineJoin: .round))
            layer.blendMode = .destinationIn
            layer.fill(Path(CGRect(origin: .zero, size: size)), with: across(tips, size))
        }
    }

    /// A soft white band travelling left → right along the upper rim.
    static func glint(_ context: inout GraphicsContext, _ path: Path, at position: Double,
                      alpha: Double, size: CGSize) {
        let center = position - 0.2   // 1.4 cycle → band fully off-strip between passes
        guard alpha > 0.01, center > -0.1, center < 1.1 else { return }
        func clamp(_ value: Double) -> Double { max(0, min(1, value)) }
        let band = Gradient(stops: [.init(color: .white.opacity(0), location: clamp(center - 0.10)),
                                    .init(color: .white.opacity(alpha), location: clamp(center)),
                                    .init(color: .white.opacity(0), location: clamp(center + 0.10))])
        var light = context
        light.blendMode = .plusLighter
        light.stroke(path, with: across(band, size), style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
    }

    /// Hairline horizon / axis that fades out toward both ends.
    static func axis(_ context: inout GraphicsContext, _ size: CGSize, mid: CGFloat, field: Gradient) {
        let rect = CGRect(x: margin, y: mid - 0.5, width: size.width - margin * 2, height: 1)
        context.drawLayer { layer in
            layer.fill(Path(rect), with: across(field, size))
            layer.blendMode = .destinationIn
            layer.fill(Path(rect), with: across(alphaRamp([(0, 0), (1, 0.14), (1, 0.86), (0, 1)]), size))
        }
    }
}

// MARK: - Shapes

extension AuroraRenderer {
    /// Horizon: mountains rise off a glowing horizon, with a short reflection
    /// below that keeps a brief afterglow. Bright crest hue over a deeper base.
    static func drawHorizon(_ palette: AuroraPalette, _ engine: AuroraEngine,
                            _ context: inout GraphicsContext, _ size: CGSize) {
        let mid = (size.height * 0.60).rounded()
        let upMax = size.height * 0.52, downMax = size.height * 0.30
        let xs = Geo.xs(size, margin: margin), crawl = engine.crawl
        let zero = [CGFloat](repeating: 0, count: Geo.steps + 1)
        let reflectionMask = alphaRamp([(0.48, 0), (0.13, 0.5), (0, 1)])
        for lobe in 0..<3 {
            let down = Geo.scaled(Geo.profile(engine.glow, lobe: lobe), downMax)
            let deep = across(field(palette.deep, crawl: crawl, band: lobeBands[lobe], alpha: 1), size)
            fill2D(&context, Geo.lens(xs, mid: mid, up: zero, down: down), field: deep,
                   mask: reflectionMask, rows: mid...(mid + downMax))
        }
        axis(&context, size, mid: mid, field: field(palette.crest, crawl: crawl, band: fullBand, alpha: 0.55))
        for lobe in 0..<3 {
            let up = Geo.scaled(Geo.profile(engine.values, lobe: lobe), upMax)
            let peak = max(1, up.max() ?? 1)
            let shape = Geo.lens(xs, mid: mid, up: up, down: zero)
            let crest = across(field(palette.crest, crawl: crawl, band: lobeBands[lobe], alpha: 1), size)
            let deep = across(field(palette.deep, crawl: crawl, band: lobeBands[lobe], alpha: 1), size)
            fill2D(&context, shape, field: crest, mask: alphaRamp([(0.50, 0), (0.10, 1)]), rows: (mid - peak)...mid)
            fill2D(&context, shape, field: deep, mask: alphaRamp([(0.06, 0), (0.30, 1)]), rows: (mid - peak)...mid)
            rim(&context, Geo.edge(xs, mid: mid, offsets: up), field: crest, size: size, lobe: lobe)
            guard peak > 6 else { continue }
            let inset = up.map { max(0, $0 - min(3.0, $0 * 0.2)) }
            glint(&context, Geo.edge(xs, mid: mid, offsets: inset), at: engine.glint,
                  alpha: 0.42 * min(1, Double(peak - 6) / 10), size: size)
        }
    }

    /// Lens: mirrored glass mountains; the rim hue melts into a deeper,
    /// hue-shifted core toward the centre line.
    static func drawLens(_ palette: AuroraPalette, _ engine: AuroraEngine,
                         _ context: inout GraphicsContext, _ size: CGSize) {
        let mid = size.height / 2, maxHalf = size.height * 0.44
        let xs = Geo.xs(size, margin: margin), crawl = engine.crawl
        let edgeMask = alphaRamp([(0.44, 0), (0.06, 0.4), (0, 0.5), (0.06, 0.6), (0.44, 1)])
        let coreMask = alphaRamp([(0.04, 0), (0.24, 0.34), (0.14, 0.5), (0.24, 0.66), (0.04, 1)])
        axis(&context, size, mid: mid, field: field(palette.crest, crawl: crawl, band: fullBand, alpha: 0.32))
        for lobe in 0..<3 {
            let half = Geo.scaled(Geo.profile(engine.values, lobe: lobe), maxHalf)
            let peak = max(1, half.max() ?? 1)
            let shape = Geo.lens(xs, mid: mid, up: half, down: half)
            let crest = across(field(palette.crest, crawl: crawl, band: lobeBands[lobe], alpha: 1), size)
            let deep = across(field(palette.deep, crawl: crawl, band: lobeBands[lobe], alpha: 1), size)
            fill2D(&context, shape, field: crest, mask: edgeMask, rows: (mid - peak)...(mid + peak))
            fill2D(&context, shape, field: deep, mask: coreMask, rows: (mid - peak)...(mid + peak))
            rim(&context, shape, field: crest, size: size, lobe: lobe)
            guard peak > 6 else { continue }
            let inset = half.map { max(0, $0 - min(3.2, $0 * 0.22)) }
            glint(&context, Geo.edge(xs, mid: mid, offsets: inset), at: engine.glint,
                  alpha: 0.40 * min(1, Double(peak - 6) / 10), size: size)
        }
    }
}
