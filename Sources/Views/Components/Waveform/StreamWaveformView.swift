import SwiftUI

/// Stream — particles flow horizontally (the direction of text being read).
/// Speed and density scale with audio level. Peaks stretch each particle into
/// a short trail. Reads as "voice → words → text".
struct StreamWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var time: CGFloat = 0
    @State private var isViewActive = false

    // AW palette
    private let coral     = Color(red: 0.85, green: 0.45, blue: 0.30)
    private let coralLite = Color(red: 0.91, green: 0.60, blue: 0.47)
    private let cream     = Color(red: 0.85, green: 0.83, blue: 0.80)

    private let count = 70

    var body: some View {
        Canvas { context, size in
            let level: CGFloat = CGFloat(isActive ? audioLevel : 0.15)
            let speed: CGFloat = 30 + level * 80
            let periodWidth = size.width + 60

            for index in 0..<count {
                let lane = sin(Double(index) * 11.7) * 0.5 + 0.5
                let phaseOffset = CGFloat(index) / CGFloat(count) * periodWidth
                let rawX = (time * speed + phaseOffset).truncatingRemainder(dividingBy: periodWidth)
                let posX = rawX - 30
                let posY = size.height * 0.15 + CGFloat(lane) * size.height * 0.7
                    + CGFloat(sin(Double(time) * 1.5 + Double(index) * 0.7)) * 4

                let baseSize: CGFloat = 1.2 + CGFloat(sin(Double(index) * 3) * 0.5 + 0.5) * 2.4
                let trailLen = level * 8 + 2

                let colorPick = sin(Double(index) * 5.3) * 0.5 + 0.5
                let color: Color =
                    colorPick > 0.85 ? coral :
                    colorPick > 0.5  ? coralLite :
                                       cream

                // Trail
                var trail = Path()
                trail.move(to: CGPoint(x: posX - trailLen, y: posY))
                trail.addLine(to: CGPoint(x: posX, y: posY))
                context.stroke(
                    trail,
                    with: .color(color.opacity(0.2 + Double(level) * 0.3)),
                    style: StrokeStyle(lineWidth: baseSize * 0.5, lineCap: .round)
                )

                // Outer glow
                let glowR: CGFloat = baseSize + 1.5
                let glowRect = CGRect(x: posX - glowR, y: posY - glowR, width: glowR * 2, height: glowR * 2)
                context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.18)))

                // Core
                let coreRect = CGRect(x: posX - baseSize, y: posY - baseSize, width: baseSize * 2, height: baseSize * 2)
                context.fill(Path(ellipseIn: coreRect),
                    with: .color(color.opacity(0.45 + Double(level) * 0.4)))
            }
        }
        .onAppear { isViewActive = true }
        .onDisappear { isViewActive = false }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            guard isViewActive else { return }
            time += 0.033
        }
    }
}

#Preview("Stream") {
    StreamWaveformView(audioLevel: 0.6, isActive: true)
        .frame(width: 320, height: 140)
        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
