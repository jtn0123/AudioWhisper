import AppKit
import SwiftUI
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildRecorderLayoutTests: IsolatedXCTestCase {
    func testHostingTheRecorderKeepsItsControlsAtAUsableSize() throws {
        try XCTSkipUnless(WindowServer.hasActiveDisplay, "Hosting layout requires a WindowServer")
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }))
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.toggleRecording()
        defer { session.cancel() }
        let host = NSHostingController(rootView: RebuildRecorderView(session: session, recorder: AudioEngineRecorder()))
        XCTAssertGreaterThanOrEqual(host.view.fittingSize.width, 380,
                                    "The HUD must not collapse to its narrowest waveform/control width")
        XCTAssertGreaterThanOrEqual(host.view.fittingSize.height, 230)
    }

    func testRecorderAboveDockStaysCompletelyInVisibleFrame() {
        let screen = NSRect(x: 0, y: 57, width: 1024, height: 681)
        let frame = NSRect(x: 0, y: 0, width: 380, height: 230)
        let origin = RecordingWindowStyle.frameOrigin(for: frame, on: screen)
        XCTAssertTrue(screen.contains(NSRect(origin: origin, size: frame.size)))
    }

    func testRecorderWithCentreOnScreenButButtonsBeyondEdgeIsRecovered() {
        let screen = NSRect(x: 1440, y: 50, width: 1920, height: 1030)
        let frame = NSRect(x: 3120, y: 500, width: 380, height: 230)
        let origin = RecordingWindowStyle.frameOrigin(for: frame, on: screen)
        XCTAssertTrue(screen.contains(NSRect(origin: origin, size: frame.size)))
    }
}
