import XCTest
import SwiftUI
import SwiftData
@testable import AudioWhisper

// Settings / UI-component / data-validation / error-scenario integration tests, split
// out of TranscriptionHistoryIntegrationTests for SwiftLint body-length limits.
@MainActor
extension TranscriptionHistoryIntegrationTests {
    // MARK: - Settings Integration Tests
    
    func testHistoryEnabledSetting() async throws {
        // Test enabling history
        AppDefaults.defaults.set(true, forKey: "transcriptionHistoryEnabled")
        let isEnabled = AppDefaults.defaults.bool(forKey: "transcriptionHistoryEnabled")
        XCTAssertTrue(isEnabled, "History should be enabled")
        
        // Test disabling history
        AppDefaults.defaults.set(false, forKey: "transcriptionHistoryEnabled")
        let isDisabled = AppDefaults.defaults.bool(forKey: "transcriptionHistoryEnabled")
        XCTAssertFalse(isDisabled, "History should be disabled")
    }
    
    func testRetentionPeriodSettings() async throws {
        // Test all retention periods
        for period in RetentionPeriod.allCases {
            AppDefaults.defaults.set(period.rawValue, forKey: "transcriptionRetentionPeriod")
            
            let storedValue = AppDefaults.defaults.string(forKey: "transcriptionRetentionPeriod")
            XCTAssertEqual(storedValue, period.rawValue, "Retention period should be stored correctly")
            
            let retrievedPeriod = RetentionPeriod(rawValue: storedValue!) ?? .oneMonth
            XCTAssertEqual(retrievedPeriod, period, "Retention period should be retrieved correctly")
        }
    }
    
    func testRetentionPeriodTimeIntervals() {
        // Test that time intervals are calculated correctly
        XCTAssertEqual(RetentionPeriod.oneWeek.timeInterval, 7 * 24 * 60 * 60)
        XCTAssertEqual(RetentionPeriod.oneMonth.timeInterval, 30 * 24 * 60 * 60)
        XCTAssertEqual(RetentionPeriod.threeMonths.timeInterval, 90 * 24 * 60 * 60)
        XCTAssertNil(RetentionPeriod.forever.timeInterval)
        
        // Test display names
        XCTAssertEqual(RetentionPeriod.oneWeek.displayName, "1 Week")
        XCTAssertEqual(RetentionPeriod.oneMonth.displayName, "1 Month")
        XCTAssertEqual(RetentionPeriod.threeMonths.displayName, "3 Months")
        XCTAssertEqual(RetentionPeriod.forever.displayName, "Forever")
    }
    
    // MARK: - UI Component Integration Tests
    
    func testTranscriptionHistoryViewIntegration() async throws {
        // Given - Records in the database
        let records = [
            createSampleRecord(text: "First UI test record", provider: .local),
            createSampleRecord(text: "Second UI test record", provider: .parakeet)
        ]
        
        for record in records {
            modelContext.insert(record)
        }
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        // When - Create the view
        let historyView = createTestView()
        
        // Then - View should be created successfully
        XCTAssertNotNil(historyView, "TranscriptionHistoryView should be created")
        
        // Verify data is accessible
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let viewRecords = try modelContext.fetch(descriptor)
        XCTAssertEqual(viewRecords.count, 2, "View should have access to records")
    }
    
    func testTranscriptionRecordRowIntegration() async throws {
        // Given - A record
        let record = createSampleRecord(
            text: "Test record for row integration",
            provider: .local,
            duration: 45.5,
            modelUsed: "small"
        )
        
        var copyCallCount = 0
        var deleteCallCount = 0
        var expandCallCount = 0
        
        // When - Create row view
        let rowView = TranscriptionRecordRow(
            record: record,
            isExpanded: false,
            onToggleExpand: { expandCallCount += 1 },
            onCopy: { copyCallCount += 1 },
            onDelete: { deleteCallCount += 1 }
        )
        
        // Then - View should be created and callbacks should work
        XCTAssertNotNil(rowView, "TranscriptionRecordRow should be created")
        
        // Test callbacks
        rowView.onCopy()
        rowView.onDelete()
        rowView.onToggleExpand()
        
        XCTAssertEqual(copyCallCount, 1, "Copy callback should be called")
        XCTAssertEqual(deleteCallCount, 1, "Delete callback should be called")
        XCTAssertEqual(expandCallCount, 1, "Expand callback should be called")
    }
    
