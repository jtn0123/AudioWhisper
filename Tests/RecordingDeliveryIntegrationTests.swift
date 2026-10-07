import AppKit
import SwiftData
import XCTest
@testable import AudioWhisper

@MainActor
final class RecordingDeliveryIntegrationTests: IsolatedXCTestCase {
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    func testRecordingCorrectsAndDeliversToRealIsolatedClipboardAndHistory() async throws {
        try await verifyDelivery(correctionFails: false)
    }

    func testCorrectionFailureStillDeliversRawTranscriptAndShowsWarning() async throws {
        try await verifyDelivery(correctionFails: true)
    }

    private func verifyDelivery(correctionFails: Bool) async throws {
        try XCTSkipUnless(Arch.isAppleSilicon)
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        AppDefaults.semanticCorrectionMode = .localMLX
        AppDefaults.enableSmartPaste = false
        AppDefaults.defaults.set(true, forKey: "transcriptionHistoryEnabled")
        let container = try ModelContainer(for: TranscriptionRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let history = DataManager(modelContainer: container)
        let clipboard = NSPasteboard(name: NSPasteboard.Name("delivery-\(UUID())"))
        defer { clipboard.releaseGlobally() }
        let daemon = DeliveryCorrectionDaemon(fails: correctionFails)
        let correction = SemanticCorrectionService(
            mlxService: MLXCorrectionService(daemon: daemon),
            preparePython: { URL(fileURLWithPath: "/unused-test-interpreter") }
        )
        let speech = StubSpeechToTextServiceForFlow()
        speech.result = .success("hello world")
        let coordinator = TranscriptionCoordinator(
            pipeline: TranscriptionPipeline(speechService: speech, correctionService: correction),
            delivery: TranscriptionDelivery(
                copyText: { clipboard.clearContents(); clipboard.setString($0, forType: .string) },
                historyEnabled: { true }, saveRecord: { await history.saveTranscriptionQuietly($0) }
            )
        )
        let vm = RecordingViewModel(speechService: speech, pasteManager: PasteManager(),
                                    semanticCorrectionService: correction, soundManager: SoundManager(),
                                    statusViewModel: StatusViewModel(), coordinator: coordinator)
        let recorder = MockAudioEngineRecorder()
        recorder.simulatedRecordingDuration = 2.4
        recorder.stopRecordingResult = try XCTUnwrap(Bundle.module.url(forResource: "speech_sample",
                                                                       withExtension: "wav", subdirectory: "Resources"))
        vm.stopAndProcess(audioRecorder: recorder, hasShownFirstModelUseHint: true,
                          setHintShown: {}, presentDashboard: { _ in XCTFail("unexpected setup redirect") })
        await vm.processingTask?.value
        let expected = correctionFails ? "hello world" : "Hello world."
        XCTAssertEqual(clipboard.string(forType: .string), expected)
        let records = await history.fetchAllRecordsQuietly()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, expected)
        XCTAssertEqual(records.first?.provider, TranscriptionProvider.local.rawValue)
        XCTAssertEqual(records.first?.modelUsed, WhisperModel.base.rawValue)
        XCTAssertEqual(records.first?.duration, 2.4)
        XCTAssertEqual(vm.completedAudioDuration, 2.4)
        XCTAssertTrue(vm.showSuccess)
        XCTAssertFalse(vm.isProcessing)
        XCTAssertEqual(vm.correctionFailedMessage != nil, correctionFails)
    }
}

private final class DeliveryCorrectionDaemon: MLDaemonManaging {
    let fails: Bool
    init(fails: Bool) { self.fails = fails }
    func correct(repo: String, text: String, prompt: String?) async throws -> String {
        if fails { throw MLDaemonError.remoteError("fixture correction failed") }
        return "Hello world."
    }
    func ping() async -> Bool { true }
}
