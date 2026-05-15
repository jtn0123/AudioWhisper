import SwiftUI
import AppKit

// MARK: - MenuHeaderView
//
// Branded header that lives at the top of the menu bar dropdown. Shows:
//   - AW mark (small coral mic glyph)
//   - "AudioWhisper" / status line (dot + provider + today's WPM)
//
// Used via NSMenuItem.view + NSHostingView.
internal struct MenuHeaderView: View {

    /// Provider currently selected (matches TranscriptionProvider raw values:
    /// "openai" / "gemini" / "local" / "parakeet").
    let providerRaw: String
    /// Today's average WPM, formatted ("168") — pass nil to hide.
    let todayWPM: Int?

    private let coral = Color(red: 0.85, green: 0.45, blue: 0.30)
    private let coralDeep = Color(red: 0.70, green: 0.34, blue: 0.23)
    private let sage = Color(red: 0.37, green: 0.66, blue: 0.46)

    var body: some View {
        HStack(spacing: 10) {
            // Coral logo bauble
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [coral, coralDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 26)
                .overlay(
                    // Mini bars glyph
                    Canvas { context, size in
                        let heights: [CGFloat] = [0.45, 0.85, 1.0, 0.7, 0.35]
                        let barW: CGFloat = size.width / 11
                        let gap: CGFloat = size.width / 14
                        let total = barW * 5 + gap * 4
                        let startX = (size.width - total) * 0.5
                        let maxH = size.height * 0.6
                        for (index, heightFraction) in heights.enumerated() {
                            let barH = maxH * heightFraction
                            let posX = startX + CGFloat(index) * (barW + gap)
                            let posY = (size.height - barH) * 0.5
                            let path = Path(roundedRect: CGRect(x: posX, y: posY, width: barW, height: barH),
                                            cornerRadius: barW / 2)
                            context.fill(path, with: .color(.white))
                        }
                    }
                    .frame(width: 14, height: 14)
                )
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)

            // Title + status
            VStack(alignment: .leading, spacing: 1) {
                Text("AudioWhisper")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    Circle()
                        .fill(sage)
                        .frame(width: 6, height: 6)
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var statusLine: String {
        let prov: String
        switch providerRaw.lowercased() {
        case "openai":   prov = "OpenAI"
        case "gemini":   prov = "Gemini"
        case "local":    prov = "Local Whisper"
        case "parakeet": prov = "Parakeet"
        default:         prov = providerRaw.capitalized
        }
        if let wpm = todayWPM, wpm > 0 {
            return "Ready · \(prov) · \(wpm) WPM today"
        }
        return "Ready · \(prov)"
    }
}

// MARK: - RecentTranscriptMenuRow
//
// Single recent-transcript line in the menu. Click copies the text to the
// clipboard. Used via NSMenuItem.view + NSHostingView.
internal struct RecentTranscriptMenuRow: View {
    let timeString: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(timeString)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .leading)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Recent label divider (small "Recent" caption)
internal struct MenuSectionLabel: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}
