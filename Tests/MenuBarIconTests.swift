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

    // The renderer holds its button weakly (the status item owns it in the app),
    // so each test keeps its own strong reference for the renderer's lifetime.

    func testRendererStartsIdle() {
        let button = makeButton()
        let renderer = MenuBarIconRenderer(button: button)
        XCTAssertEqual(renderer.state, .idle)
    }

    func testSetStateRecordsTheNewState() {
        let button = makeButton()
        let renderer = MenuBarIconRenderer(button: button)

        renderer.setState(.recording)
        XCTAssertEqual(renderer.state, .recording)

        renderer.setState(.processing)
        XCTAssertEqual(renderer.state, .processing)

        renderer.setState(.error)
        XCTAssertEqual(renderer.state, .error)
    }

    /// Each static state must reach the button with the right template flag:
    /// idle is the only one AppKit may recolour; the rest carry status colour.
    func testSetStateAppliesTheStatesImageToTheButton() {
        let button = makeButton()
        let renderer = MenuBarIconRenderer(button: button)

        for state: MenuBarIconState in [.processing, .success, .error] {
            renderer.setState(state)
            let image = try? XCTUnwrap(button.image, "\(state) must set an image")
            XCTAssertEqual(image?.isTemplate, false, "\(state) is tinted, so must not be a template")
        }

        renderer.setState(.idle)
        XCTAssertEqual(button.image?.isTemplate, true, "idle must be a template so it follows the menu bar")
    }

    /// `setState` early-returns on an unchanged state. That guard is what stops
    /// the recording pulse timer being torn down and restarted on every audio
    /// level update, which would visibly stutter the animation.
    func testSettingTheSameStateTwiceIsANoOp() {
        let button = makeButton()
        let renderer = MenuBarIconRenderer(button: button)

        renderer.setState(.processing)
        button.image = nil
        renderer.setState(.processing)

        XCTAssertEqual(renderer.state, .processing)
        XCTAssertNil(button.image, "a repeated state must not re-render")
    }

    func testCanReturnToIdleFromEveryState() {
        for state: MenuBarIconState in [.recording, .processing, .success, .error] {
            let button = makeButton()
            let renderer = MenuBarIconRenderer(button: button)
            renderer.setState(state)
            renderer.setState(.idle)
            XCTAssertEqual(renderer.state, .idle, "must be able to return to idle from \(state)")
            XCTAssertEqual(button.image?.isTemplate, true, "returning from \(state) must restore the idle image")
        }
    }

    func testRefreshReRendersWithoutChangingState() {
        let button = makeButton()
        let renderer = MenuBarIconRenderer(button: button)
        renderer.setState(.processing)
        button.image = nil

        renderer.refresh()

        XCTAssertEqual(renderer.state, .processing,
                       "refresh only re-renders; it must not alter the state machine")
        XCTAssertNotNil(button.image, "refresh must redraw the current state's image")
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

    private func makeButton() -> NSButton {
        // A plain button, not one vended by `NSStatusBar.system`: creating a
        // status item needs a WindowServer connection and aborts the whole test
        // process on a CI runner. The renderer only ever sets `image`.
        NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    }
}
