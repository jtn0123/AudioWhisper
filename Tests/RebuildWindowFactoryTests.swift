import AppKit
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildWindowFactoryTests: IsolatedXCTestCase {
    func testActualWorkspaceAndRecorderKeepTheirDistinctNativePoliciesWithoutPresentation() throws {
        _ = NSApplication.shared
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in false }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }))
        let navigation = RebuildNavigation()
        navigation.selection = .models
        let recorder = AudioEngineRecorder()
        let workspace = RebuildWindowFactory.workspace(root: RebuildRootView(
            session: session, navigation: navigation, recorder: recorder, importAudio: {},
            history: MockDataManager(), readShortcut: { nil }))
        workspace.isReleasedWhenClosed = false
        let overlay = RebuildWindowFactory.recorder(session: session, recorder: recorder)
        overlay.isReleasedWhenClosed = false
        defer {
            workspace.contentViewController = nil; workspace.close()
            overlay.contentViewController = nil; overlay.close()
        }
        XCTAssertEqual(workspace.title, "AudioWhisper Rebuild")
        XCTAssertEqual(workspace.minSize, NSSize(width: 870, height: 620))
        XCTAssertTrue(workspace.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
        XCTAssertEqual(workspace.level, .normal)
        XCTAssertFalse(workspace.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(workspace.isVisible)
        workspace.setContentSize(NSSize(width: 900, height: 650))
        let content = try XCTUnwrap(workspace.contentViewController?.view)
        content.layoutSubtreeIfNeeded()
        XCTAssertEqual(content.frame.size, workspace.contentLayoutRect.size)
        XCTAssertEqual(overlay.frame.size, NSSize(width: 380, height: 230))
        XCTAssertEqual(overlay.level, .floating)
        XCTAssertTrue(overlay.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(overlay.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(overlay.isVisible)
    }
}
