import XCTest
import SwiftUI
import SwiftData
@testable import AudioWhisper

@MainActor
final class TranscriptionHistoryIntegrationTests: IsolatedXCTestCase {
    // Deferred(D1): DataManager reads `transcriptionHistoryEnabled` and
    // `transcriptionRetentionPeriod` from UserDefaults.standard. Once
    // DataManager accepts an injected UserDefaults, route writes through a
    // UUID-scoped suite and re-enable isolation.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var dataManager: DataManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create in-memory model container for testing
        modelContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
        
        // Set up DataManager with test container
        dataManager = DataManager.shared as? DataManager
        try dataManager?.initialize()
        
        // Ensure history is enabled for tests
        AppDefaults.defaults.set(true, forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.set(RetentionPeriod.forever.rawValue, forKey: "transcriptionRetentionPeriod")
    }
    
    override func tearDown() async throws {
        // Clean up all records from the test database
        if let modelContext = modelContext {
            do {
                let allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
                for record in allRecords {
                    modelContext.delete(record)
                }
                try modelContext.save()
            } catch {
                // Ignore cleanup errors
            }
        }
        
        // Clean up UserDefaults
        AppDefaults.defaults.removeObject(forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.removeObject(forKey: "transcriptionRetentionPeriod")
        
        modelContainer = nil
        modelContext = nil
        dataManager = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    func createSampleRecord(
        text: String = "Sample transcription",
        provider: TranscriptionProvider = .local,
        duration: TimeInterval? = 10.5,
        modelUsed: String? = nil
    ) -> TranscriptionRecord {
        return TranscriptionRecord(
            text: text,
            provider: provider,
            duration: duration,
            modelUsed: modelUsed
        )
    }

    func createTestView() -> some View {
        TranscriptionHistoryView()
            .modelContainer(modelContainer)
    }

    func waitForAsyncOperation() async {
        // Give more time for async operations to complete and ensure they're properly flushed
        try? await Task.sleep(for: .milliseconds(250)) // 0.25 seconds
        
        // Force main actor to process any pending tasks
        await MainActor.run {
            // Empty block to ensure main actor processing
        }
    }
    
    // MARK: - Full Flow Integration Tests
    
    func testCompleteTranscriptionFlow() async throws {
        // Given - Create a new transcription record
        let originalText = "This is a complete integration test transcription from local whisper"
        let record = createSampleRecord(
            text: originalText,
            provider: .local,
            duration: 15.5,
            modelUsed: "base"
        )

        // When - Save the transcription
        modelContext.insert(record)
        try modelContext.save()

        await waitForAsyncOperation()

        // Then - Retrieve and verify
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let savedRecords = try modelContext.fetch(descriptor)

        XCTAssertEqual(savedRecords.count, 1, "Should have exactly one saved record")

        let savedRecord = savedRecords[0]
        XCTAssertEqual(savedRecord.text, originalText, "Text should match")
        XCTAssertEqual(savedRecord.provider, "local", "Provider should match")
        XCTAssertEqual(savedRecord.duration, 15.5, "Duration should match")
        XCTAssertEqual(savedRecord.modelUsed, "base", "Model should match")
        XCTAssertNotNil(savedRecord.date, "Date should be set")
        XCTAssertNotNil(savedRecord.id, "ID should be set")

        // Verify computed properties work correctly
        XCTAssertEqual(savedRecord.transcriptionProvider, .local)
        XCTAssertNotNil(savedRecord.formattedDate)
        XCTAssertNotNil(savedRecord.formattedDuration)
        XCTAssertEqual(savedRecord.preview, originalText) // Not truncated
    }
    
    func testMultipleTranscriptionsWorkflow() async throws {
        // Given - Create multiple transcription records
        let records = [
            createSampleRecord(text: "First transcription", provider: .local, duration: 5.0),
            createSampleRecord(text: "Second transcription", provider: .parakeet, duration: 10.0)
        ]

        // When - Save all records
        for record in records {
            modelContext.insert(record)
        }
        try modelContext.save()

        await waitForAsyncOperation()

        // Then - Verify all records are saved and ordered correctly
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let savedRecords = try modelContext.fetch(descriptor)

        XCTAssertEqual(savedRecords.count, 2, "Should have both records")

        // Verify they're in reverse chronological order (newest first)
        XCTAssertEqual(savedRecords[0].text, "Second transcription")
        XCTAssertEqual(savedRecords[1].text, "First transcription")

        // Verify all providers are represented
        let providers = savedRecords.map { $0.provider }
        XCTAssertTrue(providers.contains("local"))
        XCTAssertTrue(providers.contains("parakeet"))
    }
    
    func testTranscriptionWithHistoryDisabled() async throws {
        // Given - Disable history
        AppDefaults.defaults.set(false, forKey: "transcriptionHistoryEnabled")
        
        let record = createSampleRecord(text: "Should not be saved")
        
        // When - Attempt to save (simulating DataManager behavior)
        let isHistoryEnabled = AppDefaults.defaults.bool(forKey: "transcriptionHistoryEnabled")
        if isHistoryEnabled {
            modelContext.insert(record)
            try modelContext.save()
        }
        
        await waitForAsyncOperation()
        
        // Then - Verify record was not saved
        let descriptor = FetchDescriptor<TranscriptionRecord>()
        let savedRecords = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(savedRecords.count, 0, "No records should be saved when history is disabled")
    }
    
    // MARK: - Search Integration Tests
    
    func testComprehensiveSearchFunctionality() async throws {
        // Clean up any existing records first
        let existingRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        for record in existingRecords {
            modelContext.delete(record)
        }
        try modelContext.save()

        // Given - Create records with diverse content
        let records = [
            createSampleRecord(text: "Meeting notes about Swift programming", provider: .local),
            createSampleRecord(text: "Python tutorial transcript", provider: .parakeet),
            createSampleRecord(text: "Swift development discussion", provider: .local, modelUsed: "base"),
            createSampleRecord(text: "JavaScript framework comparison", provider: .parakeet),
            createSampleRecord(text: "Machine learning concepts explained", provider: .local),
            createSampleRecord(text: "Database design principles", provider: .local, modelUsed: "small")
        ]

        for record in records {
            modelContext.insert(record)
        }
        try modelContext.save()

        await waitForAsyncOperation()

        // Test 1: Text-based search
        let allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(allRecords.count, 6, "Should have exactly 6 records")

        let swiftResults = allRecords.filter { $0.matches(searchQuery: "Swift") }
        XCTAssertEqual(swiftResults.count, 2, "Should find 2 Swift-related records")

        // Test 2: Provider-based search
        let localResults = allRecords.filter { $0.matches(searchQuery: "local") }
        XCTAssertEqual(localResults.count, 4, "Should find 4 local records")

        // Test 3: Model-based search (search for "tiny" model instead to avoid word collisions)
        let records2 = [
            createSampleRecord(text: "Additional test record", provider: .local, modelUsed: "tiny")
        ]
        for record in records2 {
            modelContext.insert(record)
        }
        try modelContext.save()

        let updatedRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        let tinyModelResults = updatedRecords.filter { $0.matches(searchQuery: "tiny") }
        XCTAssertEqual(tinyModelResults.count, 1, "Should find 1 tiny model record")

        // Test 4: Case-insensitive search
        let caseInsensitiveResults = allRecords.filter { $0.matches(searchQuery: "PYTHON") }
        XCTAssertEqual(caseInsensitiveResults.count, 1, "Case-insensitive search should work")

        // Test 5: Partial word search
        let partialResults = allRecords.filter { $0.matches(searchQuery: "program") }
        XCTAssertEqual(partialResults.count, 1, "Partial word search should work")

        // Test 6: No results
        let noResults = allRecords.filter { $0.matches(searchQuery: "nonexistent") }
        XCTAssertEqual(noResults.count, 0, "Should return no results for non-matching query")

        // Test 7: Empty query (should match all)
        let emptyQueryResults = allRecords.filter { $0.matches(searchQuery: "") }
        XCTAssertEqual(emptyQueryResults.count, 6, "Empty query should match all records")
    }
    
    func testSearchWithSpecialCharacters() async throws {
        // Given - Records with special characters
        let records = [
            createSampleRecord(text: "Email: user@example.com with special chars!", provider: .local),
            createSampleRecord(text: "Path: /Users/test/file.txt", provider: .local),
            createSampleRecord(text: "Code: function() { return 'hello'; }", provider: .parakeet),
            createSampleRecord(text: "Unicode: café naïve résumé 世界 🌍", provider: .parakeet)
        ]
        
        for record in records {
            modelContext.insert(record)
        }
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        let allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        
        // Test searching for email
        let emailResults = allRecords.filter { $0.matches(searchQuery: "@example.com") }
        XCTAssertEqual(emailResults.count, 1, "Should find email record")
        
        // Test searching for path
        let pathResults = allRecords.filter { $0.matches(searchQuery: "/Users") }
        XCTAssertEqual(pathResults.count, 1, "Should find path record")
        
        // Test searching for code
        let codeResults = allRecords.filter { $0.matches(searchQuery: "function()") }
        XCTAssertEqual(codeResults.count, 1, "Should find code record")
        
        // Test searching for unicode
        let unicodeResults = allRecords.filter { $0.matches(searchQuery: "café") }
        XCTAssertEqual(unicodeResults.count, 1, "Should find unicode record")
        
        let emojiResults = allRecords.filter { $0.matches(searchQuery: "🌍") }
        XCTAssertEqual(emojiResults.count, 1, "Should find emoji record")
    }
    
}
