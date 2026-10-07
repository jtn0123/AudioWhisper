import AppKit
import SwiftUI

/// Shared look for the rebuild workspace: a deep slate sidebar, cool neutral
/// surfaces and one restrained petrol-teal accent. Every color is a semantic
/// token with light, dark and Increase Contrast variants, so pages never pick
/// raw colors of their own.
enum RebuildTheme {
    // MARK: Accent

    /// Fill accent for prominent buttons, checkboxes, switches and the record
    /// button. Dark enough in both appearances for white text (≥ 4.5:1).
    static let accent = dynamic(
        light: rgb(0x136F84), dark: rgb(0x1C7F96),
        lightHC: rgb(0x0B5566), darkHC: rgb(0x1C7F96))
    /// Accent for text and glyphs drawn on a surface: links, info icons,
    /// numbered steps. Lighter in dark mode so it stays readable.
    static let accentText = dynamic(
        light: rgb(0x136F84), dark: rgb(0x6CC3D5),
        lightHC: rgb(0x0B5566), darkHC: rgb(0x9ADCEA))

    // MARK: Surfaces and text

    /// Window background behind the page header and cards.
    static let canvas = dynamic(light: rgb(0xF3F5F7), dark: rgb(0x15181C))
    /// Cards and grouped settings.
    static let surface = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x1D2127))
    /// Inset blocks inside a surface: keycaps, original transcripts.
    static let surfaceSunken = dynamic(light: rgb(0xEEF1F4), dark: rgb(0x16191E))
    static let border = dynamic(
        light: rgb(0xDCE1E7), dark: rgb(0x2C323A),
        lightHC: rgb(0x8A96A3), darkHC: rgb(0x6B7685))
    /// A faint lift under cards in light mode only; dark mode relies on the
    /// surface step and border instead.
    static let cardShadow = dynamic(light: rgb(0x0F1A24, alpha: 0.05), dark: rgb(0x000000, alpha: 0))
    /// Captions, metadata and supporting copy. Meets 4.5:1 on canvas and surface.
    static let secondaryText = dynamic(
        light: rgb(0x5A6571), dark: rgb(0xA1AAB5),
        lightHC: rgb(0x39424C), darkHC: rgb(0xC9D0D8))

    // MARK: Status

    static let success = dynamic(
        light: rgb(0x1D8A4E), dark: rgb(0x55C68A), lightHC: rgb(0x11693A), darkHC: rgb(0x7EDCA6))
    static let warning = dynamic(
        light: rgb(0xA86200), dark: rgb(0xF2A93B), lightHC: rgb(0x844C00), darkHC: rgb(0xFFC56B))
    static let error = dynamic(
        light: rgb(0xC4352C), dark: rgb(0xFF6B61), lightHC: rgb(0x9E2219), darkHC: rgb(0xFF958D))
    /// Live recording: the stop button fill, elapsed time and status dots.
    /// Carries white glyphs in both appearances.
    static let recording = dynamic(light: rgb(0xCF362D), dark: rgb(0xCF362D), lightHC: rgb(0xA8221A))
    /// Small recording text needs a lighter red on dark surfaces than the
    /// stop-button fill, which is chosen for its white glyph.
    static let recordingText = error
    /// Record button while it can't be used. Still carries a legible white glyph.
    static let inactiveFill = dynamic(light: rgb(0x6B7480), dark: rgb(0x58616C))

    // MARK: Sidebar (always dark)

    static let sidebarBackground = dynamic(light: rgb(0x141B23), dark: rgb(0x0F1318))
    static let sidebarSecondary = Color.white.opacity(0.62)
    static let sidebarIcon = Color.white.opacity(0.72)
    static let sidebarAccent = Color(nsColor: rgb(0x7CCBDC))
    static let sidebarSelection = Color(nsColor: rgb(0x2A8FA6)).opacity(0.26)
    static let sidebarHover = Color.white.opacity(0.06)
    static let sidebarDivider = Color.white.opacity(0.07)

    // MARK: Recorder HUD (always dark)

    static let hudBackground = Color(nsColor: rgb(0x10151B))
    static let hudWaveformBackground = Color(nsColor: rgb(0x161E27))
    static let hudWaveformForeground = Color(nsColor: rgb(0xB6E2EC))
    static let hudBorder = Color.white.opacity(0.10)
    static let hudAccent = Color(nsColor: rgb(0x1C7F96))
    static let hudAccentPressed = Color(nsColor: rgb(0x166A7D))

    // MARK: Type

    /// Page titles: native, compact and consistent with section headings.
    static func titleFont(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    /// The wordmark only.
    static func brandFont(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }

    // MARK: Helpers

    private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func dynamic(light: NSColor, dark: NSColor, lightHC: NSColor? = nil, darkHC: NSColor? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua
            ]) {
            case .darkAqua?: return dark
            case .accessibilityHighContrastDarkAqua?: return darkHC ?? dark
            case .accessibilityHighContrastAqua?: return lightHC ?? light
            default: return light
            }
        })
    }
}

