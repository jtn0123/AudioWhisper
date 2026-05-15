import AppKit

// MARK: - MenuBarIconRenderer
//
// Replaces `AppSetupHelper.createMenuBarIcon()` and the 1Hz blink animation
// in `AppDelegate+Hotkeys.swift`. Draws a stylized 5-bar waveform glyph
// that ties back to the Classic visualization style, plus an animator that
// produces a smooth coral pulse during recording.
//
// Usage from AppDelegate:
//   private var iconRenderer: MenuBarIconRenderer?
//   ...
//   if let button = statusItem?.button {
//       iconRenderer = MenuBarIconRenderer(button: button)
//       iconRenderer?.setState(.idle)
//   }
//   // ...later:
//   iconRenderer?.setState(.recording)
//   iconRenderer?.setState(.processing)
//   iconRenderer?.setState(.success)   // auto-returns to .idle after ~1.5s
//   iconRenderer?.setState(.error)
internal enum MenuBarIconState: Equatable {
    case idle
    case recording
    case processing
    case success
    case error
}

@MainActor
internal final class MenuBarIconRenderer {

    // MARK: - Palette (matches AW recording window)
    static let coral     = NSColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1.0)
    static let amber     = NSColor(red: 0.89, green: 0.65, blue: 0.27, alpha: 1.0)
    static let sage      = NSColor(red: 0.37, green: 0.66, blue: 0.46, alpha: 1.0)

    private weak var button: NSStatusBarButton?
    private var animationTimer: DispatchSourceTimer?
    private(set) var state: MenuBarIconState = .idle
    private var successResetWork: DispatchWorkItem?

    init(button: NSStatusBarButton) {
        self.button = button
    }

    deinit {
        animationTimer?.cancel()
    }

    func setState(_ newState: MenuBarIconState) {
        guard state != newState else { return }
        state = newState

        // Cancel any pending success-auto-reset
        successResetWork?.cancel()
        successResetWork = nil

        // Stop any running animation
        stopAnimation()

        switch newState {
        case .idle:
            button?.image = Self.renderBars(tint: nil, level: 0)
        case .recording:
            startRecordingPulse()
        case .processing:
            button?.image = Self.renderBars(tint: Self.amber, level: 0.35)
        case .success:
            button?.image = Self.renderCheck(tint: Self.sage)
            // Return to idle after a beat
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.state == .success else { return }
                self.setState(.idle)
            }
            successResetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        case .error:
            button?.image = Self.renderBars(tint: Self.coral.withAlphaComponent(0.55), level: 0)
        }
    }

    /// Re-renders the icon for the current state without changing it. Used
    /// when the menu bar icon size changes (e.g. display reconfiguration);
    /// `setState` is a no-op when called with the current state.
    func refresh() {
        switch state {
        case .idle:       button?.image = Self.renderBars(tint: nil, level: 0)
        case .processing: button?.image = Self.renderBars(tint: Self.amber, level: 0.35)
        case .error:      button?.image = Self.renderBars(tint: Self.coral.withAlphaComponent(0.55), level: 0)
        case .success:    button?.image = Self.renderCheck(tint: Self.sage)
        case .recording:  break // the pulse timer re-renders every frame
        }
    }

    // MARK: - Pulse animation (smooth, ~0.4 Hz)

    private func startRecordingPulse() {
        guard let button = button else { return }
        stopAnimation()

        let start = Date()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.05)  // 20 fps
        timer.setEventHandler { [weak self, weak button] in
            guard let self = self,
                  let button = button,
                  self.state == .recording else { return }

            let elapsed = Date().timeIntervalSince(start)
            // 0.4 Hz pulse — opacity oscillates between 0.55 and 1.0
            let pulse = (sin(elapsed * 2 * .pi * 0.4) + 1) * 0.5
            let alpha = 0.55 + pulse * 0.45

            // Gentle level wobble in bar heights
            let level = 0.4 + sin(elapsed * 3.0) * 0.25

            let tint = Self.coral.withAlphaComponent(CGFloat(alpha))
            button.image = Self.renderBars(tint: tint, level: CGFloat(level))
        }
        animationTimer = timer
        timer.resume()
    }

    private func stopAnimation() {
        animationTimer?.cancel()
        animationTimer = nil
    }

    // MARK: - Drawing

    /// Draws the 5-bar AW glyph. Pass `tint == nil` for a template image
    /// that auto-adapts to light/dark menu bar. Pass an NSColor (with the
    /// desired alpha) for state-colored states.
    /// `level` (0–1) scales each bar's height — used to give the recording
    /// state a subtle "alive" wobble.
    static func renderBars(tint: NSColor?, level: CGFloat) -> NSImage {
        let size = AppSetupHelper.getAdaptiveMenuBarIconSize()
        let canvas = NSSize(width: size, height: size)

        let img = NSImage(size: canvas, flipped: false) { _ in
            let color: NSColor = tint ?? NSColor.labelColor
            color.setFill()

            // Bar heights — middle bar tallest, taper outward
            let baseHeights: [CGFloat] = [0.45, 0.85, 1.0, 0.7, 0.35]
            let heights = baseHeights.map { $0 * (0.7 + max(0, min(1, level)) * 0.3) }

            let barW = max(1.0, size / 11.0)
            let gap  = max(0.5, size / 14.0)
            let totalW = barW * 5 + gap * 4
            let startX = (size - totalW) * 0.5
            let maxBarH = size * 0.78

            for (i, h) in heights.enumerated() {
                let barH = maxBarH * h
                let x = startX + CGFloat(i) * (barW + gap)
                let y = (size - barH) * 0.5
                let path = NSBezierPath(
                    roundedRect: NSRect(x: x, y: y, width: barW, height: barH),
                    xRadius: barW / 2,
                    yRadius: barW / 2
                )
                path.fill()
            }

            return true
        }
        img.isTemplate = (tint == nil)
        return img
    }

    /// Sage checkmark for the success state. Not a template image — uses
    /// explicit sage color so it reads correctly on any menu bar.
    static func renderCheck(tint: NSColor) -> NSImage {
        let size = AppSetupHelper.getAdaptiveMenuBarIconSize()
        let canvas = NSSize(width: size, height: size)

        let img = NSImage(size: canvas, flipped: false) { _ in
            tint.setStroke()
            let path = NSBezierPath()
            path.lineWidth = size * 0.16
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // In AppKit (origin = bottom-left), the check shape mirrors
            // vertically vs. screen coords. So y values are top-down here.
            path.move(to: NSPoint(x: size * 0.24, y: size * 0.50))
            path.line(to: NSPoint(x: size * 0.43, y: size * 0.30))
            path.line(to: NSPoint(x: size * 0.78, y: size * 0.70))
            path.stroke()
            return true
        }
        img.isTemplate = false
        return img
    }
}