    // MARK: - Data Validation Tests
    
    private struct RecordIntegrityCase {
        let text: String
        let provider: TranscriptionProvider
        let duration: TimeInterval?
        let model: String?
    }

    func testRecordDataIntegrity() async throws {
        // Test various record configurations
        let testCases: [RecordIntegrityCase] = [
            RecordIntegrityCase(text: "Short text", provider: .local, duration: 5.0, model: nil),
            RecordIntegrityCase(text: "Medium length text that should not be truncated in preview",
                                provider: .parakeet, duration: 125.5, model: nil),
            RecordIntegrityCase(text: String(repeating: "Long text ", count: 20),
                                provider: .local, duration: 3665.0, model: "base"), // > 100 chars for truncation test
            RecordIntegrityCase(text: "", provider: .parakeet, duration: nil, model: nil), // Edge case: empty text
            RecordIntegrityCase(text: "Special chars: @#$%^&*()_+ 世界 🌍", provider: .local, duration: 0.5, model: "small")
        ]

        for testCase in testCases {
            let text = testCase.text
            let provider = testCase.provider
            let duration = testCase.duration
            let model = testCase.model
            let record = createSampleRecord(
                text: text,
                provider: provider,
                duration: duration,
                modelUsed: model
            )
            
            modelContext.insert(record)
            try modelContext.save()
            
            await waitForAsyncOperation()
            
            // Verify record was saved correctly
            let savedRecord = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>()).last!
            
            XCTAssertEqual(savedRecord.text, text, "Text should be preserved exactly")
            XCTAssertEqual(savedRecord.provider, provider.rawValue, "Provider should match")
            XCTAssertEqual(savedRecord.duration, duration, "Duration should match")
            XCTAssertEqual(savedRecord.modelUsed, model, "Model should match")
            XCTAssertNotNil(savedRecord.id, "ID should be generated")
            XCTAssertNotNil(savedRecord.date, "Date should be set")
            
            // Test computed properties
            XCTAssertEqual(savedRecord.transcriptionProvider, provider, "Provider enum should work")
            if let model = model {
                XCTAssertEqual(savedRecord.whisperModel?.rawValue, model, "Whisper model enum should work")
            }
            
            // Clean up for next iteration
            modelContext.delete(savedRecord)
            try modelContext.save()
        }
    }
    
    func testFormattedDisplayProperties() async throws {
        // Test duration formatting
        let durationTestCases: [(TimeInterval?, String?)] = [
            (nil, nil),
            (30.5, "30.5s"),
            (65.0, "1m 5s"),
            (125.7, "2m 5s"),
            (3665.0, "1h 1m"),
            (7325.5, "2h 2m")
        ]
        
        for (duration, expectedFormat) in durationTestCases {
            let record = createSampleRecord(duration: duration)
            
            if let expectedFormat = expectedFormat {
                XCTAssertEqual(record.formattedDuration, expectedFormat, "Duration formatting should match expected")
            } else {
                XCTAssertNil(record.formattedDuration, "Nil duration should return nil formatted duration")
            }
        }
        
        // Test text preview truncation
        let shortText = "Short text"
        let longText = String(repeating: "a", count: 150)
        
        let shortRecord = createSampleRecord(text: shortText)
        let longRecord = createSampleRecord(text: longText)
        
        XCTAssertEqual(shortRecord.preview, shortText, "Short text should not be truncated")
        XCTAssertTrue(longRecord.preview.count <= 103, "Long text should be truncated")
        XCTAssertTrue(longRecord.preview.hasSuffix("..."), "Truncated text should end with ellipsis")
        
        // Test formatted date
        let record = createSampleRecord()
        XCTAssertFalse(record.formattedDate.isEmpty, "Formatted date should not be empty")
        XCTAssertTrue(record.formattedDate.count > 5, "Formatted date should be meaningful")
    }
    
    // MARK: - Error Scenarios and Edge Cases
    
    func testDataCorruptionRecovery() async throws {
        // Given - Valid records
        let validRecord = createSampleRecord(text: "Valid record", provider: .local)
        modelContext.insert(validRecord)
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        // When - Simulate corruption by modifying provider to invalid value
        let records = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        let record = records[0]
        record.provider = "invalid_provider"
        try modelContext.save()
        
        // Then - System should handle invalid provider gracefully
        XCTAssertNil(record.transcriptionProvider, "Invalid provider should return nil")
        XCTAssertEqual(record.provider, "invalid_provider", "Raw provider string should be preserved")
        
        // Search should still work with corrupted data
        XCTAssertTrue(record.matches(searchQuery: "invalid_provider"), "Search should work with invalid provider")
        XCTAssertTrue(record.matches(searchQuery: "Valid record"), "Text search should still work")
    }
    
    func testEmptyAndWhitespaceRecords() async throws {
        // Test edge cases with empty/whitespace content
        let edgeCaseRecords = [
            createSampleRecord(text: "", provider: .local),
            createSampleRecord(text: "   ", provider: .parakeet), // Only spaces
            createSampleRecord(text: "\n\t\r", provider: .local), // Only whitespace chars
            createSampleRecord(text: "   Valid text with spaces   ", provider: .parakeet)
        ]
        
        for record in edgeCaseRecords {
            modelContext.insert(record)
        }
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        let savedRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(savedRecords.count, 4, "All edge case records should be saved")
        
        // Test search behavior with empty/whitespace content
        let emptyRecord = savedRecords.first { $0.text.isEmpty }!
        XCTAssertFalse(emptyRecord.matches(searchQuery: "anything"), "Empty text should not match search terms")
        XCTAssertTrue(emptyRecord.matches(searchQuery: ""), "Empty search should match empty text")
        
        // Test preview behavior
        XCTAssertEqual(emptyRecord.preview, "", "Empty text preview should be empty")
        
        let whitespaceRecord = savedRecords.first { $0.text == "   " }!
        XCTAssertEqual(whitespaceRecord.preview, "   ", "Whitespace should be preserved in preview")
    }
    
    func testExtremelyLongText() async throws {
        // Test with very long transcription text
        let longTextUnit = "This is a very long transcription text that simulates real-world "
            + "scenarios where speech-to-text might produce extensive content. "
        let veryLongText = String(repeating: longTextUnit, count: 100) // ~10,000 characters

        let longRecord = createSampleRecord(text: veryLongText, provider: .local)
        modelContext.insert(longRecord)
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        let savedRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        let savedRecord = savedRecords[0]
        
        XCTAssertEqual(savedRecord.text.count, veryLongText.count, "Very long text should be saved completely")
        XCTAssertTrue(savedRecord.preview.count <= 103, "Preview should be truncated")
        XCTAssertTrue(savedRecord.preview.hasSuffix("..."), "Long preview should end with ellipsis")
        
        // Search should still work with very long text
        XCTAssertTrue(savedRecord.matches(searchQuery: "very long transcription"), "Search should work with long text")
        XCTAssertTrue(savedRecord.matches(searchQuery: "scenarios"), "Search should find text anywhere in long content")
    }
    
    func testConcurrentModifications() async throws {
        // Test concurrent access to the same records
        let initialRecords = [
            createSampleRecord(text: "Concurrent test 1", provider: .local),
            createSampleRecord(text: "Concurrent test 2", provider: .parakeet)
        ]
        
        for record in initialRecords {
            modelContext.insert(record)
        }
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        // Simulate concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Add new records
            group.addTask { @MainActor in
                let newRecord = self.createSampleRecord(text: "Added concurrently", provider: .local)
                self.modelContext.insert(newRecord)
                try? self.modelContext.save()
            }
            
            // Task 2: Read records
            group.addTask { @MainActor in
                _ = try? self.modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
            }
            
            // Task 3: Search records
            group.addTask { @MainActor in
                let records = try? self.modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
                _ = records?.filter { $0.matches(searchQuery: "test") }
            }
        }
        
        await waitForAsyncOperation()
        
        // Verify final state
        let finalRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertGreaterThanOrEqual(finalRecords.count, 2, "Should have at least initial records")
    }
}
