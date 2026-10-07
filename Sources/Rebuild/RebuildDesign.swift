import AppKit
import SwiftUI

/// Shared look for the rebuild workspace: ink sidebar, warm paper, rust accent
/// and an editorial serif used sparingly for page titles.
enum RebuildTheme {
    /// Rust in light mode; a lighter coral in dark mode so links, focus and
    /// prominent buttons keep readable contrast on the dark paper.
    static let accent = dynamic(
        light: NSColor(red: 0.70, green: 0.27, blue: 0.16, alpha: 1),
        dark: NSColor(red: 0.84, green: 0.40, blue: 0.26, alpha: 1))
    static let paper = dynamic(
        light: NSColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1),
        dark: NSColor(calibratedWhite: 0.145, alpha: 1))
    static let card = dynamic(
        light: NSColor(calibratedWhite: 1, alpha: 0.72),
        dark: NSColor(calibratedWhite: 1, alpha: 0.05))
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.14)
    static let brand = Color(red: 0.94, green: 0.60, blue: 0.44)
    static let sidebarSecondary = Color.white.opacity(0.62)

    static func titleFont(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
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
                    Text(caption).font(.system(size: 12)).foregroundStyle(.secondary)
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
            .background(RebuildTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08)))
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
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
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
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(tone.color.opacity(tone == .info ? 0.06 : 0.09), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tone.color.opacity(0.22)))
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

/// A numbered setup step that turns into a checkmark once complete.
struct RebuildStepHeader: View {
    let number: Int
    let title: String
    let done: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.green : RebuildTheme.accent.opacity(0.14))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .semibold)).foregroundStyle(RebuildTheme.accent)
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
        Text(keys).font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.16)))
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