/// A titled group on a page. Titles are sentence case; captions explain the
/// group once instead of repeating hints under every control.
struct RebuildSection<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let caption {
                    Text(caption).font(.system(size: 12)).foregroundStyle(RebuildTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .rebuildCard()
    }
}

extension View {
    func rebuildCard(padding: CGFloat = 16) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(RebuildTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(RebuildTheme.border))
            .shadow(color: RebuildTheme.cardShadow, radius: 2, x: 0, y: 1)
    }
}

/// Text-only action drawn in the accent, used where AppKit's link style would
/// otherwise stay system blue regardless of the app tint.
struct RebuildLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkLabel(configuration: configuration)
    }

    private struct LinkLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? RebuildTheme.accentText : RebuildTheme.secondaryText)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == RebuildLinkButtonStyle {
    static var rebuildLink: RebuildLinkButtonStyle { RebuildLinkButtonStyle() }
}

/// Buttons on the recorder HUD. The HUD is a non-activating panel that never
/// becomes key, so native prominent buttons would always draw inactive gray;
/// this keeps the primary action in the accent with white text.
struct RebuildHUDButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        HUDButton(configuration: configuration, prominent: prominent)
    }

    private struct HUDButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            configuration.label
                .font(.system(size: 13, weight: prominent ? .semibold : .medium))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.55))
                .padding(.horizontal, 14).frame(height: 32)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(strokeOpacity)))
                .contentShape(shape)
        }

        private var fill: Color {
            guard enabled else { return .white.opacity(0.08) }
            if prominent { return configuration.isPressed ? RebuildTheme.hudAccentPressed : RebuildTheme.hudAccent }
            return .white.opacity(configuration.isPressed ? 0.18 : 0.11)
        }

        private var strokeOpacity: Double {
            if contrast == .increased { return 0.55 }
            return prominent && enabled ? 0 : 0.12
        }
    }
}

/// Label column plus control column, so settings line up across groups.
struct RebuildFormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).font(.system(size: 13)).frame(width: 128, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum RebuildTone {
    case info, success, warning, error

    var symbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return RebuildTheme.accentText
        case .success: return RebuildTheme.success
        case .warning: return RebuildTheme.warning
        case .error: return RebuildTheme.error
        }
    }
}

/// An inline message with an optional action. Text stays in the primary color
/// for legibility; the icon and tint carry the tone.
struct RebuildCallout<Actions: View>: View {
    let tone: RebuildTone
    let message: String
    var detail: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: tone.symbol).foregroundStyle(tone.color).font(.system(size: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.system(size: 12.5)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tone.color.opacity(0.28)))
        .accessibilityElement(children: .contain)
    }
}

extension RebuildCallout where Actions == EmptyView {
    init(tone: RebuildTone, message: String, detail: String? = nil) {
        self.init(tone: tone, message: message, detail: detail) { EmptyView() }
    }
}

/// A status line with a state icon, used for setup steps and install states.
struct RebuildStatusLabel: View {
    let text: String
    let tone: RebuildTone
    var busy = false
    var emphasized = false

    var body: some View {
        HStack(spacing: 7) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: tone.symbol).foregroundStyle(tone.color)
            }
            Text(text).font(.system(size: 13, weight: emphasized ? .semibold : .regular))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A numbered setup step that turns into a checkmark once complete. Both
/// states are a tinted disc with a colored glyph, so the header stays quieter
/// than the status line beneath it.
struct RebuildStepHeader: View {
    let number: Int
    let title: String
    let done: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill((done ? RebuildTheme.success : RebuildTheme.accentText).opacity(0.15))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RebuildTheme.success)
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RebuildTheme.accentText)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title), \(done ? "complete" : "not complete")")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A key combination drawn as a keycap.
struct RebuildKeycap: View {
    let keys: String

    var body: some View {
        Text(keys).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RebuildTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(RebuildTheme.border))
            .accessibilityLabel("Shortcut \(keys)")
    }
}

/// Elapsed recording time. Ticks once a second and only exists while a
/// recording is active, so it never runs in a hidden window.
struct RebuildElapsedTime: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let text = Self.format(context.date.timeIntervalSince(start))
            Text(text).monospacedDigit()
                .accessibilityLabel("Recording time")
                .accessibilityValue(text)
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
