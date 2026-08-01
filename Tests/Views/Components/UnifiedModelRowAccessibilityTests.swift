import XCTest
@testable import AudioWhisper

/// C1: only 12 of 69 view files carried any accessibility annotation, and the
/// Dashboard — the app's largest surface — had two, both in one file. VoiceOver
/// users got unlabelled buttons across settings, model management and onboarding.
///
/// `UnifiedModelRow` is the highest-leverage fix: it backs every model list
/// (Whisper, Parakeet, MLX correction). These tests pin the strings it composes,
/// because the interesting part is not that a modifier exists but that the
/// announcement actually distinguishes one row from another and conveys install
/// and selection state.
@MainActor
final class UnifiedModelRowAccessibilityTests: XCTestCase {

    private func makeRow(
        title: String = "openai_whisper-base",
        subtitle: String = "Good balance of speed and accuracy",
        sizeText: String? = "142MB",
        statusText: String? = nil,
        isDownloaded: Bool = true,
        isDownloading: Bool = false,
        isSelected: Bool = false,
        badgeText: String? = nil
    ) -> UnifiedModelRow {
        UnifiedModelRow(
            title: title,
            subtitle: subtitle,
            sizeText: sizeText,
            statusText: statusText,
            statusColor: nil,
            isDownloaded: isDownloaded,
            isDownloading: isDownloading,
            isSelected: isSelected,
            badgeText: badgeText,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )
    }

    /// The row must name the model — otherwise every row in the list sounds the
    /// same.
    func testLabelUsesTheModelName() {
        XCTAssertEqual(makeRow().accessibilityTitle, "openai_whisper-base")
    }

    /// A "RECOMMENDED" badge is otherwise conveyed only by a coloured pill.
    func testLabelIncludesBadge() {
        let row = makeRow(badgeText: "RECOMMENDED")
        XCTAssertEqual(row.accessibilityTitle, "openai_whisper-base, recommended")
    }

    /// Install state is conveyed visually by an "Installed" caption and by the
    /// action button changing from Get to Delete — neither is obvious to
    /// VoiceOver from the row itself.
    func testValueDistinguishesInstalledFromNotInstalled() {
        XCTAssertTrue(makeRow(isDownloaded: true).accessibilityStateDescription.contains("Installed"))
        XCTAssertTrue(
            makeRow(isDownloaded: false).accessibilityStateDescription.contains("Not installed")
        )
    }

    /// Selection is conveyed only by a filled circle and a background tint.
    func testValueAnnouncesSelection() {
        XCTAssertTrue(makeRow(isSelected: true).accessibilityStateDescription.contains("Selected"))
        XCTAssertFalse(makeRow(isSelected: false).accessibilityStateDescription.contains("Selected"))
    }

    func testValueIncludesSizeAndSubtitle() {
        let description = makeRow().accessibilityStateDescription
        XCTAssertTrue(description.contains("142MB"))
        XCTAssertTrue(description.contains("Good balance of speed and accuracy"))
    }

    /// In-progress status (e.g. download percentage) has to reach the value, or
    /// progress is inaudible.
    func testValueSurfacesLiveStatus() {
        let row = makeRow(statusText: "Downloading… 45%")
        XCTAssertTrue(row.accessibilityStateDescription.contains("Downloading… 45%"))
    }

    /// A missing size must not produce a dangling separator.
    func testValueOmitsMissingSize() {
        let description = makeRow(sizeText: nil).accessibilityStateDescription
        XCTAssertFalse(description.contains(", ,"))
        XCTAssertTrue(description.contains("Installed"))
    }
}
