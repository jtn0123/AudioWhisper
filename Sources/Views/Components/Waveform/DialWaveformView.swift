import SwiftUI

/// Dial — Apple-Watch-style audio energy dial. 36 perimeter dots brighten
/// with band activity; a coral progress arc tracks total audio energy; a
/// soft cream-coral central orb scales with overall level.
struct DialWaveformView: View {
    let frequencyBands: [Float]
    let audioLevel: Float
    let isActive: Bool

    @State private var time: CGFloat = 0
    @State private var frameTimer = FrameTimer(interval: 0.033)

    private let dotCount = 36
    private let coral     = Color(red: 0.85, green: 0.45, blue: 0.30)
    private let coralDeep = Color(red: 0.70, green: 0.34, blue: 0.23)
    private let coralLite = Color(red: 0.91, green: 0.60, blue: 0.47)
    private let cream     = Color(red: 0.85, green: 0.83, blue: 0.80)

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let ringR = size * 0.4
            let coreR = size * 0.18 + CGFloat(audioLevel) * size * 0.04

            ZStack {
                // Static arc track
                Circle()
                    .stroke(cream.opacity(0.06), lineWidth: 2)
                    .frame(width: ringR * 2, height: ringR * 2)

                // Progress arc — total band energy
                ProgressArc(energy: averageEnergy, ringR: ringR, coralLite: coralLite, coral: coral)
                    .stroke(
                        LinearGradient(colors: [coralLite, coral], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: ringR * 2, height: ringR * 2)

                // Tick dots — band-driven brightness
                Canvas { context, canvasSize in
                    let cp = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    // CRASH FIX: this was `max(1, frequencyBands.count)`, which
                    // was presumably meant to avoid a modulo-by-zero. It does
                    // the opposite of protecting the subscript: with an EMPTY
                    // `frequencyBands`, bandCount becomes 1, `index % 1` is 0,
                    // and `frequencyBands[0]` traps with "Index out of range".
                    // `frequencyBands` is empty whenever no audio has been
                    // analysed yet — i.e. every time this style renders at rest,
                    // which is exactly what the WelcomeView snapshot hit.
                    // Matches the guard HaloWaveformView already uses.
                    let bandCount = frequencyBands.count
                    for index in 0..<dotCount {
                        let angle = (CGFloat(index) / CGFloat(dotCount)) * 2 * .pi - .pi / 2
                        let value: CGFloat = bandCount > 0 ? CGFloat(frequencyBands[index % bandCount]) : 0
                        let brightness = 0.15 + Double(value) * 0.7
                        let dx = cp.x + cos(angle) * ringR
                        let dy = cp.y + sin(angle) * ringR
                        let radius: CGFloat = 1.2 + value * 1.2
                        context.fill(
                            Path(ellipseIn: CGRect(x: dx - radius, y: dy - radius, width: radius * 2, height: radius * 2)),
                            with: .color(cream.opacity(brightness))
                        )
                    }
                }

                // Soft core glow
                Circle()
                    .fill(coral.opacity(0.3))
                    .frame(width: (coreR + 4) * 2, height: (coreR + 4) * 2)
                    .blur(radius: 6)

                // Central orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [cream.opacity(0.95), coral.opacity(0.7), coralDeep.opacity(0.1)],
                            center: .center, startRadius: 0, endRadius: coreR
                        )
                    )
                    .frame(width: coreR * 2, height: coreR * 2)

                // Highlight
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: coreR * 0.5, height: coreR * 0.5)
                    .offset(x: -coreR * 0.3, y: -coreR * 0.3)
            }
            .position(center)
        }
        .onAppear { frameTimer.start() }
        .onDisappear { frameTimer.stop() }
        .onReceive(frameTimer.publisher) { _ in
            time += 0.033
        }
    }

    private var averageEnergy: Double {
        guard !frequencyBands.isEmpty else { return 0 }
        let sum = frequencyBands.reduce(0, +)
        return Double(sum) / Double(frequencyBands.count)
    }
}

private struct ProgressArc: Shape {
    let energy: Double
    let ringR: CGFloat
    let coralLite: Color
    let coral: Color

    func path(in rect: CGRect) -> Path {
        var arcPath = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Sweep up to 324° (1.8π) with full energy
        let sweep = energy * .pi * 1.8
        let start: Angle = .degrees(-90)
        let end: Angle = .degrees(-90 + sweep * 180 / .pi)
        arcPath.addArc(center: center, radius: ringR, startAngle: start, endAngle: end, clockwise: false)
        return arcPath
    }
}

#Preview("Dial") {
    DialWaveformView(
        frequencyBands: [0.8, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15],
        audioLevel: 0.5,
        isActive: true
    )
    .frame(width: 220, height: 220)
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
