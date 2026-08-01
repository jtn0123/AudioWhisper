import XCTest
@testable import AudioWhisper

@MainActor
final class DataManagerIntegrationTests: IsolatedXCTestCase {
    // Deferred(D1): DataManager reads `transcriptionHistoryEnabled` and
    // `transcriptionRetentionPeriod` from UserDefaults.standard. Once
    // DataManager accepts an injected UserDefaults, route writes through a
    // UUID-scoped suite and re-enable isolation.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    var dataManager: MockDataManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Set up mock data manager for controlled testing
        dataManager = MockDataManager()
        try dataManager.initialize()
        
        // Ensure history is enabled for tests
        AppDefaults.defaults.set(true, forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.set(RetentionPeriod.forever.rawValue, forKey: "transcriptionRetentionPeriod")
    }
    
    override func tearDown() async throws {
        // Clean up UserDefaults
        AppDefaults.defaults.removeObject(forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.removeObject(forKey: "transcriptionRetentionPeriod")
        
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

    func waitForAsyncOperation() async {
        // Small delay to ensure async operations complete
        try? await Task.sleep(for: .milliseconds(100)) // 0.1 seconds
    }
    
    // MARK: - DataManager Protocol Integration Tests
    
    func testDataManagerProtocolConformance() async throws {
        // Test that DataManager conforms to protocol correctly
        XCTAssertTrue(dataManager.isHistoryEnabled, "History should be enabled by default in tests")
        XCTAssertEqual(dataManager.retentionPeriod, .oneMonth, "Default retention should be one month")
        
        // Test that we can change settings
        dataManager.retentionPeriod = .threeMonths
        XCTAssertEqual(dataManager.retentionPeriod, .threeMonths, "Retention period should be changeable")
        
        dataManager.isHistoryEnabled = false
        XCTAssertFalse(dataManager.isHistoryEnabled, "History enabled should be changeable")
    }
    
    func testSaveTranscriptionIntegration() async throws {
        // Test full save workflow with DataManager
        let record = createSampleRecord(
            text: "DataManager integration test",
            provider: .parakeet,
            duration: 25.5,
            modelUsed: "advanced"
        )
        
        // When - Save using DataManager
        try await dataManager.saveTranscription(record)
        
        await waitForAsyncOperation()
        
        // Then - Verify record was saved
        let savedRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(savedRecords.count, 1, "Should have saved one record")
        
        let savedRecord = savedRecords[0]
        XCTAssertEqual(savedRecord.text, "DataManager integration test")
        XCTAssertEqual(savedRecord.provider, "parakeet")
        XCTAssertEqual(savedRecord.duration, 25.5)
        XCTAssertEqual(savedRecord.modelUsed, "advanced")
    }
    
    func testSaveTranscriptionWhenHistoryDisabled() async throws {
        // Given - Disable history
        dataManager.isHistoryEnabled = false
        
        let record = createSampleRecord(text: "Should not be saved")
        
        // When - Attempt to save
        try await dataManager.saveTranscription(record)
        
        await waitForAsyncOperation()
        
        // Then - Verify record was not saved
        let savedRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(savedRecords.count, 0, "No records should be saved when history is disabled")
    }
    
    func testFetchRecordsIntegration() async throws {
        // Given - Multiple records
        let records = [
            createSampleRecord(text: "First record for fetch test", provider: .local),
            createSampleRecord(text: "Second record for fetch test", provider: .local),
            createSampleRecord(text: "Third record for fetch test", provider: .parakeet)
        ]
        
        for record in records {
            try await dataManager.saveTranscription(record)
        }
        
        await waitForAsyncOperation()
        
        // When - Fetch all records
        let fetchedRecords = try await dataManager.fetchAllRecords()
        
        // Then - Verify correct order and content
        XCTAssertEqual(fetchedRecords.count, 3, "Should fetch all saved records")
        
        // Records should be sorted by date (newest first)
        XCTAssertEqual(fetchedRecords[0].text, "Third record for fetch test")
        XCTAssertEqual(fetchedRecords[1].text, "Second record for fetch test")
        XCTAssertEqual(fetchedRecords[2].text, "First record for fetch test")
    }
    
    func testSearchIntegration() async throws {
        // Given - Records with searchable content
        let records = [
            createSampleRecord(text: "Meeting about Swift development", provider: .local),
            createSampleRecord(text: "Python tutorial for beginners", provider: .parakeet),
            createSampleRecord(text: "Swift programming best practices", provider: .local),
            createSampleRecord(text: "Database design principles", provider: .parakeet)
        ]
        
        for record in records {
            try await dataManager.saveTranscription(record)
        }
        
        await waitForAsyncOperation()
        
        // Test various search scenarios
        let swiftResults = try await dataManager.fetchRecords(matching: "Swift")
        XCTAssertEqual(swiftResults.count, 2, "Should find 2 Swift-related records")

        let pythonResults = try await dataManager.fetchRecords(matching: "Python")
        XCTAssertEqual(pythonResults.count, 1, "Should find 1 Python-related record")

        let localResults = try await dataManager.fetchRecords(matching: "local")
        XCTAssertEqual(localResults.count, 2, "Should find 2 local records")
        
        let noResults = try await dataManager.fetchRecords(matching: "JavaScript")
        XCTAssertEqual(noResults.count, 0, "Should find no JavaScript records")
        
        let allResults = try await dataManager.fetchRecords(matching: "")
        XCTAssertEqual(allResults.count, 4, "Empty search should return all records")
    }
    
    func testDeleteRecordIntegration() async throws {
        // Given - Multiple records
        let records = [
            createSampleRecord(text: "Keep this record", provider: .local),
            createSampleRecord(text: "Delete this record", provider: .parakeet),
            createSampleRecord(text: "Keep this one too", provider: .local)
        ]
        
        for record in records {
            try await dataManager.saveTranscription(record)
        }
        
        await waitForAsyncOperation()
        
        var allRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(allRecords.count, 3, "Should start with 3 records")
        
        // When - Delete specific record
        let recordToDelete = allRecords.first { $0.text == "Delete this record" }!
        try await dataManager.deleteRecord(recordToDelete)
        
        await waitForAsyncOperation()
        
        // Then - Verify deletion
        allRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(allRecords.count, 2, "Should have 2 records after deletion")
        
        let remainingTexts = allRecords.map { $0.text }
        XCTAssertTrue(remainingTexts.contains("Keep this record"))
        XCTAssertTrue(remainingTexts.contains("Keep this one too"))
        XCTAssertFalse(remainingTexts.contains("Delete this record"))
    }
    
    func testDeleteAllRecordsIntegration() async throws {
        // Given - Multiple records
        let records = [
            createSampleRecord(text: "Record 1", provider: .local),
            createSampleRecord(text: "Record 2", provider: .parakeet),
            createSampleRecord(text: "Record 3", provider: .local)
        ]
        
        for record in records {
            try await dataManager.saveTranscription(record)
        }
        
        await waitForAsyncOperation()
        
        var allRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(allRecords.count, 3, "Should start with 3 records")
        
        // When - Delete all records
        try await dataManager.deleteAllRecords()
        
        await waitForAsyncOperation()
        
        // Then - Verify all deleted
        allRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(allRecords.count, 0, "Should have no records after delete all")
    }
    
    // MARK: - Retention Policy Integration Tests
    
    func testRetentionPolicyCleanup() async throws {
        // Create records with different dates
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60) // 40 days ago
        let recentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        
        let oldRecord = createSampleRecord(text: "Old record", provider: .local)
        oldRecord.date = oldDate
        
        let recentRecord = createSampleRecord(text: "Recent record", provider: .parakeet)
        recentRecord.date = recentDate
        
        try await dataManager.saveTranscription(oldRecord)
        try await dataManager.saveTranscription(recentRecord)
        
        await waitForAsyncOperation()
        
        // Set retention period to one month
        dataManager.retentionPeriod = .oneMonth
        
        // When - Perform cleanup
        try await dataManager.cleanupExpiredRecords()
        
        await waitForAsyncOperation()
        
        // Then - Verify old record was removed
        let remainingRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(remainingRecords.count, 1, "Should have 1 record after cleanup")
        XCTAssertEqual(remainingRecords[0].text, "Recent record", "Recent record should remain")
    }
    
    func testForeverRetentionPolicy() async throws {
        // Create old records
        let veryOldDate = Date().addingTimeInterval(-365 * 24 * 60 * 60) // 1 year ago
        
        let veryOldRecord = createSampleRecord(text: "Very old record", provider: .local)
        veryOldRecord.date = veryOldDate
        
        try await dataManager.saveTranscription(veryOldRecord)
        
        await waitForAsyncOperation()
        
        // Set retention period to forever
        dataManager.retentionPeriod = .forever
        
        // When - Perform cleanup
        try await dataManager.cleanupExpiredRecords()
        
        await waitForAsyncOperation()
        
        // Then - Verify record was NOT removed
        let remainingRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(remainingRecords.count, 1, "Record should be preserved with forever retention")
        XCTAssertEqual(remainingRecords[0].text, "Very old record")
    }
    
    // MARK: - Quiet Operations Integration Tests
    
    func testQuietOperationsIntegration() async {
        // Test that quiet operations don't throw but still work
        let record = createSampleRecord(text: "Quiet operation test", provider: .local)
        
        // Test quiet save
        await dataManager.saveTranscriptionQuietly(record)
        
        await waitForAsyncOperation()
        
        // Test quiet fetch
        let savedRecords = await dataManager.fetchAllRecordsQuietly()
        XCTAssertEqual(savedRecords.count, 1, "Quiet save should work")
        XCTAssertEqual(savedRecords[0].text, "Quiet operation test")
        
        // Test quiet cleanup
        await dataManager.cleanupExpiredRecordsQuietly()
        
        // Should still have the record (no cleanup needed)
        let afterCleanup = await dataManager.fetchAllRecordsQuietly()
        XCTAssertEqual(afterCleanup.count, 1, "Quiet cleanup should work")
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testDataManagerErrorHandling() async {
        // Test error scenarios with real error types
        let errors: [DataManagerError] = [
            .initializationFailed(NSError(domain: "test", code: 1)),
            .saveFailed(NSError(domain: "test", code: 2)),
            .fetchFailed(NSError(domain: "test", code: 3)),
            .deleteFailed(NSError(domain: "test", code: 4)),
            .cleanupFailed(NSError(domain: "test", code: 5)),
            .modelContainerUnavailable
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
        
        // Test specific error descriptions
        let initError = DataManagerError.initializationFailed(NSError(domain: "test", code: 1))
        XCTAssertTrue(initError.errorDescription!.contains("Failed to initialize"), "Init error should mention initialization")
        
        let containerError = DataManagerError.modelContainerUnavailable
        XCTAssertEqual(containerError.errorDescription, "Data storage is not available")
    }
    
}
