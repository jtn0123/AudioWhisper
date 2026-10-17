import XCTest
@testable import AudioWhisper

@MainActor
final class DictationTimingEndToEndTests: IsolatedXCTestCase {
    func testCachedParakeetColdAndWarmPipelineDelivery() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_DICTATION_TIMING"] == "1",
                          "Opt in to cached, offline model timing")
        let python = try XCTUnwrap(ProcessInfo.processInfo.environment["LIVE_PREVIEW_PYTHON"])
        let output = try XCTUnwrap(ProcessInfo.processInfo.environment["DICTATION_TIMING_OUTPUT"])
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "speech_sample", withExtension: "wav",
                                                     subdirectory: "Resources"))
        let daemon = MLDaemonManager()
        await daemon.setTestOverrides(python: URL(fileURLWithPath: python),
                                      script: ResourceLocator.pythonScriptURL(named: "ml_daemon"))
        addTeardownBlock { await daemon.shutdown() }
        let parakeet = ParakeetService(daemon: daemon)
        let cached = await parakeet.isModelCached(model: .v2English)
        XCTAssertTrue(cached, "No model downloads are permitted in this benchmark")
        let speech = SpeechToTextService(parakeetService: parakeet, preparePython: { URL(fileURLWithPath: python) })
        let pipeline = TranscriptionPipeline(speechService: speech)
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.selectedParakeetModel = .v2English
        AppDefaults.semanticCorrectionMode = .off
        AppDefaults.transcriptionHistoryEnabled = false
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        var copied: [String] = []
        var services = RebuildSessionServices.live(recorder: AudioEngineRecorder(), pipeline: pipeline,
            copy: { copied.append($0) }, history: MockDataManager(), usage: UsageMetricsStore(defaults: AppDefaults.defaults))
        services.capturePasteDestination = { nil }
        let session = RebuildSession(services: services)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        var measurements: [[String: Any]] = []
        for name in ["cold", "warm-1", "warm-2"] {
            session.importAudio(fixture)
            let deadline = ContinuousClock.now + .seconds(60)
            while session.timing.delivered == nil, session.phase != .failed, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            await session.waitForHistoryWrites()
            XCTAssertEqual(session.phase, .completed, session.notice ?? "No final result")
            let words = session.transcript.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
            XCTAssertEqual(words, "the quick brown fox jumps over the lazy dog")
            measurements.append(["run": name, "processing_ms": try XCTUnwrap(session.timing.processingMilliseconds),
                                 "delivery_ms": try XCTUnwrap(session.timing.deliveryMilliseconds)])
        }
        XCTAssertEqual(copied.count, 3)
        let report: [String: Any] = ["model": ParakeetModel.v2English.rawValue, "measurements": measurements,
            "fixture": "speech_sample.wav", "cleanup": "off", "history": "off",
            "scope": "Real pipeline, cached offline model, file validation/conversion and clipboard callback",
            "not_measured": ["physical microphone", "hotkey dispatch", "external app paste", "writing cleanup"]]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output))
        session.cancel()
    }
}
