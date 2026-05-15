import SwiftUI

/// Halo — 28 fine bars in slow continuous rotation, ember-to-cream gradient
/// mapped around the ring. Center hub pulses with audio level.
struct HaloWaveformView: View {
    let frequencyBands: [Float]
    let audioLevel: Float
    let isActive: Bool

    @State private var t: CGFloat = 0
    @State private var isViewActive = false

    private let barCount = 28
    private let coral = Color(red: 0.85, green: 0.45, blue: 0.30)

    // Ember → cream palette, applied around the circle
    private let palette: [Color] = [
        Color(red: 0.48, green: 0.16, blue: 0.08),  // #7A2A14
        Color(red: 0.63, green: 0.23, blue: 0.11),  // #A03A1C
        Color(red: 0.76, green: 0.31, blue: 0.16),  // #C24E29
        Color(red: 0.85, green: 0.45, blue: 0.30),  // #D9734D
        Color(red: 0.91, green: 0.60, blue: 0.47),  // #E89A77
        Color(red: 0.95, green: 0.75, blue: 0.63),  // #F2BFA0
        Color(red: 0.94, green: 0.84, blue: 0.76),  // #F0D7C2
        Color(red: 0.90, green: 0.85, blue: 0.80),  // #E6D9CC
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let rIn = size * 0.13
            let rMax = size * 0.43

            ZStack {
                // Ambient hub glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [coral.opacity(0.55), coral.opacity(0.18), coral.opacity(0)],
                            center: .center, startRadius: 0, endRadius: size * 0.48
                        )
                    )
                    .frame(width: size, height: size)

                // Center hub
                Circle()
                    .fill(Color(red: 0.087, green: 0.078, blue: 0.071))  // #161412
                    .frame(width: (rIn - 2) * 2, height: (rIn - 2) * 2)

                Circle()
                    .stroke(coral.opacity(0.3 + Double(audioLevel) * 0.4), lineWidth: 0.6)
                    .frame(width: (rIn - 2) * 2, height: (rIn - 2) * 2)

                // Audio-reactive inner glow
                Circle()
                    .fill(coral.opacity(0.45))
                    .frame(
                        width: (rIn - 2) * 2 * (0.4 + CGFloat(audioLevel) * 0.3),
                        height: (rIn - 2) * 2 * (0.4 + CGFloat(audioLevel) * 0.3)
                    )
                    .blur(radius: 4)

                // Rotating bars (drawn via Canvas for performance)
                Canvas { context, canvasSize in
                    let cp = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let rotation = t * 0.15
                    let bandCount = frequencyBands.count

                    for i in 0..<barCount {
                        let a = (CGFloat(i) / CGFloat(barCount)) * 2 * .pi - .pi / 2 + rotation
                        let bandIdx = (Int((Double(i) / Double(barCount)) * Double(bandCount))) % max(1, bandCount)
                        let v: CGFloat = bandCount > 0 ? CGFloat(frequencyBands[bandIdx]) : 0
                        let len = rIn + (rMax - rIn) * (0.3 + v * 0.85)

                        let x1 = cp.x + cos(a) * rIn
                        let y1 = cp.y + sin(a) * rIn
                        let x2 = cp.x + cos(a) * len
                        let y2 = cp.y + sin(a) * len

                        let angleFrac = (Double(i) / Double(barCount) + Double(t) * 0.02).truncatingRemainder(dividingBy: 1)
                        let palIdx = Int(angleFrac * Double(palette.count))
                        let c = palette[min(palIdx, palette.count - 1)]

                        // Glow stroke
                        var glow = Path()
                        glow.move(to: CGPoint(x: x1, y: y1))
                        glow.addLine(to: CGPoint(x: x2, y: y2))
                        context.stroke(
                            glow,
                            with: .color(c.opacity(0.35)),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )

                        // Core stroke
                        var core = Path()
                        core.move(to: CGPoint(x: x1, y: y1))
                        core.addLine(to: CGPoint(x: x2, y: y2))
                        context.stroke(
                            core,
                            with: .color(c),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                    }
                }
                .blur(radius: 0.5)
            }
            .position(center)
        }
        .onAppear { isViewActive = true }
        .onDisappear { isViewActive = false }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            guard isViewActive else { return }
            t += 0.033
        }
    }
}

#Preview("Halo") {
    HaloWaveformView(
        frequencyBands: [0.7, 0.5, 0.4, 0.6, 0.3, 0.45, 0.25, 0.35],
        audioLevel: 0.5,
        isActive: true
    )
    .frame(width: 220, height: 220)
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
