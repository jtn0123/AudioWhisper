import XCTest
@testable import AudioWhisper

@MainActor
final class LivePreviewEndToEndTests: IsolatedXCTestCase {
    func testActualPreviewWhileRecordingThenFinalDelivery() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LIVE_PREVIEW_E2E"] == "1",
                          "Set RUN_LIVE_PREVIEW_E2E=1 for cached, offline Parakeet inference")
        try XCTSkipUnless(Arch.isAppleSilicon)
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "speech_sample", withExtension: "wav",
                                                     subdirectory: "Resources"))
        let python = try XCTUnwrap(ProcessInfo.processInfo.environment["LIVE_PREVIEW_PYTHON"])
        let daemon = MLDaemonManager()
        await daemon.setTestOverrides(python: URL(fileURLWithPath: python),
                                      script: ResourceLocator.pythonScriptURL(named: "ml_daemon"))
        addTeardownBlock { await daemon.shutdown() }
        let service = ParakeetService(daemon: daemon)
        let cached = await service.isModelCached(model: .v2English)
        XCTAssertTrue(cached, "The fixture must use an already cached model")
        let pcm = FileManager.default.temporaryDirectory.appendingPathComponent("preview-fixture-\(UUID()).raw")
        try RawPCMConverter.convert(input: fixture, output: pcm)
        defer { try? FileManager.default.removeItem(at: pcm) }
        let samples = try Data(contentsOf: pcm).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let audio = RecordingPreviewSnapshot(samples: samples, sampleRate: 16000)
        let preview = RebuildLivePreview(interval: .milliseconds(20)) { snapshot, model in
            try await service.transcribePreparedPCM(snapshot.writePCM(), repo: model.rawValue)
        }
        var delivered: [String] = []
        let capturedFile = FileManager.default.temporaryDirectory.appendingPathComponent("preview-capture-\(UUID()).wav")
        try FileManager.default.copyItem(at: fixture, to: capturedFile)
        defer { try? FileManager.default.removeItem(at: capturedFile) }
        AppDefaults.liveTranscriptionPreview = true
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.selectedParakeetModel = .v2English
        AppDefaults.enableSmartPaste = false
        defer {
            for key in [AppDefaults.Key.liveTranscriptionPreview, .transcriptionProvider,
                        .selectedParakeetModel, .enableSmartPaste] {
                AppDefaults.defaults.removeObject(forKey: key.rawValue)
            }
        }
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { capturedFile }, cancel: {},
            transcribe: { url, config, _ in
                let text = try await service.transcribe(
                    audioFileURL: url, pythonPath: python, model: config.parakeetModel ?? .v2English)
                return TranscriptionResult(text: text, correctionOutcome: nil)
            }, copy: { delivered.append($0) }, save: { _, _, _ in })
        services.previewSnapshot = { audio }
        let session = RebuildSession(services: services, livePreview: preview)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        let started = ContinuousClock.now
        session.toggleRecording()
        let deadline = ContinuousClock.now + .seconds(45)
        while preview.text.isEmpty && !preview.paused && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.phase, .recording)
        XCTAssertTrue(delivered.isEmpty, "An actual live draft must never reach the clipboard")
        XCTAssertTrue(preview.text.lowercased().contains("quick brown fox"), preview.message)
        print("REAL_LIVE_PREVIEW firstDraft=\(started.duration(to: .now)) transcript=\(preview.text)")
        session.finishRecording()
        while session.phase == .transcribing && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.phase, .completed, session.notice ?? "No final result")
        XCTAssertEqual(delivered.count, 1)
        XCTAssertTrue(delivered.first?.lowercased().contains("quick brown fox") == true)
        session.cancel()
    }
}
