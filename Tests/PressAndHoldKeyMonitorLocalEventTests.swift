import XCTest
import AppKit
@testable import AudioWhisper

/// The press-and-hold key has to work while AudioWhisper itself is the active
/// app — with the Dashboard focused, say. A global monitor never sees those
/// events, so the key used to do nothing there.
final class PressAndHoldKeyMonitorLocalEventTests: XCTestCase {
    private var globalTokens: [Int] = []
    private var localHandlers: [(NSEvent.EventTypeMask, (NSEvent) -> NSEvent?)] = []
    private var removed: [String] = []

    override func tearDown() {
        globalTokens.removeAll()
        localHandlers.removeAll()
        removed.removeAll()
        super.tearDown()
    }

    func testEveryGlobalMonitorHasALocalOneAndStopRemovesBoth() {
        let monitor = makeMonitor()

        monitor.start()
        XCTAssertEqual(globalTokens.count, 1)
        XCTAssertEqual(localHandlers.map(\.0), [.flagsChanged])

        monitor.stop()
        XCTAssertEqual(removed.sorted(), ["global-1", "local-1"])
    }

    func testTheKeyWorksWhileAudioWhisperIsTheActiveApp() throws {
        let pressed = expectation(description: "key down handled")
        let monitor = makeMonitor { pressed.fulfill() }
        monitor.start()
        let handler = try XCTUnwrap(localHandlers.first?.1)
        let event = try XCTUnwrap(rightCommandDown())

        let passedOn = handler(event)

        wait(for: [pressed], timeout: 1.0)
        XCTAssertIdentical(passedOn, event,
                           "the key must still reach the focused window, e.g. as ⌘ for a shortcut")
        monitor.stop()
    }

    func testOtherModifierKeysPassThroughUntouched() throws {
        let pressed = expectation(description: "key down handled")
        pressed.isInverted = true
        let monitor = makeMonitor { pressed.fulfill() }
        monitor.start()
        let handler = try XCTUnwrap(localHandlers.first?.1)
        let leftOption = try XCTUnwrap(flagsChanged(keyCode: PressAndHoldKey.leftOption.keyCode,
                                                    flags: [.option]))

        XCTAssertIdentical(handler(leftOption), leftOption)

        wait(for: [pressed], timeout: 0.3)
        monitor.stop()
    }

    // MARK: - Helpers

    private func makeMonitor(keyDown: @escaping () -> Void = {}) -> PressAndHoldKeyMonitor {
        PressAndHoldKeyMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: keyDown,
            keyUpHandler: nil,
            addGlobalMonitor: { [weak self] _, _ in
                guard let self else { return nil }
                globalTokens.append(globalTokens.count + 1)
                return "global-\(globalTokens.count)"
            },
            addLocalMonitor: { [weak self] mask, handler in
                guard let self else { return nil }
                localHandlers.append((mask, handler))
                return "local-\(localHandlers.count)"
            },
            removeMonitor: { [weak self] token in
                self?.removed.append(token as? String ?? "?")
            }
        )
    }

    private func rightCommandDown() -> NSEvent? {
        // NX_DEVICERCMDKEYMASK alongside the device-independent .command flag,
        // as the window server reports a right-Command press.
        let flags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)
        return flagsChanged(keyCode: PressAndHoldKey.rightCommand.keyCode, flags: flags)
    }

    private func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
