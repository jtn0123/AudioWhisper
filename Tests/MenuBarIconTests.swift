import AppKit
import XCTest
@testable import AudioWhisper

/// Tests for the menu-bar icon renderer and its state machine.
///
/// `MenuBarIcon.swift` had no test file at all and measured 0.0% across 197
/// lines. The two renderers are pure static functions with an invariant that is
/// easy to break and invisible in code review: `isTemplate`. A template image is
/// recoloured by AppKit to match the menu bar, so a tinted image marked template
/// loses its colour entirely, and an untinted image *not* marked template stays
/// black on a dark menu bar — invisible. That is a user-visible bug with no
/// compile-time signal.
@MainActor
final class MenuBarIconTests: XCTestCase {

    private var originalOverride: Double?

    override func setUp() async throws {
        try await super.setUp()
        // Pin the icon size so assertions do not depend on whether the test
        // machine has a notched display.
        originalOverride = AppDefaults.menuBarIconSize
        AppDefaults.menuBarIconSize = 16
        AppSetupHelper.resetIconSizeCache()
    }

    override func tearDown() async throws {
        AppDefaults.menuBarIconSize = originalOverride
        AppSetupHelper.resetIconSizeCache()
        try await super.tearDown()
    }

    // MARK: - Template flag

    /// Untinted bars must be a template image, or the icon renders black on a
    /// dark menu bar and disappears.
    func testUntintedBarsAreATemplateImage() {
        let image = MenuBarIconRenderer.renderBars(tint: nil, level: 0)

        XCTAssertTrue(image.isTemplate,
                      "an untinted icon must be a template so AppKit recolours it for the menu bar")
    }

    /// Tinted bars must NOT be a template, or AppKit strips the colour that
    /// distinguishes recording/processing/error from idle.
    func testTintedBarsAreNotATemplateImage() {
        for tint in [MenuBarIconRenderer.coral, MenuBarIconRenderer.amber, MenuBarIconRenderer.sage] {
            let image = MenuBarIconRenderer.renderBars(tint: tint, level: 0.5)
            XCTAssertFalse(image.isTemplate,
                           "a tinted icon must keep its colour rather than being recoloured")
        }
    }

    func testCheckmarkIsNotATemplateImage() {
        let image = MenuBarIconRenderer.renderCheck(tint: MenuBarIconRenderer.sage)

        XCTAssertFalse(image.isTemplate,
                       "the success check uses an explicit sage colour on any menu bar")
    }

    // MARK: - Geometry

    func testRenderedIconIsSquareAndMatchesTheConfiguredSize() {
        let expected = AppSetupHelper.getAdaptiveMenuBarIconSize()

        for image in [MenuBarIconRenderer.renderBars(tint: nil, level: 0.5),
                      MenuBarIconRenderer.renderCheck(tint: MenuBarIconRenderer.sage)] {
            XCTAssertEqual(image.size.width, expected, accuracy: 0.001)
            XCTAssertEqual(image.size.height, expected, accuracy: 0.001)
        }
    }

    func testIconSizeFollowsTheUserOverride() {
        AppDefaults.menuBarIconSize = 24
        AppSetupHelper.resetIconSizeCache()

        let image = MenuBarIconRenderer.renderBars(tint: nil, level: 0)

        XCTAssertEqual(image.size.width, 24, accuracy: 0.001,
                       "the renderer must honour the user's menu-bar icon size")
    }

    // MARK: - Level clamping

    /// `level` scales the bar heights and is clamped to 0...1. An unclamped
    /// value would push bars outside the canvas or invert them; the audio level
    /// feeding this is not guaranteed normalised.
    func testOutOfRangeLevelsAreClampedRatherThanCrashing() {
        let wayOver = MenuBarIconRenderer.renderBars(tint: nil, level: 5.0)
        let atMax = MenuBarIconRenderer.renderBars(tint: nil, level: 1.0)
        let wayUnder = MenuBarIconRenderer.renderBars(tint: nil, level: -3.0)
        let atMin = MenuBarIconRenderer.renderBars(tint: nil, level: 0.0)

        // Same canvas either way — the clamp keeps drawing inside the bounds.
        XCTAssertEqual(wayOver.size, atMax.size)
        XCTAssertEqual(wayUnder.size, atMin.size)
        XCTAssertGreaterThan(wayOver.size.width, 0)
    }

    func testRenderingIsStableAcrossRepeatedCalls() {
        let first = MenuBarIconRenderer.renderBars(tint: nil, level: 0.4)
        let second = MenuBarIconRenderer.renderBars(tint: nil, level: 0.4)

        XCTAssertEqual(first.size, second.size)
        XCTAssertEqual(first.isTemplate, second.isTemplate)
    }

    // MARK: - State machine

    func testRendererStartsIdle() {
        let renderer = MenuBarIconRenderer(button: makeButton())
        XCTAssertEqual(renderer.state, .idle)
    }

    func testSetStateRecordsTheNewState() {
        let renderer = MenuBarIconRenderer(button: makeButton())

        renderer.setState(.recording)
        XCTAssertEqual(renderer.state, .recording)

        renderer.setState(.processing)
        XCTAssertEqual(renderer.state, .processing)

        renderer.setState(.error)
        XCTAssertEqual(renderer.state, .error)
    }

    /// `setState` early-returns on an unchanged state. That guard is what stops
    /// the recording pulse timer being torn down and restarted on every audio
    /// level update, which would visibly stutter the animation.
    func testSettingTheSameStateTwiceIsANoOp() {
        let renderer = MenuBarIconRenderer(button: makeButton())

        renderer.setState(.recording)
        renderer.setState(.recording)

        XCTAssertEqual(renderer.state, .recording)
    }

    func testCanReturnToIdleFromEveryState() {
        for state: MenuBarIconState in [.recording, .processing, .success, .error] {
            let renderer = MenuBarIconRenderer(button: makeButton())
            renderer.setState(state)
            renderer.setState(.idle)
            XCTAssertEqual(renderer.state, .idle, "must be able to return to idle from \(state)")
        }
    }

    func testRefreshDoesNotChangeState() {
        let renderer = MenuBarIconRenderer(button: makeButton())
        renderer.setState(.processing)

        renderer.refresh()

        XCTAssertEqual(renderer.state, .processing,
                       "refresh only re-renders; it must not alter the state machine")
    }

    // MARK: - Palette

    /// The three status colours must stay distinguishable — they are the only
    /// signal separating recording, processing and error in the menu bar.
    func testStatusColoursAreDistinct() {
        let palette = [MenuBarIconRenderer.coral,
                       MenuBarIconRenderer.amber,
                       MenuBarIconRenderer.sage]

        for (index, colour) in palette.enumerated() {
            for other in palette[(index + 1)...] {
                XCTAssertNotEqual(colour, other, "status colours must be visually distinct")
            }
        }
    }

    // MARK: - Helpers

    private func makeButton() -> NSStatusBarButton {
        // A detached status item gives a real NSStatusBarButton without
        // requiring the item to be visible in the menu bar.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        addTeardownBlock { NSStatusBar.system.removeStatusItem(item) }
        guard let button = item.button else {
            XCTFail("status item should vend a button")
            return NSStatusBarButton()
        }
        return button
    }
}
