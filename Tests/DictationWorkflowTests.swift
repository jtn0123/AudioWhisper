import XCTest
@testable import AudioWhisper

@MainActor
final class DictationWorkflowTests: IsolatedXCTestCase {
    private var settings: DictationModeSettings!
    private var modes: [SavedDictationMode] = []
    private var rules: [AppDictationRule] = []
    private var automatic = false
    private var selectedID: UUID?

    override func setUp() {
        super.setUp()
        settings = AppDefaults.currentDictationSettings
        modes = AppDefaults.savedDictationModes
        rules = AppDefaults.appDictationRules
        automatic = AppDefaults.automaticDictationModes
        selectedID = AppDefaults.selectedDictationModeID
        AppDefaults.savedDictationModes = []
        AppDefaults.appDictationRules = []
        AppDefaults.automaticDictationModes = false
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
    }

    override func tearDown() {
        AppDefaults.currentDictationSettings = settings
        AppDefaults.savedDictationModes = modes
        AppDefaults.appDictationRules = rules
        AppDefaults.automaticDictationModes = automatic
        AppDefaults.selectedDictationModeID = selectedID
        super.tearDown()
    }

    func testLegacyModesDecodeWithConservativeDefaults() throws {
        let data = try JSONEncoder().encode(settings)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "language")
        json.removeValue(forKey: "writing")
        let legacy = try JSONDecoder().decode(DictationModeSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.language, .automatic)
        XCTAssertEqual(legacy.writing, DictationWriting())
        XCTAssertEqual(legacy.provider, settings.provider)
        XCTAssertEqual(legacy.vocabulary, settings.vocabulary)
    }

    func testArchiveImportsFreshIdentitiesAndResetsContextConsent() throws {
        var configured = settings!
        configured.writing.contextSource = .clipboard
        configured.writing.instructions = "Use bullet points."
        let mode = try SavedDictationMode.make(name: "Work", settings: configured, existing: [])
        let imported = try DictationModeArchive.importing(DictationModeArchive.export([mode]), into: [mode])
        XCTAssertEqual(imported.count, 2)
        XCTAssertNotEqual(imported[1].id, mode.id)
        XCTAssertEqual(imported[1].name, "Work (imported 1)")
        XCTAssertEqual(imported[1].settings.writing.contextSource, .none)
        XCTAssertEqual(imported[1].settings.writing.instructions, configured.writing.instructions)
        XCTAssertThrowsError(try DictationModeArchive.importing(Data(repeating: 0, count: 1_048_577), into: []))
        XCTAssertThrowsError(try DictationModeArchive.importing(Data("{\"schemaVersion\":2,\"modes\":[]}".utf8), into: []))
        XCTAssertEqual(AppDefaults.savedDictationModes, [], "Import parsing must not mutate preferences")
    }

    func testRewriteAllowsFormattingButStillProtectsNumbersAndNegation() {
        let rewrite = DictationWriting(operation: .rewrite, instructions: "Use an email format.")
        let source = "Send Maria the 42 files, but do not upload them."
        let output = "Subject: Files\n\nPlease send Maria the 42 files. Do not upload them."
        XCTAssertEqual(rewrite.accepted(original: source, output: output), output)
        XCTAssertEqual(DictationWriting().accepted(original: source, output: output), source)
        XCTAssertEqual(rewrite.accepted(original: source, output: output.replacingOccurrences(of: "42", with: "43")), source)
        XCTAssertEqual(rewrite.accepted(original: source, output: output.replacingOccurrences(of: "not ", with: "")), source)
        XCTAssertEqual(LocalWhisperService.decodingOptions(prompt: nil, tokenizer: nil, language: .spanish).language, "es")
    }

    func testRulesUseExactAppAndRespectPersistentManualOverride() throws {
        let mode = try SavedDictationMode.make(name: "Email", settings: settings, existing: [])
        let rule = AppDictationRule(bundleIdentifier: "fixture.mail", appName: "Mail", modeID: mode.id)
        func resolve(_ app: String?, automatic: Bool) -> ResolvedDictationMode {
            .resolve(app: app, selection: (automatic: automatic, selectedID: nil),
                     modes: [mode], rules: [rule], fallback: settings)
        }
        XCTAssertEqual(resolve("fixture.mail", automatic: true).origin, .appRule)
        XCTAssertEqual(resolve("fixture.mail.web", automatic: true).origin, .custom)
        XCTAssertEqual(resolve("fixture.mail", automatic: false).origin, .custom)
        XCTAssertEqual(resolve(nil, automatic: true).origin, .custom)
    }

    func testContextIsReadOnceAndRetainedForRetry() async throws {
        var configured = settings!
        configured.cleanup = .localMLX
        configured.writing.contextSource = .clipboard
        AppDefaults.currentDictationSettings = configured
        var reads = 0
        var received: [TranscriptionPipelineConfig] = []
        var services = fixtureServices { config in
            received.append(config)
            if received.count == 1 { throw SpeechToTextError.noSpeechDetected }
            return TranscriptionResult(text: "Words", correctionOutcome: nil)
        }
        services.contextCapture = RebuildWritingContextCapture(selectedText: { _ in XCTFail("Wrong source"); return nil },
            clipboardText: { reads += 1; return reads == 1 ? "Project Atlas" : "Changed clipboard" })
        let session = readySession(services)
        defer { session.cancel() }
        session.toggleRecording()
        session.finishRecording()
        try await wait { session.phase == .failed }
        session.retry()
        try await wait { session.phase == .completed }
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0].context, received[1].context)
        XCTAssertEqual(received[1].context?.text, "Project Atlas")
    }

    func testAppModeChecksItsOwnModelBeforeOpeningMicrophone() async throws {
        var current = settings!
        current.provider = .local
        AppDefaults.currentDictationSettings = current
        var other = current
        other.provider = .parakeet
        let mode = try SavedDictationMode.make(name: "Unavailable", settings: other, existing: [])
        AppDefaults.savedDictationModes = [mode]
        AppDefaults.appDictationRules = [.init(bundleIdentifier: "fixture.editor", appName: "Editor", modeID: mode.id)]
        AppDefaults.automaticDictationModes = true
        var starts = 0
        var services = fixtureServices { _ in TranscriptionResult(text: "Words", correctionOutcome: nil) }
        services.start = { _ in starts += 1; return true }
        services.capturePasteDestination = {
            .init(processIdentifier: 111, bundleIdentifier: "fixture.editor", activate: { true },
                  isTerminated: { false }, foregroundPID: { 111 })
        }
        var setup = RebuildSetupServices.live
        setup.microphoneStatus = { .authorized }
        setup.runtimeReady = { _ in true }
        setup.modelInstalled = { selection in selection.provider == .local }
        setup.assetIdentity = { _ in nil }
        let session = readySession(services, setup: setup)
        defer { session.cancel() }
        session.toggleRecording()
        try await wait { session.phase == .failed }
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(session.effectiveMode?.id, mode.id)
        XCTAssertEqual(AppDefaults.currentDictationSettings, current, "Automatic rules must not rewrite global settings")
    }

    private func fixtureServices(
        transcribe: @escaping (TranscriptionPipelineConfig) throws -> TranscriptionResult
    ) -> RebuildSessionServices {
        RebuildSessionServices(start: { _ in true }, stop: { URL(fileURLWithPath: "/fixture.wav") }, cancel: {},
            transcribe: { _, config, _ in try transcribe(config) }, copy: { _ in }, save: { _, _, _ in },
            capturePasteDestination: { nil })
    }

    private func readySession(_ services: RebuildSessionServices, setup: RebuildSetupServices? = nil) -> RebuildSession {
        let session = RebuildSession(services: services, setup: setup)
        session.readiness = .init(microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        return session
    }

    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}
