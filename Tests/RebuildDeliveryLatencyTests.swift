import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildDeliveryLatencyTests: IsolatedXCTestCase {
    func testSlowHistoryDoesNotDelayPasteAndStillSavesExactlyOnce() async throws {
        AppDefaults.enableSmartPaste = true
        AppDefaults.playCompletionSound = false
        var releaseSave: CheckedContinuation<Void, Never>?
        var saves = 0
        var pastes = 0
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { URL(fileURLWithPath: "/fixture.wav") }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "Ready now", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in
                saves += 1
                await withCheckedContinuation { releaseSave = $0 }
            })
        services.capturePasteDestination = {
            RebuildPasteDestination(processIdentifier: 111, bundleIdentifier: "fixture.editor",
                activate: { true }, isTerminated: { false }, foregroundPID: { 111 })
        }
        let paste = PasteManager(accessibilityManager: AccessibilityPermissionManager(permissionCheck: { true }),
                                 foregroundPID: { 111 }, pasteEvent: { pastes += 1 })
        let delivery = RebuildPasteDelivery(focusedText: .init(read: { _ in nil }, pressPasteMenuItem: { _ in false }))
        let session = RebuildSession(services: services, paste: paste, delivery: delivery)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.toggleRecording()
        session.finishRecording()
        for _ in 0..<100 where releaseSave == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(releaseSave)
        XCTAssertEqual(session.pendingHistoryWrites, 1)
        XCTAssertEqual(pastes, 1, "A slow library write must not hold back the user's text")
        XCTAssertNotNil(session.timing.deliveryMilliseconds)
        XCTAssertNotNil(session.timing.startupMilliseconds)
        XCTAssertNotNil(session.timing.processingMilliseconds)
        releaseSave?.resume()
        await session.waitForHistoryWrites()
        for _ in 0..<100 where session.phase == .transcribing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(pastes, 1)
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.pendingHistoryWrites, 0)
        session.cancel()
    }

    func testMonotonicTimingSeparatesStartupProcessingAndDelivery() {
        let timing = RebuildSessionTiming(requested: 100, recording: 100.02, stopped: 103,
                                         recognized: 103.4, delivered: 103.45)
        XCTAssertEqual(timing.startupMilliseconds ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(timing.processingMilliseconds ?? -1, 400, accuracy: 0.001)
        XCTAssertEqual(timing.deliveryMilliseconds ?? -1, 450, accuracy: 0.001)
        XCTAssertNil(RebuildSessionTiming().deliveryMilliseconds)
    }

    func testCancelledCompletedSessionStillFinishesItsHistoryWrite() async throws {
        AppDefaults.enableSmartPaste = false
        var release: CheckedContinuation<Void, Never>?
        var saved = false
        let services = RebuildSessionServices(
            start: { _ in true }, stop: { URL(fileURLWithPath: "/fixture.wav") }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "Delivered words", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in
                await withCheckedContinuation { release = $0 }
                saved = true
                throw NSError(domain: "fixture", code: 1)
            })
        let session = RebuildSession(services: services)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.toggleRecording()
        session.finishRecording()
        for _ in 0..<100 where release == nil { try await Task.sleep(for: .milliseconds(5)) }
        session.cancel()
        release?.resume()
        await session.waitForHistoryWrites()
        XCTAssertTrue(saved)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.notice, "A completed older write must not report failure on a replacement session")
    }
}
