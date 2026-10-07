import AVFoundation
import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildMicrophoneInputsTests: IsolatedXCTestCase {
    func testUnavailableSavedInputRemainsVisibleWithoutChangingTheSelection() throws {
        AppDefaults.selectedMicrophone = "disconnected-fixture"
        let view = RebuildPreferencesView()
        _ = try view.inspect().find(text: "Saved microphone · unavailable")
        XCTAssertEqual(AppDefaults.selectedMicrophone, "disconnected-fixture")
    }

    func testMountedChoicesRefreshOnConnectDisconnectAndActivation() throws {
        let center = NotificationCenter()
        let builtIn = RebuildMicrophoneInputs.Input(id: "builtin", name: "Built-in microphone")
        let usb = RebuildMicrophoneInputs.Input(id: "usb", name: "USB microphone")
        var devices = [builtIn]
        let inputs = RebuildMicrophoneInputs(center: center, isAuthorized: { true }, enumerate: { devices })
        AppDefaults.selectedMicrophone = usb.id
        let view = RebuildPreferencesView(inputs: inputs)
        inputs.startObserving()
        _ = try view.inspect().find(text: "Saved microphone · unavailable")
        devices.append(usb)
        center.post(name: AVCaptureDevice.wasConnectedNotification, object: nil)
        _ = try view.inspect().find(text: usb.name)
        XCTAssertThrowsError(try view.inspect().find(text: "Saved microphone · unavailable"))
        devices = [builtIn]
        center.post(name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        _ = try view.inspect().find(text: "Saved microphone · unavailable")
        XCTAssertEqual(AppDefaults.selectedMicrophone, usb.id)
        devices = [usb]
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(inputs.devices, [usb])
    }

    func testPermissionRefreshDoesNotEnumerateWithoutConsentOrForgetSavedInput() {
        var allowed = false
        var enumerations = 0
        let input = RebuildMicrophoneInputs.Input(id: "saved", name: "Saved input")
        let inputs = RebuildMicrophoneInputs(center: NotificationCenter(), isAuthorized: { allowed }, enumerate: {
            enumerations += 1
            return [input]
        })
        AppDefaults.selectedMicrophone = input.id
        inputs.startObserving()
        XCTAssertTrue(inputs.devices.isEmpty)
        XCTAssertEqual(enumerations, 0)
        allowed = true
        inputs.refresh()
        XCTAssertEqual(inputs.devices, [input])
        allowed = false
        inputs.refresh()
        XCTAssertTrue(inputs.devices.isEmpty)
        XCTAssertEqual(AppDefaults.selectedMicrophone, input.id)
        XCTAssertEqual(enumerations, 1)
    }

    func testObservationIsIdempotentAndReleasedWithThePageState() {
        let center = NotificationCenter()
        var enumerations = 0
        var inputs: RebuildMicrophoneInputs? = RebuildMicrophoneInputs(
            center: center, isAuthorized: { true }, enumerate: { enumerations += 1; return [] })
        inputs?.startObserving()
        inputs?.startObserving()
        let before = enumerations
        center.post(name: AVCaptureDevice.wasConnectedNotification, object: nil)
        XCTAssertEqual(enumerations, before + 1)
        weak var released = inputs
        inputs = nil
        XCTAssertNil(released)
        center.post(name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        XCTAssertEqual(enumerations, before + 1)
    }
}
