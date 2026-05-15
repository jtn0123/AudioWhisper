import XCTest
@testable import AudioWhisper

/// Coverage tests for `LocalWhisperService` static helpers, `LocalWhisperError`
/// descriptions, and transcription guards that don't require a real model.
final class LocalWhisperServiceCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): safeSelectedWhisperModel reads `selectedWhisperModel` from
    // AppDefaults, which is backed by UserDefaults.standard.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    // MARK: - Static configuration

    func testDefaultModelIsBase() {
        XCTAssertEqual(LocalWhisperService.defaultModel, .base)
    }

    func testSafeSelectedWhisperModelReturnsValidEnum() {
        let model = LocalWhisperService.safeSelectedWhisperModel
        XCTAssertTrue(WhisperModel.allCases.contains(model))
    }

    func testSharedInstanceIsStable() {
        XCTAssertTrue(LocalWhisperService.shared === LocalWhisperService.shared)
    }

    // MARK: - LocalWhisperError descriptions

    func testModelNotDownloadedDescription() {
        let desc = LocalWhisperError.modelNotDownloaded.errorDescription
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("model"))
    }

    func testInvalidAudioFileDescription() {
        XCTAssertEqual(LocalWhisperError.invalidAudioFile.errorDescription, "Invalid audio file format")
    }

    func testBufferAllocationFailedDescription() {
        XCTAssertEqual(
            LocalWhisperError.bufferAllocationFailed.errorDescription,
            "Failed to allocate audio buffer"
        )
    }

    func testNoChannelDataDescription() {
        XCTAssertEqual(LocalWhisperError.noChannelData.errorDescription, "No audio channel data found")
    }

    func testResamplingFailedDescription() {
        XCTAssertEqual(LocalWhisperError.resamplingFailed.errorDescription, "Failed to resample audio")
    }

    func testTranscriptionFailedDescription() {
        XCTAssertEqual(LocalWhisperError.transcriptionFailed.errorDescription, "Transcription failed")
    }

    func testModelNotDownloadedEquatable() {
        XCTAssertEqual(LocalWhisperError.modelNotDownloaded, LocalWhisperError.modelNotDownloaded)
    }

    // MARK: - transcribe guard (model not downloaded)

    func testTranscribeThrowsWhenModelNotDownloaded() async {
        // A model that isn't downloaded in CI should throw modelNotDownloaded
        // from the cache's pre-flight check before any WhisperKit init.
        let service = LocalWhisperService()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lw_cov_\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0, count: 64))
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await service.transcribe(audioFileURL: url, model: .largeTurbo)
            // If a model happens to be present locally the call may proceed
            // and fail later; either way it must throw.
            XCTFail("Expected transcription to throw without a usable model")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testClearCacheDoesNotCrash() async {
        let service = LocalWhisperService()
        await service.clearCache()
    }
}
