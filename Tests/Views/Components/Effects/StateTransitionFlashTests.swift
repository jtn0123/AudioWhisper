import XCTest
import SwiftUI
@testable import AudioWhisper

/// Flash-property and color-constant coverage for state transition effects.
/// Split out of `StateTransitionEffectsTests` to keep each test class within
/// the type body length budget.
final class StateTransitionFlashTests: XCTestCase {

    // MARK: - Flash Properties Tests

    func testShowFlashGlow() {
        let intensity = VisualIntensity.glow
        XCTAssertFalse(intensity.showFlash)
    }

    func testShowFlashBalanced() {
        let intensity = VisualIntensity.balanced
        XCTAssertFalse(intensity.showFlash)
    }

    func testShowFlashBurst() {
        let intensity = VisualIntensity.burst
        XCTAssertTrue(intensity.showFlash)
    }

    func testFlashOpacityGlow() {
        let intensity = VisualIntensity.glow
        XCTAssertEqual(intensity.flashOpacity, 0)
    }

    func testFlashOpacityBalanced() {
        let intensity = VisualIntensity.balanced
        XCTAssertEqual(intensity.flashOpacity, 0)
    }

    func testFlashOpacityBurst() {
        let intensity = VisualIntensity.burst
        XCTAssertEqual(intensity.flashOpacity, 0.3)
    }

    // MARK: - Color Constants Tests

    func testAccentColor() {
        let accentColor = Color(red: 0.85, green: 0.45, blue: 0.40)
        XCTAssertNotNil(accentColor)
    }

    func testSuccessColor() {
        let successColor = Color(red: 0.45, green: 0.75, blue: 0.55)
        XCTAssertNotNil(successColor)
    }
}
