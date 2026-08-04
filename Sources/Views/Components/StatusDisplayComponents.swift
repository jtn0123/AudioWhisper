import SwiftUI

internal struct StatusIndicator: View {
    let status: AppStatus
    @State private var isAnimating = false

    var body: some View {
        // Fixed size container to prevent any positional animation
        ZStack {
            Color.clear
                .frame(width: 12, height: 12) // Fixed container size

            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .opacity(status.shouldAnimate ? (isAnimating ? 0.7 : 1.0) : 1.0)
                .onAppear {
                    if status.shouldAnimate {
                        withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            isAnimating = true
                        }
                    }
                }
                .onChange(of: status.shouldAnimate) { _, shouldAnimate in
                    if shouldAnimate {
                        withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            isAnimating = true
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isAnimating = false
                        }
                    }
                }
        }
    }
}

internal struct StatusMessage: View {
    let status: AppStatus

    var body: some View {
        Text(status.message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(status == .permissionRequired ? .secondary : .primary)
            .accessibilityLabel(accessibilityMessage)
    }

    private var accessibilityMessage: String {
        switch status {
        case .error(let message):
            return "Error: \(message)"
        case .recording:
            return "Currently recording audio"
        case .processing(let message):
            return "Processing: \(message)"
        case .success:
            return "Transcription completed successfully"
        case .ready:
            return "Ready to record"
        case .permissionRequired:
            return "Microphone permission required to record audio"
        }
    }
}
