import SwiftUI

/// Visuals settings — replaces the dropdown with a 2×4 grid of live previews
/// plus a full-size preview window that mirrors what the user will actually
/// see during a recording.
internal struct DashboardVisualsView: View {
    @AppDefault(\.waveformStyle) private var waveformStyle
    @AppDefault(\.visualIntensity) private var visualIntensity

    @StateObject private var sampler: LivePreviewSampler
    @StateObject private var micCapture: MicTestCapture

    init() {
        let sharedSampler = LivePreviewSampler()
        _sampler = StateObject(wrappedValue: sharedSampler)
        _micCapture = StateObject(wrappedValue: MicTestCapture(sampler: sharedSampler))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xl) {
                pageHeader
                MicTestBanner(style: waveformStyle, sampler: sampler, capture: micCapture)
                waveformSection
                previewSection
                celebrationSection
            }
            .padding(DashboardTheme.Spacing.xl)
        }
        .background(DashboardTheme.pageBg)
        .onAppear { sampler.start() }
        .onDisappear {
            micCapture.stop()
            sampler.stop()
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xs) {
            Text("Visuals")
                .font(DashboardTheme.Fonts.serif(32, weight: .medium))
                .tracking(-0.5)
                .foregroundStyle(DashboardTheme.ink)

            Text("Eight live previews — pick whichever feels right.")
                .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                .foregroundStyle(DashboardTheme.inkLight)
        }
    }

    // MARK: - Waveform grid

    private var waveformSection: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            sectionLabel("Waveform style")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                spacing: 12
            ) {
                ForEach(WaveformStyle.allCases) { style in
                    StylePickerCard(
                        style: style,
                        selected: waveformStyle == style,
                        sampler: sampler
                    ) {
                        waveformStyle = style
                        NotificationCenter.default.post(
                            name: .waveformStyleChanged,
                            object: style
                        )
                    }
                }
            }
        }
    }

    // MARK: - Big preview window

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            sectionLabel("Preview")

            HStack {
                Spacer()
                PreviewWindow(style: waveformStyle, sampler: sampler)
                Spacer()
            }
            .padding(.vertical, DashboardTheme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                    .fill(DashboardTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                    .stroke(DashboardTheme.rule, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
        }
    }

    // MARK: - Celebration / intensity

    private var celebrationSection: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            sectionLabel("Visual intensity")

            VStack(alignment: .leading, spacing: 0) {
                settingsRow(
                    title: "Celebration",
                    subtitle: "How much animation and glass plays during recording and on success."
                ) {
                    Picker("", selection: $visualIntensity) {
                        ForEach(VisualIntensity.allCases) { intensity in
                            Text(intensity.rawValue).tag(intensity)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Divider().background(DashboardTheme.rule)

                HStack(spacing: DashboardTheme.Spacing.sm) {
                    Image(systemName: visualIntensity.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(DashboardTheme.accent)
                    Text(visualIntensity.description)
                        .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                        .foregroundStyle(DashboardTheme.inkMuted)
                }
                .padding(DashboardTheme.Spacing.md)
            }
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                    .fill(DashboardTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                    .stroke(DashboardTheme.rule, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DashboardTheme.Fonts.sans(11, weight: .semibold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(DashboardTheme.inkLight)
    }

    private func settingsRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: DashboardTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DashboardTheme.Fonts.sans(14, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)
                Text(subtitle)
                    .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
            }
            Spacer()
            content()
        }
        .padding(DashboardTheme.Spacing.md)
    }
}

// MARK: - StylePickerCard

private struct StylePickerCard: View {
    let style: WaveformStyle
    let selected: Bool
    @ObservedObject var sampler: LivePreviewSampler
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 9) {
                // Live preview area
                ZStack {
                    Color(red: 0.04, green: 0.04, blue: 0.04)
                    WaveformStylePreview(style: style, sampler: sampler)
                        .frame(
                            width: style.isRadial ? 140 : 190,
                            height: style.isRadial ? 140 : 100
                        )
                }
                .frame(height: style.isRadial ? 140 : 110)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                // Label + radio
                HStack(spacing: 8) {
                    Circle()
                        .stroke(selected ? DashboardTheme.accent : DashboardTheme.rule, lineWidth: 1.5)
                        .background(
                            Circle().fill(selected ? DashboardTheme.accent : Color.clear)
                                .padding(3)
                        )
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(style.rawValue)
                                .font(DashboardTheme.Fonts.sans(12.5, weight: .semibold))
                                .foregroundStyle(DashboardTheme.ink)
                            if style.isNew {
                                Text("NEW")
                                    .font(DashboardTheme.Fonts.sans(9, weight: .bold))
                                    .tracking(0.4)
                                    .foregroundStyle(DashboardTheme.accentDeep)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(DashboardTheme.accentLight)
                                    )
                            }
                        }
                        Text(style.description)
                            .font(DashboardTheme.Fonts.sans(10.5, weight: .regular))
                            .foregroundStyle(DashboardTheme.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                    .fill(DashboardTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                    .stroke(
                        selected ? DashboardTheme.accent.opacity(0.5) : DashboardTheme.rule,
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: selected ? DashboardTheme.accent.opacity(0.18) : Color.black.opacity(0.03),
                radius: selected ? 0 : 2,
                y: selected ? 0 : 1
            )
        }
        .buttonStyle(.plain)
        // C1: same problem as the Welcome screen's style grid — the label is a
        // rendered waveform, so every tile announced identically.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.isNew ? "\(style.rawValue), new" : style.rawValue)
        .accessibilityValue(style.description)
        .accessibilityHint("Use this waveform style")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - PreviewWindow

private struct PreviewWindow: View {
    let style: WaveformStyle
    @ObservedObject var sampler: LivePreviewSampler

    var body: some View {
        ZStack {
            // Dark recording window
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.04)

                WaveformStylePreview(style: style, sampler: sampler)
                    .frame(
                        width: style.isRadial ? 200 : 320,
                        height: style.isRadial ? 200 : 150
                    )

                // Status row
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(red: 0.85, green: 0.45, blue: 0.30))
                                .frame(width: 6, height: 6)
                                .shadow(color: Color(red: 0.85, green: 0.45, blue: 0.30).opacity(0.7), radius: 4)
                            Text("LISTENING")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.6)
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                        Spacer()
                        Text("00:14")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                }
            }
            .frame(width: 360, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .shadow(color: Color(red: 0.85, green: 0.45, blue: 0.30).opacity(0.10), radius: 50)
        }
    }
}

// MARK: - Testable Helpers

extension DashboardVisualsView {
    /// Parses waveform style from raw string value.
    static func testableWaveformStyle(from rawValue: String) -> WaveformStyle {
        WaveformStyle(rawValue: rawValue) ?? .classic
    }

    /// Parses visual intensity from raw string value.
    static func testableVisualIntensity(from rawValue: String) -> VisualIntensity {
        VisualIntensity(rawValue: rawValue) ?? .balanced
    }
}

#Preview("Visuals · expanded") {
    DashboardVisualsView()
        .frame(width: 920, height: 800)
}
