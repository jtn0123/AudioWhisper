import SwiftUI
import AppKit

/// A frosted glass background effect using NSVisualEffectView.
/// All celebration styles use glass with slight variations.
struct GlassBackground: NSViewRepresentable {
    let intensity: VisualIntensity
    var cornerRadius: CGFloat = 12

    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
        configureEffect(effectView)
        return effectView
    }

    func updateNSView(_ effectView: NSVisualEffectView, context: Context) {
        effectView.layer?.cornerRadius = cornerRadius
        configureEffect(effectView)
    }

    private func configureEffect(_ effectView: NSVisualEffectView) {
        // All styles use consistent frosted glass
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.alphaValue = 0.85
    }
}

// MARK: - SwiftUI Convenience Modifier

extension View {
    /// Adds a glass background effect based on visual intensity.
    @ViewBuilder
    func glassBackground(intensity: VisualIntensity, cornerRadius: CGFloat = 12) -> some View {
        if intensity.showGlass {
            self.background(
                GlassBackground(intensity: intensity, cornerRadius: cornerRadius)
            )
        } else {
            self
        }
    }
}

// MARK: - Previews

#Preview("Glass - Glow") {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack {
            Text("Glow")
                .font(.title)
                .foregroundStyle(.white)
        }
        .frame(width: 200, height: 100)
        .glassBackground(intensity: .glow)
    }
    .frame(width: 300, height: 200)
}

#Preview("Glass - Balanced") {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack {
            Text("Balanced")
                .font(.title)
                .foregroundStyle(.white)
        }
        .frame(width: 200, height: 100)
        .glassBackground(intensity: .balanced)
    }
    .frame(width: 300, height: 200)
}

#Preview("Glass - Burst") {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack {
            Text("Burst")
                .font(.title)
                .foregroundStyle(.white)
        }
        .frame(width: 200, height: 100)
        .glassBackground(intensity: .burst)
    }
    .frame(width: 300, height: 200)
}
