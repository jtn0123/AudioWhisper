import XCTest
@testable import AudioWhisper

/// Integration tests for provider selection
@MainActor
final class ProviderSelectionIntegrationTests: IsolatedXCTestCase {
    var speechService: SpeechToTextService!
    var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()

        // Create isolated defaults
        let suiteName = "ProviderSelectionIntegrationTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!

        // Create speech service
        speechService = SpeechToTextService()
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: testDefaults.description)

        speechService = nil
        testDefaults = nil

        try await super.tearDown()
    }

    // MARK: - Provider Enum Tests

    func testAllProvidersHaveDisplayNames() {
        for provider in TranscriptionProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty, "\(provider) should have a display name")
        }
    }

    func testProviderRawValues() {
        XCTAssertEqual(TranscriptionProvider.local.rawValue, "local")
        XCTAssertEqual(TranscriptionProvider.parakeet.rawValue, "parakeet")
    }

    func testProviderCount() {
        let allProviders = TranscriptionProvider.allCases
        XCTAssertEqual(allProviders.count, 2)
        XCTAssertTrue(allProviders.contains(.local))
        XCTAssertTrue(allProviders.contains(.parakeet))
    }

    // MARK: - Model Selection Tests

    func testWhisperModelEnumeration() {
        // Verify all whisper models are accessible
        let models = WhisperModel.allCases
        XCTAssertEqual(models.count, 4)
        XCTAssertTrue(models.contains(.tiny))
        XCTAssertTrue(models.contains(.base))
        XCTAssertTrue(models.contains(.small))
        XCTAssertTrue(models.contains(.largeTurbo))
    }

    func testWhisperModelFileNames() {
        XCTAssertEqual(WhisperModel.tiny.fileName, "ggml-tiny.bin")
        XCTAssertEqual(WhisperModel.base.fileName, "ggml-base.bin")
        XCTAssertEqual(WhisperModel.small.fileName, "ggml-small.bin")
        XCTAssertEqual(WhisperModel.largeTurbo.fileName, "ggml-large-v3-turbo.bin")
    }

    func testParakeetModelEnumeration() {
        let models = ParakeetModel.allCases
        XCTAssertEqual(models.count, 3)
        XCTAssertTrue(models.contains(.tdtCtc110mEnglish))
        XCTAssertTrue(models.contains(.v2English))
        XCTAssertTrue(models.contains(.v3Multilingual))
    }
}
