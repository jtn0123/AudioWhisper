import AVFoundation
import XCTest
@testable import AudioWhisper

@MainActor
private final class VerificationFixture {
    var selection = RebuildModelSelection(provider: .local, whisper: .base, parakeet: .v3Multilingual)
    var identity = "assets-v1"
    var result = ModelVerificationResult(succeeded: false, message: "Verification failed: weights cannot load")
    var verifyOperation: (() async throws -> ModelVerificationResult)?
    var starts = 0
    var copies = 0
    let suite = "com.audiowhisper.verification-test.\(UUID())"
    lazy var preferences = UserDefaults(suiteName: suite)!

    func makeSession() -> RebuildSession {
        RebuildSession(
            services: RebuildSessionServices(
                start: { _ in self.starts += 1; return true }, stop: { nil }, cancel: {},
                transcribe: { _, _, _ in TranscriptionResult(text: "fixture", correctionOutcome: nil) },
                copy: { _ in self.copies += 1 }, save: { _, _, _ in }),
            setup: RebuildSetupServices(
                selection: { self.selection }, microphoneStatus: { .authorized },
                requestMicrophone: { _ in }, openMicrophoneSettings: {},
                runtimeReady: { _ in true }, modelInstalled: { _ in true }, install: { _ in },
                verify: { _ in
                    if let operation = self.verifyOperation { return try await operation() }
                    return self.result
                }, assetIdentity: { _ in self.identity }),
            verificationDefaults: preferences)
    }

    func cleanUp() { preferences.removePersistentDomain(forName: suite) }
}

@MainActor
final class RebuildModelVerificationTests: IsolatedXCTestCase {
    private var fixture: VerificationFixture!

    override func setUp() {
        super.setUp()
        fixture = VerificationFixture()
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
    }

    override func tearDown() {
        fixture.cleanUp()
        fixture = nil
        super.tearDown()
    }

    func testFailedLoadBlocksRecordingAndFileImportDespitePresentAssets() async {
        let session = fixture.makeSession()
        await session.refreshSetup()
        XCTAssertTrue(session.readiness.ready)
        await session.verifyVoiceModel()
        XCTAssertFalse(session.readiness.ready)
        XCTAssertEqual(session.verificationMessage, fixture.result.message)
        session.importAudio(URL(fileURLWithPath: "/tmp/fixture.wav"))
        for _ in 0..<20 { await Task.yield() }
        session.toggleRecording()
        XCTAssertEqual(fixture.starts, 0)
        XCTAssertEqual(fixture.copies, 0)
    }

    func testFailedVerificationSurvivesRefreshAndSessionRecreation() async {
        let session = fixture.makeSession()
        await session.verifyVoiceModel()
        await session.refreshSetup()
        XCTAssertFalse(session.readiness.ready)
        let reopened = fixture.makeSession()
        await reopened.refreshSetup()
        XCTAssertFalse(reopened.readiness.ready)
    }

    func testSuccessfulReverificationClearsFailureForSameAssets() async {
        let session = fixture.makeSession()
        await session.verifyVoiceModel()
        fixture.result = ModelVerificationResult(succeeded: true, message: "Loaded successfully")
        await session.verifyVoiceModel()
        XCTAssertTrue(session.readiness.ready)
        let reopened = fixture.makeSession()
        await reopened.refreshSetup()
        XCTAssertTrue(reopened.readiness.ready)
    }

    func testAssetReplacementInvalidatesTheOldFailure() async {
        let session = fixture.makeSession()
        await session.verifyVoiceModel()
        fixture.identity = "repaired-assets-v2"
        await session.refreshSetup()
        XCTAssertTrue(session.readiness.ready)
        XCTAssertNil(session.verificationMessage)
    }

    func testCheckingInstallationDoesNotEraseKnownFailure() async {
        let session = fixture.makeSession()
        await session.verifyVoiceModel()
        await session.installVoiceModel() // Existing unchanged assets are still unusable.
        XCTAssertFalse(session.readiness.ready)
    }

    func testLateVerificationCannotPoisonADifferentSelection() async throws {
        var pending: CheckedContinuation<ModelVerificationResult, Never>?
        fixture.verifyOperation = { await withCheckedContinuation { pending = $0 } }
        let session = fixture.makeSession()
        let verification = Task { await session.verifyVoiceModel() }
        for _ in 0..<20 { await Task.yield() }
        fixture.selection = RebuildModelSelection(provider: .local, whisper: .tiny, parakeet: .v3Multilingual)
        session.selectionChanged()
        try XCTUnwrap(pending).resume(returning: fixture.result)
        await verification.value
        XCTAssertTrue(session.readiness.ready)
        XCTAssertNil(session.verificationMessage)
    }

    func testThrownLoadErrorBlocksReadinessAndReleasesMaintenance() async {
        fixture.verifyOperation = { throw NSError(domain: "fixture", code: 1) }
        let session = fixture.makeSession()
        await session.verifyVoiceModel()
        XCTAssertFalse(session.readiness.ready)
        XCTAssertFalse(session.maintenanceInProgress)
        XCTAssertFalse(session.isVerifyingVoiceModel)
    }

    func testFingerprintTracksChangedContentsAndMissingAssets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("model-identity-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(RebuildModelAssetIdentity.fingerprint(at: root))
        let file = root.appendingPathComponent("weights.bin")
        try Data("before".utf8).write(to: file)
        let old = try XCTUnwrap(RebuildModelAssetIdentity.fingerprint(at: root))
        try Data("after with a different size".utf8).write(to: file)
        XCTAssertNotEqual(old, RebuildModelAssetIdentity.fingerprint(at: root))
    }
}
