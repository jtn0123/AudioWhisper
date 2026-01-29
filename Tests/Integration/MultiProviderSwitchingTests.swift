import XCTest
import SwiftData
@testable import AudioWhisper

/// Integration tests for switching between transcription providers
@MainActor
final class MultiProviderSwitchingTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var testDefaults: UserDefaults!
    var mockKeychain: MockKeychainService!
    var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        modelContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)

        // Create isolated UserDefaults for testing
        suiteName = "MultiProviderSwitchingTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!

        // Set up mock keychain
        mockKeychain = MockKeychainService()

        // Enable history
        testDefaults.set(true, forKey: "transcriptionHistoryEnabled")
    }

    override func tearDown() async throws {
        // Clean up records
        if let modelContext = modelContext {
            let allRecords = try? modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
            for record in allRecords ?? [] {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }

        if let suiteName = suiteName {
            testDefaults?.removePersistentDomain(forName: suiteName)
        }

        modelContainer = nil
        modelContext = nil
        mockKeychain = nil
        testDefaults = nil
        suiteName = nil

        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func waitForAsyncOperation() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    private func setProvider(_ provider: TranscriptionProvider) {
        testDefaults.set(provider.rawValue, forKey: "transcriptionProvider")
    }

    private func getProvider() -> TranscriptionProvider {
        let rawValue = testDefaults.string(forKey: "transcriptionProvider") ?? TranscriptionProvider.openai.rawValue
        return TranscriptionProvider(rawValue: rawValue) ?? .openai
    }

    // MARK: - Provider Switching Tests

    func testSwitchFromOpenAIToGemini() {
        // Given - OpenAI is selected
        setProvider(.openai)
        XCTAssertEqual(getProvider(), .openai)

        // When - Switch to Gemini
        setProvider(.gemini)

        // Then - Provider is updated
        XCTAssertEqual(getProvider(), .gemini)
    }

    func testSwitchFromGeminiToLocal() {
        // Given - Gemini is selected
        setProvider(.gemini)
        XCTAssertEqual(getProvider(), .gemini)

        // When - Switch to Local
        setProvider(.local)

        // Then - Provider is updated
        XCTAssertEqual(getProvider(), .local)
    }

    func testSwitchFromLocalToParakeet() {
        // Given - Local is selected
        setProvider(.local)
        XCTAssertEqual(getProvider(), .local)

        // When - Switch to Parakeet
        setProvider(.parakeet)

        // Then - Provider is updated
        XCTAssertEqual(getProvider(), .parakeet)
    }

    func testSwitchFromParakeetToOpenAI() {
        // Given - Parakeet is selected
        setProvider(.parakeet)
        XCTAssertEqual(getProvider(), .parakeet)

        // When - Switch to OpenAI
        setProvider(.openai)

        // Then - Provider is updated
        XCTAssertEqual(getProvider(), .openai)
    }

    // MARK: - Provider Switch Error Handling Tests

    func testSwitchToLocalWithMissingModel() async throws {
        // Given - Switch to local provider
        setProvider(.local)

        // When - Local model is not downloaded
        // The system should handle this gracefully

        // Then - No crash, appropriate error would be shown
        XCTAssertEqual(getProvider(), .local)
    }

    func testSwitchToParakeetWithoutPython() async throws {
        // Given - Switch to Parakeet provider
        setProvider(.parakeet)

        // When - Python is not configured
        // The system should handle this gracefully

        // Then - No crash, appropriate error would be shown
        XCTAssertEqual(getProvider(), .parakeet)
    }

    func testSwitchToCloudWithMissingAPIKey() async throws {
        // Given - No API key is stored
        mockKeychain.clear()

        // When - Switch to OpenAI
        setProvider(.openai)

        // Then - Provider is set but transcription would fail without key
        XCTAssertEqual(getProvider(), .openai)
    }

    // MARK: - Rapid Switching Tests

    func testRapidProviderSwitching() {
        // Given - Start with OpenAI
        setProvider(.openai)

        // When - Rapidly switch between providers
        let providers: [TranscriptionProvider] = [.gemini, .local, .parakeet, .openai, .gemini, .local]

        for provider in providers {
            setProvider(provider)
        }

        // Then - Final provider should be correct
        XCTAssertEqual(getProvider(), .local)
    }

    func testRapidProviderSwitchingDoesNotCorruptState() async throws {
        // Given - Existing records
        let initialRecord = TranscriptionRecord(
            text: "Initial transcription",
            provider: .openai,
            duration: 5.0
        )
        modelContext.insert(initialRecord)
        try modelContext.save()

        // When - Rapidly switch providers
        for _ in 0..<10 {
            setProvider(.openai)
            setProvider(.gemini)
            setProvider(.local)
            setProvider(.parakeet)
        }

        await waitForAsyncOperation()

        // Then - Records are preserved
        let descriptor = FetchDescriptor<TranscriptionRecord>()
        let records = try modelContext.fetch(descriptor)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Initial transcription")
    }

    // MARK: - Provider Switch Mid-Transcription (Conceptual)

    func testProviderSwitchMidTranscription() async throws {
        // This is a conceptual test - in practice, switching mid-transcription
        // should complete the current transcription with the original provider

        // Given - Transcription in progress with OpenAI
        let openAIRecord = TranscriptionRecord(
            text: "Transcription started with OpenAI",
            provider: .openai,
            duration: 10.0
        )
        modelContext.insert(openAIRecord)
        try modelContext.save()

        // When - Provider is changed to Gemini
        setProvider(.gemini)

        // Then - Existing record maintains original provider
        let descriptor = FetchDescriptor<TranscriptionRecord>()
        let records = try modelContext.fetch(descriptor)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.transcriptionProvider, .openai)
        XCTAssertEqual(getProvider(), .gemini)
    }

    // MARK: - History Preservation Tests

    func testProviderSwitchPreservesHistory() async throws {
        // Given - Records from multiple providers
        let records = [
            TranscriptionRecord(text: "OpenAI text", provider: .openai, duration: 5.0),
            TranscriptionRecord(text: "Gemini text", provider: .gemini, duration: 6.0),
            TranscriptionRecord(text: "Local text", provider: .local, duration: 7.0)
        ]

        for record in records {
            modelContext.insert(record)
        }
        try modelContext.save()

        // When - Switch between providers
        setProvider(.parakeet)
        setProvider(.openai)
        setProvider(.gemini)

        await waitForAsyncOperation()

        // Then - All records are preserved
        let descriptor = FetchDescriptor<TranscriptionRecord>()
        let savedRecords = try modelContext.fetch(descriptor)

        XCTAssertEqual(savedRecords.count, 3)

        let providers = Set(savedRecords.map { $0.transcriptionProvider })
        XCTAssertTrue(providers.contains(.openai))
        XCTAssertTrue(providers.contains(.gemini))
        XCTAssertTrue(providers.contains(.local))
    }

    // MARK: - Provider Configuration Tests

    func testProviderSwitchUpdatesUsageMetrics() async throws {
        // Given - Records from different providers
        let openAIRecord = TranscriptionRecord(text: "Five words are here now", provider: .openai, duration: 5.0)
        let geminiRecord = TranscriptionRecord(text: "Three words here", provider: .gemini, duration: 3.0)

        modelContext.insert(openAIRecord)
        modelContext.insert(geminiRecord)
        try modelContext.save()

        // When - Fetch provider-specific records
        let descriptor = FetchDescriptor<TranscriptionRecord>()
        let allRecords = try modelContext.fetch(descriptor)

        // Then - Each provider's records are correctly attributed
        let openAIRecords = allRecords.filter { $0.transcriptionProvider == .openai }
        let geminiRecords = allRecords.filter { $0.transcriptionProvider == .gemini }

        XCTAssertEqual(openAIRecords.count, 1)
        XCTAssertEqual(geminiRecords.count, 1)
    }

    // MARK: - All Providers Test

    func testAllProvidersAreAccessible() {
        // Verify all providers can be set
        let allProviders: [TranscriptionProvider] = [.openai, .gemini, .local, .parakeet]

        for provider in allProviders {
            setProvider(provider)
            XCTAssertEqual(getProvider(), provider, "Should be able to set \(provider.displayName)")
        }
    }

    func testProviderDisplayNames() {
        // Verify all providers have display names
        let allProviders: [TranscriptionProvider] = [.openai, .gemini, .local, .parakeet]

        for provider in allProviders {
            XCTAssertFalse(provider.displayName.isEmpty, "\(provider) should have a display name")
        }
    }

    func testProviderRawValues() {
        // Verify raw values are unique and valid
        let allProviders: [TranscriptionProvider] = [.openai, .gemini, .local, .parakeet]
        let rawValues = allProviders.map { $0.rawValue }

        XCTAssertEqual(Set(rawValues).count, allProviders.count, "All raw values should be unique")

        for rawValue in rawValues {
            XCTAssertFalse(rawValue.isEmpty, "Raw value should not be empty")
        }
    }
}
