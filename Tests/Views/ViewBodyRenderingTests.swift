import AppKit
import SwiftUI
import XCTest
@testable import AudioWhisper

/// Renders views that otherwise only the local-only snapshot suite draws.
///
/// The older view tests construct a view and assert it is non-nil, which never
/// evaluates `body` — the waveform crash on empty input
/// (`WaveformEmptyInputRenderingTests`) survived exactly that way. These host
/// each view in a window and lay it out, which runs every `body` and helper the
/// view draws, including what sits inside a `ScrollView` (`ImageRenderer` does
/// not lay that out). They assert the view produced a non-empty layout, not
/// what it looks like: CI has no WindowServer to draw with, and pixels are the
/// snapshot suite's job.
@MainActor
final class ViewBodyRenderingTests: XCTestCase {

    // MARK: - Waveform subviews

    func testProcessingShimmerRendersAnimatedAndStill() {
        assertLaysOut(ProcessingShimmerView(color: .white, animated: true).frame(width: 200, height: 24))
        assertLaysOut(ProcessingShimmerView(color: .white, animated: false).frame(width: 200, height: 24))
    }

    func testTimerLabelRendersWithAndWithoutAStart() {
        assertLaysOut(TimerLabel(start: nil))
        assertLaysOut(TimerLabel(start: Date().addingTimeInterval(-75)))
        // A start in the future must clamp to zero rather than go negative.
        assertLaysOut(TimerLabel(start: Date().addingTimeInterval(600)))
    }

    func testHotkeyHintRenders() {
        assertLaysOut(HotkeyHint())
    }

    func testSuccessRecapRendersWithAndWithoutAWordCount() {
        assertLaysOut(SuccessRecapLabel(duration: 2.5, wordCount: 12))
        assertLaysOut(SuccessRecapLabel(duration: 2.5, wordCount: 0))
        assertLaysOut(SuccessRecapLabel(duration: nil, wordCount: nil))
    }

    // MARK: - Settings cards

    func testSettingsCardsRenderEveryRowKind() {
        let card = SettingsSectionCard(title: "General", icon: "gear") {
            SettingsToggleRow(title: "Launch at login", subtitle: "Start with macOS", isOn: .constant(true))
            SettingsToggleRow(title: "Sounds", subtitle: nil, isOn: .constant(false))
            SettingsPickerRow(
                title: "Keep history",
                subtitle: "Older transcripts are deleted",
                selection: .constant(RetentionPeriod.oneMonth),
                options: RetentionPeriod.allCases,
                display: { $0.displayName }
            )
            SettingsPickerRow(title: "Count", selection: .constant(2), options: [1, 2, 3])
            SettingsButtonRow(title: "Clear history", subtitle: "Cannot be undone", icon: "trash", role: .destructive) {}
            SettingsButtonRow(title: "Open folder") {}
            SettingsInfoRow(text: "Settings are stored on this Mac only.")
        }
        assertLaysOut(card.frame(width: 560))
    }

    // MARK: - Dashboard pages

    func testPermissionsPageRendersWithSmartPasteOnAndOff() {
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        for enabled in [true, false] {
            AppDefaults.defaults.set(enabled, forKey: "enableSmartPaste")
            assertLaysOut(
                DashboardPermissionsView()
                    .environment(PermissionManager.shared)
                    .frame(width: 720, height: 900)
            )
        }
    }

    // MARK: - Helper

    private func assertLaysOut(
        _ view: some View,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 1000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        XCTAssertGreaterThan(size.width, 0, "view laid out with zero width", file: file, line: line)
        XCTAssertGreaterThan(size.height, 0, "view laid out with zero height", file: file, line: line)
        window.contentView = nil
        window.close()
    }
}
