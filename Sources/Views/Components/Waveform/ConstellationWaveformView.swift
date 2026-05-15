import SwiftUI

/// Constellation — drifting nodes with proximity-based connections.
/// Audio peaks brighten the whole network. Meditative, ambient.
struct ConstellationWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var t: CGFloat = 0
    @State private var isViewActive = false

    private let count = 18
    private let coral = Color(red: 0.85, green: 0.45, blue: 0.30)
    private let cream = Color(red: 0.85, green: 0.83, blue: 0.80)

    var body: some View {
        Canvas { context, size in
            let level: CGFloat = CGFloat(isActive ? audioLevel : 0.20)
            let proximity = min(size.width, size.height) * 0.45

            // Build node positions
            var nodes: [CGPoint] = []
            for i in 0..<count {
                let homeX = (sin(Double(i) * 9.71 + 1) * 0.5 + 0.5) * Double(size.width - 24) + 12
                let homeY = (sin(Double(i) * 13.41 + 2) * 0.5 + 0.5) * Double(size.height - 24) + 12
                let driftR = 8 + (sin(Double(i) * 3) * 0.5 + 0.5) * 6
                let driftSpeed = 0.5 + (sin(Double(i) * 7) * 0.5 + 0.5) * 0.4
                let x = homeX + cos(Double(t) * driftSpeed + Double(i)) * driftR
                let y = homeY + sin(Double(t) * driftSpeed * 1.3 + Double(i)) * driftR
                nodes.append(CGPoint(x: x, y: y))
            }

            // Edges
            let linkAlpha = 0.15 + Double(level) * 0.5
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let dx = nodes[i].x - nodes[j].x
                    let dy = nodes[i].y - nodes[j].y
                    let d = sqrt(dx * dx + dy * dy)
                    if d < proximity {
                        let closeness = 1 - d / proximity
                        var p = Path()
                        p.move(to: nodes[i])
                        p.addLine(to: nodes[j])
                        context.stroke(
                            p,
                            with: .color(coral.opacity(Double(closeness) * linkAlpha)),
                            style: StrokeStyle(lineWidth: 0.8)
                        )
                    }
                }
            }

            // Nodes
            for n in nodes {
                let glowR: CGFloat = 4
                context.fill(
                    Path(ellipseIn: CGRect(x: n.x - glowR, y: n.y - glowR, width: glowR * 2, height: glowR * 2)),
                    with: .color(cream.opacity(0.18))
                )
                let r: CGFloat = 1.8 + level * 1.2
                context.fill(
                    Path(ellipseIn: CGRect(x: n.x - r, y: n.y - r, width: r * 2, height: r * 2)),
                    with: .color(cream.opacity(0.6 + Double(level) * 0.4))
                )
            }
        }
        .onAppear { isViewActive = true }
        .onDisappear { isViewActive = false }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            guard isViewActive else { return }
            t += 0.033
        }
    }
}

#Preview("Constellation") {
    ConstellationWaveformView(audioLevel: 0.5, isActive: true)
        .frame(width: 320, height: 140)
        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
