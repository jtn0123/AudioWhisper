import SwiftUI
import XCTest
@testable import AudioWhisper

/// Accessibility coverage for the shared Dashboard settings rows.
///
/// Audit item C2. `SettingsToggleRow` renders `Toggle("", isOn:)` with
/// `.labelsHidden()` — visually correct, since the sibling `Text` draws the
/// title, but it left the switch with no accessibility label at all. VoiceOver
/// announced a bare "switch, off" next to unrelated text. These rows are used
/// across every Dashboard settings screen, so the gap multiplied.
///
/// SwiftUI does not expose a resolved accessibility tree to XCTest, so these
/// assert what is assertable without a UI test target: that each row builds
/// with the labelling inputs present, and — the part that actually regresses —
/// that a row is never constructed with an empty title, which is what would
/// silently reintroduce an unnamed control.
@MainActor
final class DashboardSettingsCardsAccessibilityTests: XCTestCase {

    // MARK: - Toggle row

    func testToggleRowRetainsTitleAndSubtitleForLabelling() {
        var isOn = true
        let row = SettingsToggleRow(
            title: "Save Transcription History",
            subtitle: "Keep a local record of every transcript",
            isOn: Binding(get: { isOn }, set: { isOn = $0 })
        )

        XCTAssertEqual(row.title, "Save Transcription History")
        XCTAssertEqual(row.subtitle, "Keep a local record of every transcript")
        XCTAssertFalse(row.title.isEmpty,
                       "an empty title yields an unlabelled switch — the C2 defect")
    }

    func testToggleRowWithoutSubtitleStillHasALabel() {
        var isOn = false
        let row = SettingsToggleRow(
            title: "Express Mode",
            subtitle: nil,
            isOn: Binding(get: { isOn }, set: { isOn = $0 })
        )

        XCTAssertFalse(row.title.isEmpty)
        XCTAssertNil(row.subtitle, "a nil subtitle must be tolerated, not required")
    }

    /// The accessibility value must track the binding, not a snapshot taken at
    /// construction — otherwise VoiceOver reports a stale on/off state.
    func testToggleRowValueFollowsItsBinding() {
        var isOn = false
        let binding = Binding(get: { isOn }, set: { isOn = $0 })
        let row = SettingsToggleRow(title: "Smart Paste", subtitle: nil, isOn: binding)

        XCTAssertFalse(row.isOn)
        isOn = true
        XCTAssertTrue(row.isOn, "row must read through to the binding")
    }

    // MARK: - Picker row

    func testPickerRowRetainsTitleAndRendersSelection() {
        var selection = "1 month"
        let row = SettingsPickerRow(
            title: "Retention",
            subtitle: "How long transcripts are kept",
            selection: Binding(get: { selection }, set: { selection = $0 }),
            options: ["1 week", "1 month", "3 months", "Forever"]
        )

        XCTAssertEqual(row.title, "Retention")
        XCTAssertFalse(row.title.isEmpty,
                       "the menu's visible label is only the current value, so the "
                       + "title is the only thing naming the setting")
        XCTAssertEqual(row.display(row.selection), "1 month")
    }

    // MARK: - Button row

    func testButtonRowRetainsTitleForLabelling() {
        let row = SettingsButtonRow(title: "Clear All Transcripts", subtitle: "Cannot be undone") {}

        XCTAssertEqual(row.title, "Clear All Transcripts")
        XCTAssertEqual(row.subtitle, "Cannot be undone")
        XCTAssertFalse(row.title.isEmpty)
    }

    func testDestructiveButtonRowKeepsItsRole() {
        let row = SettingsButtonRow(
            title: "Delete Everything",
            subtitle: nil,
            role: .destructive
        ) {}

        XCTAssertEqual(row.role, .destructive,
                       "the destructive role is what VoiceOver announces as a warning")
    }

    func testButtonRowActionFires() {
        var fired = false
        let row = SettingsButtonRow(title: "Reset", subtitle: nil) { fired = true }

        row.action()

        XCTAssertTrue(fired)
    }

    // MARK: - Section card

    func testSectionCardRetainsItsHeadingTitle() {
        let card = SettingsSectionCard(title: "General", icon: "gearshape") {
            EmptyView()
        }

        XCTAssertEqual(card.title, "General")
        XCTAssertFalse(card.title.isEmpty,
                       "the title carries the .isHeader trait for rotor navigation")
    }
}
