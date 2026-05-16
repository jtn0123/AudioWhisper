import SwiftUI

// MARK: - Mic Test Palette

/// Coral palette used by the mic-test banner. Mirrors the design prototype;
/// `coral` matches `DashboardTheme.accent` / `coralDeep` matches `accentDeep`.
private enum MicTestPalette {
    static let coral     = Color(red: 0.85, green: 0.45, blue: 0.30)
    static let coralDeep = Color(red: 0.70, green: 0.34, blue: 0.23)
    static let coralLite = Color(red: 0.91, green: 0.60, blue: 0.47)
    static let sage      = Color(red: 0.37, green: 0.66, blue: 0.46)
}

// MARK: - MicTestBanner

/// "Test with my voice" banner shown at the top of the Visuals tab. Captures
/// live mic audio and drives the shared `LivePreviewSampler` so every preview
/// reacts to the user's real voice. Nothing is recorded or persisted.
internal struct MicTestBanner: View {
    let style: WaveformStyle
    @ObservedObject var sampler: LivePreviewSampler
    @ObservedObject var capture: MicTestCapture

    private var isLive: Bool { capture.state == .live }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            previewTile
            copyColumn
            Spacer(minLength: 0)
            actionButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isLive ? MicTestPalette.coral : DashboardTheme.rule, lineWidth: isLive ? 1 : 0.5)
        )
        .shadow(
            color: isLive ? MicTestPalette.coral.opacity(0.22) : Color.black.opacity(0.04),
            radius: isLive ? 14 : 6,
            y: isLive ? 0 : 2
        )
    }

    // MARK: - Left: live preview

    private var previewTile: some View {
        VStack(spacing: 6) {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.04)
                WaveformStylePreview(style: style, sampler: sampler)
                    .frame(
                        width: style.isRadial ? 96 : 122,
                        height: style.isRadial ? 96 : 64
                    )
            }
            .frame(width: 136, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 5) {
                if isLive {
                    Circle()
                        .fill(MicTestPalette.coral)
                        .frame(width: 5, height: 5)
                }
                Text(isLive ? "Live" : "Preview")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(isLive ? MicTestPalette.coral : DashboardTheme.inkMuted)
            }
        }
    }

    // MARK: - Middle: copy + meter

    private var copyColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(headline)
                .font(DashboardTheme.Fonts.sans(15, weight: .semibold))
                .foregroundStyle(DashboardTheme.ink)

            Text(subCopy)
                .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                .foregroundStyle(DashboardTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if isLive {
                inputMeter
                    .padding(.top, 4)
            }
        }
    }

    private var inputMeter: some View {
        HStack(spacing: 8) {
            Text("Input")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(DashboardTheme.inkLight)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardTheme.rule.opacity(0.6))
                    Capsule()
                        .fill(meterColor)
                        .frame(width: max(2, geo.size.width * CGFloat(min(1, capture.level))))
                }
            }
            .frame(width: 120, height: 6)

            Text("\(Int((min(1, capture.level) * 100).rounded()))%")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(DashboardTheme.inkMuted)
        }
    }

    private var meterColor: Color {
        let level = capture.level
        if level > 0.85 { return MicTestPalette.coralDeep }
        if level > 0.5 { return MicTestPalette.coral }
        return MicTestPalette.sage
    }

    // MARK: - Right: action button

    private var actionButton: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                if isLive {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MicTestPalette.coral)
                        .frame(width: 9, height: 9)
                }
                Text(buttonTitle)
                    .font(DashboardTheme.Fonts.sans(13, weight: .semibold))
            }
            .foregroundStyle(buttonForeground)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(buttonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isLive ? DashboardTheme.rule : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if isLive {
            RoundedRectangle(cornerRadius: 8).fill(Color.white)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [MicTestPalette.coralLite, MicTestPalette.coral],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var buttonForeground: Color {
        isLive ? DashboardTheme.ink : .white
    }

    private func toggle() {
        if isLive {
            capture.stop()
        } else {
            capture.start()
        }
    }

    // MARK: - State-driven copy

    private var headline: String {
        switch capture.state {
        case .off:
            return "Test it with your voice."
        case .live:
            return capture.speaking ? "Looking good — keep going." : "Say something."
        case .denied:
            return "Microphone access blocked."
        case .error:
            return "Couldn't reach your microphone."
        }
    }

    private var subCopy: String {
        switch capture.state {
        case .off:
            return "Speak for a few seconds to see how each style responds to real "
                + "audio. The mic is only used here — nothing is sent off-device."
        case .live:
            return "Switch styles below — the preview reacts in real time. Nothing is recorded."
        case .denied:
            return "Open System Settings → Privacy & Security → Microphone and allow AudioWhisper."
        case .error(let reason):
            return "Mic unavailable (\(reason)). Check that no other app is using it."
        }
    }

    private var buttonTitle: String {
        switch capture.state {
        case .off:
            return "Test with my voice"
        case .live:
            return "Stop"
        case .denied, .error:
            return "Try again"
        }
    }
}

#Preview("Mic test banner") {
    MicTestBanner(
        style: .classic,
        sampler: LivePreviewSampler(),
        capture: MicTestCapture(sampler: LivePreviewSampler())
    )
    .padding(32)
    .frame(width: 760)
}
