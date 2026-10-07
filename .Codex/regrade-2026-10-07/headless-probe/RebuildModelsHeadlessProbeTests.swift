import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import AudioWhisper

/// Feasibility probe for a semantic, offscreen Models fixture. No live consent,
/// recording, downloads or shortcut registration are part of this test.
@MainActor
final class RebuildModelsHeadlessProbeTests: IsolatedXCTestCase {
    func testBlockedSetupControlRoutesToSetupWithoutRequestingConsent() async throws {
        var openedSetup = 0
        var requests = 0
        var starts = 0
        let session = RebuildSession(
            services: RebuildSessionServices(
                start: { _ in starts += 1; return false }, stop: { nil }, cancel: {},
                transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
                copy: { _ in }, save: { _, _, _ in }),
            setup: RebuildSetupServices(
                selection: { .current }, microphoneStatus: { AVAuthorizationStatus.notDetermined },
                requestMicrophone: { _ in requests += 1 }, openMicrophoneSettings: {},
                runtimeReady: { _ in true }, modelInstalled: { _ in false },
                install: { _ in XCTFail("Mounting must not install a model") },
                verify: { _ in ModelVerificationResult(succeeded: true, message: "unused") }))
        session.openSetup = { openedSetup += 1 }
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        await session.refreshSetup()
        let hosting = NSHostingView(rootView: RebuildModelsView(session: session))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 670, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        var finish: (any NSAccessibilityProtocol)?
        for _ in 0..<50 {
            hosting.layoutSubtreeIfNeeded()
            finish = elements(hosting).first {
                $0.accessibilityRole() == .button &&
                    ($0.accessibilityLabel() == "Finish setup" || $0.accessibilityTitle() == "Finish setup")
            }
            if finish != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        if finish == nil {
            print("HEADLESS_ROOT_CHILDREN", hosting.accessibilityChildren()?.map { String(reflecting: type(of: $0)) } ?? [])
            for element in elements(hosting) {
                print("HEADLESS_AX", element.accessibilityRole()?.rawValue ?? "nil",
                      element.accessibilityLabel() ?? "nil", element.accessibilityTitle() ?? "nil")
            }
        }
        let button = try XCTUnwrap(finish, "The real Models control must be present in the offscreen accessibility tree")
        XCTAssertTrue(button.isAccessibilityEnabled())
        XCTAssertTrue(button.accessibilityPerformPress())
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(openedSetup, 1)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(session.readiness.ready)
    }

    private func elements(_ root: Any) -> [any NSAccessibilityProtocol] {
        var visited = Set<ObjectIdentifier>()
        func walk(_ object: Any) -> [any NSAccessibilityProtocol] {
            guard let element = object as? any NSAccessibilityProtocol,
                  visited.insert(ObjectIdentifier(element)).inserted else { return [] }
            return [element] + (element.accessibilityChildren() ?? []).flatMap(walk)
        }
        return walk(root)
    }
}
