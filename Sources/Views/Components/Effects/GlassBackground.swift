import SwiftUI
import AppKit

/// A frosted glass background effect using NSVisualEffectView.
/// Intensity controls the material and blending mode.
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
        switch intensity {
        case .subtle:
            // No glass effect - use a very subtle material
            effectView.material = .underWindowBackground
            effectView.blendingMode = .behindWindow
            effectView.alphaValue = 0.3

        case .expressive:
            // Light frosted glass
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.alphaValue = 0.85

        case .bold:
            // Full vibrancy glass
            effectView.material = .fullScreenUI
            effectView.blendingMode = .behindWindow
            effectView.alphaValue = 1.0
        }
    }
}

// MARK: - SwiftUI Convenience Modifier

extension View {
    /// Adds a glass background effect based on visual intensity.
    /// Only shows for expressive and bold intensities.
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

#Preview("Glass - Subtle") {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack {
            Text("Subtle")
                .font(.title)
                .foregroundStyle(.white)
        }
        .frame(width: 200, height: 100)
        .glassBackground(intensity: .subtle)
    }
    .frame(width: 300, height: 200)
}

#Preview("Glass - Expressive") {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack {
            Text("Expressive")
                .font(.title)
                .foregroundStyle(.white)
        }
        .frame(width: 200, height: 100)
        .glassBackground(intensity: .expressive)
    }
    .frame(width: 300, height: 200)
}

#Preview("Glass - Bold") {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack {
            Text("Bold")
                .font(.title)
                .foregroundStyle(.white)
        }
        .frame(width: 200, height: 100)
        .glassBackground(intensity: .bold)
    }
    .frame(width: 300, height: 200)
}
