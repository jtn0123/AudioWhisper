import AudioToolbox
import CoreAudio
import XCTest
@testable import AudioWhisper

final class AudioInputRoutingTests: XCTestCase {
    func testSelectedUIDIsResolvedAndAppliedBeforeCapture() throws {
        var events: [String] = []
        let routing = AudioInputRouting(
            resolveDevice: { uid in
                events.append("resolve:\(uid)")
                return 99
            },
            applyDevice: { device, _ in events.append("apply:\(device)") })
        let unit = try XCTUnwrap(AudioUnit(bitPattern: 1)) // Never dereferenced by the injected operations.
        let device = try routing.prepare(selectedUID: "usb-microphone", unit: unit)
        XCTAssertEqual(device, 99)
        XCTAssertEqual(events, ["resolve:usb-microphone", "apply:99"])
    }

    func testSystemDefaultIsResolvedOncePerCapture() throws {
        var calls = 0
        var applied: [AudioDeviceID] = []
        let routing = AudioInputRouting(
            resolveDevice: { uid in
                XCTAssertTrue(uid.isEmpty)
                calls += 1
                return calls == 1 ? 42 : 77
            }, applyDevice: { id, _ in applied.append(id) })
        let unit = try XCTUnwrap(AudioUnit(bitPattern: 1))
        XCTAssertEqual(try routing.prepare(selectedUID: "", unit: unit), 42)
        XCTAssertEqual(try routing.prepare(selectedUID: "", unit: unit), 77)
        XCTAssertEqual(applied, [42, 77])
    }

    func testDisconnectedSelectionNeverFallsBackOrAppliesAnotherDevice() throws {
        var applied = false
        let routing = AudioInputRouting(
            resolveDevice: { _ in AudioDeviceID(kAudioObjectUnknown) }, applyDevice: { _, _ in applied = true })
        let unit = try XCTUnwrap(AudioUnit(bitPattern: 1))
        XCTAssertThrowsError(try routing.prepare(selectedUID: "disconnected", unit: unit))
        XCTAssertFalse(applied)
    }

    func testRoutingFailurePropagatesWithoutPretendingCaptureSucceeded() throws {
        let routing = AudioInputRouting(
            resolveDevice: { _ in 99 }, applyDevice: { _, _ in throw AudioInputError.routingFailed(-50) })
        let unit = try XCTUnwrap(AudioUnit(bitPattern: 1))
        XCTAssertThrowsError(try routing.prepare(selectedUID: "usb", unit: unit)) { error in
            XCTAssertTrue(error.localizedDescription.contains("-50"))
        }
    }
}
