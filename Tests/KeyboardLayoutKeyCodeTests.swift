import Carbon
import XCTest
@testable import AudioWhisper

final class KeyboardLayoutKeyCodeTests: XCTestCase {
    private typealias Translate = KeyboardLayoutKeyCode.Translate

    func testConventionalKeyIsKeptWhenItTypesTheCharacter() {
        let qwerty: Translate = { $0 == CGKeyCode(kVK_ANSI_V) ? "v" : "x" }
        XCTAssertEqual(KeyboardLayoutKeyCode.keyCode(for: "v", layouts: [qwerty]), CGKeyCode(kVK_ANSI_V))
    }

    func testDvorakResolvesThePhysicalKeyThatTypesV() {
        // On Dvorak the ANSI "." key types "v" and the ANSI V key types "k".
        let dvorak: Translate = { [CGKeyCode(kVK_ANSI_Period): "v", CGKeyCode(kVK_ANSI_V): "k"][$0] }
        XCTAssertEqual(KeyboardLayoutKeyCode.keyCode(for: "v", layouts: [dvorak]), CGKeyCode(kVK_ANSI_Period))
    }

    func testNonLatinLayoutFallsBackToTheASCIICapableLayout() {
        let russian: Translate = { _ in "м" }
        let qwerty: Translate = { $0 == CGKeyCode(kVK_ANSI_V) ? "v" : nil }
        XCTAssertEqual(KeyboardLayoutKeyCode.keyCode(for: "v", layouts: [russian, qwerty]), CGKeyCode(kVK_ANSI_V))
    }

    func testCaseOfTheCommandLayerDoesNotMatter() {
        let shouting: Translate = { $0 == 3 ? "V" : nil }
        XCTAssertEqual(KeyboardLayoutKeyCode.keyCode(for: "v", layouts: [shouting]), 3)
    }

    func testNoLayoutFindsNothing() {
        XCTAssertNil(KeyboardLayoutKeyCode.keyCode(for: "v", layouts: []))
        XCTAssertNil(KeyboardLayoutKeyCode.keyCode(for: "v", layouts: [{ _ in nil }]))
    }

    @MainActor
    func testLivePasteKeyTypesVInTheInstalledLayout() {
        let code = KeyboardLayoutKeyCode.pasteKeyCode()
        let layouts = KeyboardLayoutKeyCode.liveLayouts()
        if layouts.isEmpty {
            XCTAssertEqual(code, CGKeyCode(kVK_ANSI_V), "without layout data the ANSI key is the fallback")
        } else {
            XCTAssertTrue(layouts.contains { $0(code)?.lowercased() == "v" })
        }
    }
}
