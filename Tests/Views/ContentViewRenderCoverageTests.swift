import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

/// Renders ContentView to exercise its body (waveform container, overlays,
/// sheets) and exercises the ContentView+Recording.swift error-path helpers.
@MainActor
final class ContentViewRenderCoverageTests: XCTestCase {

    private func makeViewModel(statusViewModel: StatusViewModel = StatusViewModel()) -> RecordingViewModel {
        RecordingViewModel(
            speechService: SpeechToTextService(),
            pasteManager: PasteManager(),
            semanticCorrectionService: SemanticCorrectionService(),
            soundManager: SoundManager(),
            statusViewModel: statusViewModel
        )
    }

    private func render(_ viewModel: RecordingViewModel) {
        let view = ContentView(viewModel: viewModel, audioRecorder: AudioEngineRecorder())
            .environmentObject(WindowCoordinator.shared)
            .environment(PermissionManager.shared)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
        host.layout()
    }

    // MARK: - Body rendering

    func testRendersDefaultState() {
        render(makeViewModel())
    }

    func testRendersWithCorrectionFailedMessage() {
        let viewModel = makeViewModel()
        viewModel.correctionFailedMessage = "Correction failed, using raw text"
        render(viewModel)
    }

    func testRendersWithSuccessState() {
        let viewModel = makeViewModel()
        viewModel.showSuccess = true
        render(viewModel)
    }

    // MARK: - Recording helper error paths

    func testRetryLastTranscriptionWithNoAudioSetsError() {
        let viewModel = makeViewModel()
        viewModel.lastAudioURL = nil
        let view = ContentView(viewModel: viewModel, audioRecorder: AudioEngineRecorder())
        view.retryLastTranscription()
        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)
    }

    func testRetryLastTranscriptionWithMissingFileSetsError() {
        let viewModel = makeViewModel()
        viewModel.lastAudioURL = URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString).wav")
        let view = ContentView(viewModel: viewModel, audioRecorder: AudioEngineRecorder())
        view.retryLastTranscription()
        XCTAssertTrue(viewModel.showError)
        XCTAssertNil(viewModel.lastAudioURL)
    }

    func testShowLastAudioFileWithNoAudioSetsError() {
        let viewModel = makeViewModel()
        viewModel.lastAudioURL = nil
        let view = ContentView(viewModel: viewModel, audioRecorder: AudioEngineRecorder())
        view.showLastAudioFile()
        XCTAssertTrue(viewModel.showError)
    }

    func testShowLastAudioFileWithMissingFileSetsError() {
        let viewModel = makeViewModel()
        viewModel.lastAudioURL = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).wav")
        let view = ContentView(viewModel: viewModel, audioRecorder: AudioEngineRecorder())
        view.showLastAudioFile()
        XCTAssertTrue(viewModel.showError)
        XCTAssertNil(viewModel.lastAudioURL)
    }

    func testIsProcessingReadOnlyForwarder() {
        let viewModel = makeViewModel()
        let view = ContentView(viewModel: viewModel, audioRecorder: AudioEngineRecorder())
        // Writing through the forwarder is discarded; VM owns the value.
        view.isProcessing = true
        XCTAssertEqual(view.isProcessing, viewModel.isProcessing)
    }
}
