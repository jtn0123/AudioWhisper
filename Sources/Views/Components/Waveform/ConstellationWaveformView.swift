import SwiftUI

/// Constellation — drifting nodes with proximity-based connections.
/// Audio peaks brighten the whole network. Meditative, ambient.
struct ConstellationWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var time: CGFloat = 0
    @State private var frameTimer = FrameTimer(interval: 0.033)

    private let count = 18
    private let coral = Color(red: 0.85, green: 0.45, blue: 0.30)
    private let cream = Color(red: 0.85, green: 0.83, blue: 0.80)

    var body: some View {
        Canvas { context, size in
            let level: CGFloat = CGFloat(isActive ? audioLevel : 0.20)
            let proximity = min(size.width, size.height) * 0.45

            // Build node positions
            var nodes: [CGPoint] = []
            for index in 0..<count {
                let homeX = (sin(Double(index) * 9.71 + 1) * 0.5 + 0.5) * Double(size.width - 24) + 12
                let homeY = (sin(Double(index) * 13.41 + 2) * 0.5 + 0.5) * Double(size.height - 24) + 12
                let driftR = 8 + (sin(Double(index) * 3) * 0.5 + 0.5) * 6
                let driftSpeed = 0.5 + (sin(Double(index) * 7) * 0.5 + 0.5) * 0.4
                let posX = homeX + cos(Double(time) * driftSpeed + Double(index)) * driftR
                let posY = homeY + sin(Double(time) * driftSpeed * 1.3 + Double(index)) * driftR
                nodes.append(CGPoint(x: posX, y: posY))
            }

            // Edges
            let linkAlpha = 0.15 + Double(level) * 0.5
            for index in 0..<count {
                for other in (index + 1)..<count {
                    let dx = nodes[index].x - nodes[other].x
                    let dy = nodes[index].y - nodes[other].y
                    let distance = sqrt(dx * dx + dy * dy)
                    if distance < proximity {
                        let closeness = 1 - distance / proximity
                        var edgePath = Path()
                        edgePath.move(to: nodes[index])
                        edgePath.addLine(to: nodes[other])
                        context.stroke(
                            edgePath,
                            with: .color(coral.opacity(Double(closeness) * linkAlpha)),
                            style: StrokeStyle(lineWidth: 0.8)
                        )
                    }
                }
            }

            // Nodes
            for node in nodes {
                let glowR: CGFloat = 4
                context.fill(
                    Path(ellipseIn: CGRect(x: node.x - glowR, y: node.y - glowR, width: glowR * 2, height: glowR * 2)),
                    with: .color(cream.opacity(0.18))
                )
                let radius: CGFloat = 1.8 + level * 1.2
                context.fill(
                    Path(ellipseIn: CGRect(x: node.x - radius, y: node.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(cream.opacity(0.6 + Double(level) * 0.4))
                )
            }
        }
        .onAppear { frameTimer.start() }
        .onDisappear { frameTimer.stop() }
        .onReceive(frameTimer.publisher) { _ in
            time += 0.033
        }
    }
}

#Preview("Constellation") {
    ConstellationWaveformView(audioLevel: 0.5, isActive: true)
        .frame(width: 320, height: 140)
        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
