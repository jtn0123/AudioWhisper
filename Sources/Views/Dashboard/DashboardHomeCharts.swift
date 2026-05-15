import SwiftUI

// MARK: - Activity timeline (the bar histogram)

internal struct ActivityTimeline: View {
    let values: [Int]          // 28 daily word counts, oldest → newest
    let accent: Color
    let ink: Color
    let rule: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = max(1, values.max() ?? 1)
            let count = max(1, values.count)
            let gap: CGFloat = 4
            let totalGap = gap * CGFloat(count - 1)
            let barW = max(2, (geo.size.width - totalGap) / CGFloat(count))

            HStack(alignment: .center, spacing: gap) {
                ForEach(values.indices, id: \.self) { index in
                    let dayWords = values[index]
                    let isThisWeek = index >= values.count - 7
                    let normalized = max(2.0, CGFloat(dayWords) / CGFloat(maxV) * (geo.size.height - 6))

                    RoundedRectangle(cornerRadius: barW / 2)
                        .fill(dayWords == 0 ? rule : (isThisWeek ? accent : ink.opacity(0.78)))
                        .frame(width: barW, height: normalized)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - MiniSparkline
internal struct MiniSparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            guard values.count >= 2 else {
                return AnyView(EmptyView())
            }
            let maxV = max(1, values.max() ?? 1)
            let step = geo.size.width / CGFloat(values.count - 1)
            let path = Path { linePath in
                for (index, dayWords) in values.enumerated() {
                    let posX = CGFloat(index) * step
                    let posY = geo.size.height - (CGFloat(dayWords) / CGFloat(maxV)) * (geo.size.height - 4) - 2
                    if index == 0 {
                        linePath.move(to: CGPoint(x: posX, y: posY))
                    } else {
                        linePath.addLine(to: CGPoint(x: posX, y: posY))
                    }
                }
            }
            let lastIdx = values.count - 1
            let lastY = geo.size.height - (CGFloat(values[lastIdx]) / CGFloat(maxV)) * (geo.size.height - 4) - 2
            let lastX = CGFloat(lastIdx) * step

            return AnyView(
                ZStack(alignment: .topLeading) {
                    path
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .offset(x: lastX - 3, y: lastY - 3)
                }
            )
        }
    }
}
