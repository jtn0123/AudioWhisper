import SwiftUI

// Small presentational subviews used only by `WaveformContainer`.
//
// Split out of WaveformContainer.swift, which had grown past 500 lines. These
// four are leaf views with no dependency on the container's state machine —
// they take what they need as plain parameters — so moving them changes
// nothing about behaviour and leaves the container file focused on the
// state-driven chrome.
//
// They stay `private`-equivalent in spirit: `fileprivate` would not survive the
// move, so they are internal, but nothing outside the waveform folder
// references them.

// MARK: - ProcessingShimmerView
// Seven horizontally-arranged dots with a soft falloff. Used in place of
// breathing bars during .processing so we don't pretend to be listening.

internal struct ProcessingShimmerView: View {
    let color: Color
    let animated: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: max(8, geo.size.width * 0.04)) {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .opacity(dotOpacity(for: index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .onChange(of: animated) { _, enabled in
            withAnimation(.linear(duration: 0)) { phase = 0 }
            if enabled {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
            }
        }
        .onDisappear {
            // Halt the repeating shimmer animation when off-screen so it
            // doesn't keep driving re-renders for a hidden view.
            withAnimation(.linear(duration: 0)) { phase = 0 }
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        let position = (CGFloat(index) / 6.0)
        let center = phase
        let dist = abs(position - center.truncatingRemainder(dividingBy: 1.0))
        let wrapped = min(dist, 1 - dist)
        return Double(0.15 + 0.65 * exp(-pow(wrapped * 3.0, 2)))
    }
}

// MARK: - TimerLabel
// Live elapsed-time label shown to the right of LISTENING.

internal struct TimerLabel: View {
    let start: Date?
    @State private var now: Date = Date()
    /// C3/G1: was a raw autoconnected Timer publisher. Only 2 Hz, but it
    /// also never stopped — the recording window stays alive between sessions.
    @State private var frameTimer = FrameTimer(interval: 0.5)

    private let formatter: DateComponentsFormatter = {
        let componentsFormatter = DateComponentsFormatter()
        componentsFormatter.unitsStyle = .positional
        componentsFormatter.zeroFormattingBehavior = .pad
        componentsFormatter.allowedUnits = [.minute, .second]
        return componentsFormatter
    }()

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .tracking(0.5)
            .onAppear {
                now = Date()
                frameTimer.start()
            }
            .onDisappear { frameTimer.stop() }
            .onReceive(frameTimer.publisher) { _ in
                now = Date()
            }
    }

    private var label: String {
        guard let start = start else { return "00:00" }
        let dt = max(0, now.timeIntervalSince(start))
        return formatter.string(from: dt) ?? "00:00"
    }
}

// MARK: - HotkeyHint
// Compact keycap shown on .ready so users know how to invoke the app.

internal struct HotkeyHint: View {
    @AppDefault(\.globalHotkey) private var shortcut
    var body: some View {
        Text(RecordingShortcut.display(shortcut))
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - SuccessRecapLabel
// On success, show how long the recording was. Pass a word count from the
// view-model if you want to surface "N words · M.Ms".

internal struct SuccessRecapLabel: View {
    let duration: TimeInterval?
    let wordCount: Int?

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .regular))
            .tracking(0.4)
    }

    var label: String {
        let seconds = duration.flatMap { $0.isFinite && $0 > 0 ? String(format: "%.1fs", $0) : nil }
        if let count = wordCount, count > 0 {
            return seconds.map { "\(count) words · \($0)" } ?? "\(count) words"
        }
        return seconds ?? "Copied"
    }
}
