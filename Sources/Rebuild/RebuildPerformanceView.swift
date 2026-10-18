import SwiftUI

struct RebuildPerformanceView: View {
    let timing: RebuildSessionTiming

    var body: some View {
        RebuildFormRow(label: "Last dictation") {
            HStack(spacing: 18) {
                measurement("Microphone start", timing.startupMilliseconds)
                measurement("Transcription", timing.processingMilliseconds)
                measurement("Stop to delivery", timing.deliveryMilliseconds)
            }
            Text(timing.delivery).font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            Text("Measured on this Mac for the latest session only. Includes writing cleanup when enabled. Nothing is uploaded.")
                .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func measurement(_ label: String, _ milliseconds: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(milliseconds.map { $0 < 1000 ? "\(Int($0.rounded())) ms" : String(format: "%.2f s", $0 / 1000) } ?? "—")
                .font(.system(size: 13, weight: .medium)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(RebuildTheme.secondaryText)
        }.accessibilityElement(children: .combine)
    }
}
