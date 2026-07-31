import SwiftUI
import AppKit

/// Consolidated single-page welcome.
///
/// Replaces the previous multi-section onboarding (welcome header + privacy
/// card + feature grid + setup section + smart-paste instructions + button).
///
/// Layout:
///   • Hero recording window — live-rendering the user's selected style
///   • Headline + subtitle
///   • 2×4 grid of visual style tiles
///   • Selected style name + description (italic NY serif)
///   • Footer: "Change anything later" + "Get started" CTA
internal struct WelcomeView: View {
    @AppDefault(\.waveformStyle) private var waveformStyle
    @State private var isDismissing = false
    @StateObject private var sampler = LivePreviewSampler()

    // AW colors
    private let paper = Color(red: 0.980, green: 0.973, blue: 0.953) // #FAF8F3
    private let ink   = Color(red: 0.102, green: 0.086, blue: 0.071) // #1A1612
    private let coral = Color(red: 0.85, green: 0.45, blue: 0.30)
    private let coralDeep = Color(red: 0.70, green: 0.34, blue: 0.23)

    private var selectedStyle: WaveformStyle { waveformStyle }

    var body: some View {
        ZStack {
            // Background flourish
            paper.ignoresSafeArea()
            RadialGradient(
                colors: [coral.opacity(0.06), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 320
            )
            .frame(maxWidth: 600, maxHeight: 500)
            .offset(y: -120)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Hero
                hero
                    .padding(.top, 12)

                Spacer().frame(height: 24)

                // Picker label
                HStack(spacing: 10) {
                    Text("Your visual")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(ink.opacity(0.5))
                    Rectangle()
                        .fill(ink.opacity(0.12))
                        .frame(height: 0.5)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 10)

                // Grid
                styleGrid
                    .padding(.horizontal, 36)

                // Selected readout
                selectedReadout
                    .padding(.horizontal, 36)
                    .padding(.top, 12)

                Spacer()

                // Footer
                footer
                    .padding(.horizontal, 36)
                    .padding(.bottom, 22)
            }
        }
        .frame(
            width: LayoutMetrics.Welcome.windowSize.width,
            height: LayoutMetrics.Welcome.windowSize.height
        )
        .onAppear {
            sampler.isActive = false   // hero idle, breathing
            sampler.start()
        }
        .onDisappear { sampler.stop() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 16) {
            // Recording window (live, idle-breathing the selected style)
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.04)
                WaveformStylePreview(style: selectedStyle, sampler: sampler)
                    .frame(
                        width: selectedStyle.isRadial ? 155 : 270,
                        height: selectedStyle.isRadial ? 155 : 130
                    )

                // Status row
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(red: 0.85, green: 0.83, blue: 0.80))
                                .opacity(0.45)
                                .frame(width: 5, height: 5)
                            Text("TAP TO RECORD")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                        Spacer()
                        Text("⌘⇧Space")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.32))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 11)
                }
            }
            .frame(width: 300, height: 175)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
            .shadow(color: coral.opacity(0.12), radius: 56)
            // C1: purely visual preview of the recording window. Collapse it into
            // one element that states what it is and which style is showing,
            // rather than letting VoiceOver walk its decorative innards.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording window preview")
            .accessibilityValue("\(selectedStyle.rawValue) style. Press Command Shift Space to record.")

            // Headline
            Text("Hold a key. Speak. Paste.")
                .font(.system(size: 30, weight: .medium, design: .serif))
                .tracking(-0.8)
                .foregroundStyle(ink)

            // Sub
            Text("Voice in, text out. Nothing leaves your Mac.")
                .font(.system(size: 13, design: .serif))
                .italic()
                .foregroundStyle(ink.opacity(0.55))
        }
    }

    // MARK: - Grid

    private var styleGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4),
            spacing: 7
        ) {
            ForEach(WaveformStyle.allCases) { style in
                StyleTile(
                    style: style,
                    selected: waveformStyle == style,
                    sampler: sampler
                ) {
                    waveformStyle = style
                }
            }
        }
    }

    // MARK: - Selected readout

    private var selectedReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(selectedStyle.rawValue)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(ink)

            Text("— \(selectedStyle.description.lowercased())")
                .font(.system(size: 12, design: .serif))
                .italic()
                .foregroundStyle(ink.opacity(0.55))

            if selectedStyle.isNew {
                Text("NEW")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(coral)
                    .padding(.leading, 4)
            }

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Change anything later in settings.")
                .font(.system(size: 11.5, design: .serif))
                .italic()
                .foregroundStyle(ink.opacity(0.45))

            Spacer()

            Button(action: startApp) {
                Text("Get started")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [coral, coralDeep],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: coral.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(isDismissing)
        }
    }

    // MARK: - Actions

    private func startApp() {
        guard !isDismissing else { return }
        isDismissing = true

        // Default to local provider (preserved from old WelcomeView behavior)
        UserDefaults.standard.set(TranscriptionProvider.local.rawValue, forKey: "transcriptionProvider")
        UserDefaults.standard.set(true, forKey: "hasCompletedWelcome")
        UserDefaults.standard.set("1.1", forKey: "lastWelcomeVersion")

        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)
        DashboardWindowManager.shared.showDashboardWindow()
        NSApplication.shared.stopModal(withCode: .OK)
    }
}

// MARK: - StyleTile

private struct StyleTile: View {
    let style: WaveformStyle
    let selected: Bool
    @ObservedObject var sampler: LivePreviewSampler
    let onSelect: () -> Void

    private let coral = Color(red: 0.85, green: 0.45, blue: 0.30)

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.04)
                WaveformStylePreview(style: style, sampler: sampler)
                    .frame(
                        width: style.isRadial ? 64 : 108,
                        height: style.isRadial ? 64 : 60
                    )

                if style.isNew {
                    VStack {
                        HStack {
                            Spacer()
                            Text("NEW")
                                .font(.system(size: 7, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(coral)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(red: 0.04, green: 0.04, blue: 0.04).opacity(0.55))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(coral.opacity(0.4), lineWidth: 0.5)
                                        )
                                )
                        }
                        Spacer()
                    }
                    .padding(3)
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(selected ? coral : Color(red: 0.235, green: 0.176, blue: 0.118).opacity(0.14),
                            lineWidth: 1)
            )
            .shadow(
                color: selected ? coral.opacity(0.25) : .clear,
                radius: selected ? 3 : 0
            )
        }
        .buttonStyle(.plain)
        // C1: this button's entire label is a rendered waveform, so VoiceOver
        // announced eight identical unlabelled buttons with no way to tell the
        // styles apart or know which was chosen.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.isNew ? "\(style.rawValue), new" : style.rawValue)
        .accessibilityValue(style.description)
        .accessibilityHint("Use this waveform style")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Welcome · consolidated") {
    WelcomeView()
}
