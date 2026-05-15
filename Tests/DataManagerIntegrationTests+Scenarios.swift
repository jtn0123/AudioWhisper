import XCTest
import SwiftData
@testable import AudioWhisper

// Concurrency / performance / settings / real-world integration tests, split out of
// DataManagerIntegrationTests to keep each file and type within SwiftLint limits.
@MainActor
extension DataManagerIntegrationTests {
    // MARK: - Concurrency Integration Tests
    
    func testConcurrentDataManagerOperations() async throws {
        let operationCount = 50
        
        // Perform concurrent saves
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<operationCount {
                group.addTask {
                    let record = await self.createSampleRecord(
                        text: "Concurrent record \(index)",
                        provider: TranscriptionProvider.allCases[index % TranscriptionProvider.allCases.count]
                    )
                    await self.dataManager.saveTranscriptionQuietly(record)
                }
            }
        }
        
        await waitForAsyncOperation()
        
        // Verify all records were saved
        let allRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(allRecords.count, operationCount, "All concurrent saves should succeed")
        
        // Test concurrent searches
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let results = (try? await self.dataManager.fetchRecords(matching: "Concurrent")) ?? []
                    return results.count
                }
            }
            
            var searchResults: [Int] = []
            for await result in group {
                searchResults.append(result)
            }
            
            // All searches should return the same count
            XCTAssertTrue(searchResults.allSatisfy { $0 == operationCount }, "Concurrent searches should be consistent")
        }
    }
    
    func testMixedConcurrentOperations() async throws {
        // Perform mixed read/write/delete operations concurrently
        
        // First, add some initial data
        for index in 0..<20 {
            let record = createSampleRecord(text: "Initial record \(index)", provider: .local)
            try await dataManager.saveTranscription(record)
        }
        
        await waitForAsyncOperation()
        
        // Now perform mixed operations
        await withTaskGroup(of: Void.self) { group in
            // Add new records
            for index in 0..<10 {
                group.addTask {
                    let record = await self.createSampleRecord(text: "New record \(index)", provider: .parakeet)
                    await self.dataManager.saveTranscriptionQuietly(record)
                }
            }
            
            // Perform searches
            for _ in 0..<5 {
                group.addTask {
                    _ = try? await self.dataManager.fetchRecords(matching: "record")
                }
            }
            
            // Delete some records
            group.addTask {
                let records = try? await self.dataManager.fetchAllRecords()
                if let recordsToDelete = records?.prefix(5) {
                    for record in recordsToDelete {
                        try? await self.dataManager.deleteRecord(record)
                    }
                }
            }
        }
        
        await waitForAsyncOperation()
        
        // Verify final state is consistent
        let finalRecords = try await dataManager.fetchAllRecords()
        XCTAssertGreaterThan(finalRecords.count, 0, "Should have some records remaining")
        XCTAssertLessThan(finalRecords.count, 30, "Should have fewer than initial + new records due to deletions")
        
        // Verify data integrity
        for record in finalRecords {
            XCTAssertFalse(record.text.isEmpty, "Records should have valid text")
            XCTAssertNotNil(record.id, "Records should have valid IDs")
            XCTAssertNotNil(record.date, "Records should have valid dates")
        }
    }
    
    // MARK: - Performance Integration Tests
    
    func testDataManagerPerformanceWithLargeDataset() async throws {
        let recordCount = 1000
        var records: [TranscriptionRecord] = []
        
        // Generate test data
        for index in 0..<recordCount {
            let provider = TranscriptionProvider.allCases[index % TranscriptionProvider.allCases.count]
            let text = "Performance test record \(index) with realistic transcription content that might be longer"
            let duration = Double.random(in: 1.0...300.0)
            let record = createSampleRecord(text: text, provider: provider, duration: duration)
            records.append(record)
        }
        
        // Test batch save performance
        let saveStartTime = CFAbsoluteTimeGetCurrent()
        
        for record in records {
            await dataManager.saveTranscriptionQuietly(record)
        }
        
        let saveEndTime = CFAbsoluteTimeGetCurrent()
        let saveTime = saveEndTime - saveStartTime
        
        print("Saved \(recordCount) records in \(saveTime) seconds")
        XCTAssertLessThan(saveTime, 30.0, "Saving should complete within reasonable time")
        
        await waitForAsyncOperation()
        
        // Test fetch performance
        let fetchStartTime = CFAbsoluteTimeGetCurrent()
        let fetchedRecords = await dataManager.fetchAllRecordsQuietly()
        let fetchEndTime = CFAbsoluteTimeGetCurrent()
        let fetchTime = fetchEndTime - fetchStartTime
        
        print("Fetched \(fetchedRecords.count) records in \(fetchTime) seconds")
        XCTAssertEqual(fetchedRecords.count, recordCount, "Should fetch all records")
        XCTAssertLessThan(fetchTime, 5.0, "Fetching should be fast")
        
        // Test search performance
        let searchStartTime = CFAbsoluteTimeGetCurrent()
        let searchResults = try await dataManager.fetchRecords(matching: "500")
        let searchEndTime = CFAbsoluteTimeGetCurrent()
        let searchTime = searchEndTime - searchStartTime
        
        print("Searched \(fetchedRecords.count) records in \(searchTime) seconds")
        XCTAssertGreaterThan(searchResults.count, 0, "Should find matching records")
        XCTAssertLessThan(searchTime, 2.0, "Search should be fast")
    }
    
    // MARK: - Settings Integration Tests
    
    func testDataManagerSettingsIntegration() async throws {
        // Test history enabled/disabled behavior
        let testRecord = createSampleRecord(text: "Settings test", provider: .local)
        
        // Enable history and save
        UserDefaults.standard.set(true, forKey: "transcriptionHistoryEnabled")
        dataManager.isHistoryEnabled = true
        
        try await dataManager.saveTranscription(testRecord)
        var records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 1, "Record should be saved when history enabled")
        
        // Disable history and try to save another
        UserDefaults.standard.set(false, forKey: "transcriptionHistoryEnabled")
        dataManager.isHistoryEnabled = false
        
        let anotherRecord = createSampleRecord(text: "Should not save", provider: .parakeet)
        try await dataManager.saveTranscription(anotherRecord)
        
        records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 1, "No new record should be saved when history disabled")
    }
    
    func testRetentionPeriodSettingsIntegration() async throws {
        // Test retention period changes
        let periods: [RetentionPeriod] = [.oneWeek, .oneMonth, .threeMonths, .forever]
        
        for period in periods {
            UserDefaults.standard.set(period.rawValue, forKey: "transcriptionRetentionPeriod")
            dataManager.retentionPeriod = period
            
            XCTAssertEqual(dataManager.retentionPeriod, period, "Retention period should be set correctly")
            
            // Test that timeInterval property matches expectations
            switch period {
            case .oneWeek:
                XCTAssertEqual(period.timeInterval, 7 * 24 * 60 * 60)
            case .oneMonth:
                XCTAssertEqual(period.timeInterval, 30 * 24 * 60 * 60)
            case .threeMonths:
                XCTAssertEqual(period.timeInterval, 90 * 24 * 60 * 60)
            case .forever:
                XCTAssertNil(period.timeInterval)
            }
        }
    }
    
    // MARK: - Real-world Integration Scenarios
    
    func testCompleteUserJourney() async throws {
        // Simulate a complete user journey from setup to data management
        
        // Step 1: User enables history
        UserDefaults.standard.set(true, forKey: "transcriptionHistoryEnabled")
        UserDefaults.standard.set(RetentionPeriod.oneMonth.rawValue, forKey: "transcriptionRetentionPeriod")
        
        dataManager.isHistoryEnabled = true
        dataManager.retentionPeriod = .oneMonth
        
        // Step 2: User creates multiple transcriptions over time
        let transcriptions = [
            ("Meeting notes from team standup", TranscriptionProvider.local, 450.0),
            ("Voice memo about vacation plans", TranscriptionProvider.local, 30.0),
            ("Interview with job candidate", TranscriptionProvider.parakeet, 1800.0),
            ("Conference call recording", TranscriptionProvider.parakeet, 2700.0),
            ("Quick reminder note", TranscriptionProvider.local, 15.0)
        ]
        
        for (text, provider, duration) in transcriptions {
            let record = createSampleRecord(text: text, provider: provider, duration: duration)
            try await dataManager.saveTranscription(record)
        }
        
        await waitForAsyncOperation()
        
        // Step 3: User searches for specific content
        let meetingResults = try await dataManager.fetchRecords(matching: "meeting")
        XCTAssertEqual(meetingResults.count, 1, "Should find meeting notes")
        
        let interviewResults = try await dataManager.fetchRecords(matching: "interview")
        XCTAssertEqual(interviewResults.count, 1, "Should find interview")
        
        let parakeetResults = try await dataManager.fetchRecords(matching: "parakeet")
        XCTAssertEqual(parakeetResults.count, 2, "Should find Parakeet transcriptions")
        
        // Step 4: User deletes some old records
        let allRecords = try await dataManager.fetchAllRecords()
        let voiceMemo = allRecords.first { $0.text.contains("vacation") }!
        try await dataManager.deleteRecord(voiceMemo)
        
        let afterDelete = try await dataManager.fetchAllRecords()
        XCTAssertEqual(afterDelete.count, 4, "Should have 4 records after deletion")
        
        // Step 5: User changes retention policy and performs cleanup
        dataManager.retentionPeriod = .oneWeek
        
        // Simulate some old records by changing their dates
        let recordsToAge = try await dataManager.fetchAllRecords()
        for (index, record) in recordsToAge.enumerated() where index < 2 {
            record.date = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        }
        
        try await dataManager.cleanupExpiredRecords()
        
        let afterCleanup = try await dataManager.fetchAllRecords()
        XCTAssertLessThan(afterCleanup.count, 4, "Should have fewer records after cleanup")
        
        // Step 6: User disables history
        dataManager.isHistoryEnabled = false
        
        let newRecord = createSampleRecord(text: "This should not be saved", provider: .local)
        try await dataManager.saveTranscription(newRecord)
        
        let finalRecords = try await dataManager.fetchAllRecords()
        XCTAssertEqual(finalRecords.count, afterCleanup.count, "No new records should be saved when history is disabled")
        
        // Verify data integrity throughout the journey
        for record in finalRecords {
            XCTAssertFalse(record.text.isEmpty, "All records should have valid text")
            XCTAssertNotNil(record.transcriptionProvider, "All records should have valid providers")
            XCTAssertNotNil(record.formattedDate, "All records should have formatted dates")
        }
    }
    
    // MARK: - Database-Level Search Performance Tests
    
    func testDatabaseLevelSearchWithPagination() async throws {
        // Create 100 test records to test performance
        for index in 0..<100 {
            let searchTerms = ["apple", "banana", "cherry", "date", "elderberry"]
            let provider = TranscriptionProvider.allCases[index % TranscriptionProvider.allCases.count]
            let searchTerm = searchTerms[index % searchTerms.count]

            let record = createSampleRecord(
                text: "Record \(index): Discussion about \(searchTerm) processing",
                provider: provider,
                duration: Double(index),
                modelUsed: provider == .local ? "tiny" : nil
            )
            try await dataManager.saveTranscription(record)
        }
        
        await waitForAsyncOperation()
        
        // Test paginated search
        let firstPage = try await dataManager.fetchRecords(matching: "apple", limit: 10, offset: 0)
        XCTAssertEqual(firstPage.count, 10, "Should return exactly 10 records for first page")
        
        let secondPage = try await dataManager.fetchRecords(matching: "apple", limit: 10, offset: 10)
        XCTAssertEqual(secondPage.count, 10, "Should return exactly 10 records for second page")
        
        // Verify pages contain different records
        let firstPageIds = Set(firstPage.map { $0.id })
        let secondPageIds = Set(secondPage.map { $0.id })
        XCTAssertTrue(firstPageIds.isDisjoint(with: secondPageIds), "Pages should contain different records")
        
        // Test search with different terms
        let bananaResults = try await dataManager.fetchRecords(matching: "banana", limit: 5, offset: 0)
        XCTAssertEqual(bananaResults.count, 5, "Should return up to 5 banana records")
        
        // Test case-insensitive search
        let uppercaseResults = try await dataManager.fetchRecords(matching: "APPLE", limit: 10, offset: 0)
        XCTAssertEqual(uppercaseResults.count, 10, "Case-insensitive search should work")
        
        // Test search in provider field
        let parakeetResults = try await dataManager.fetchRecords(matching: "parakeet", limit: nil, offset: nil)
        XCTAssertGreaterThan(parakeetResults.count, 0, "Should find records by provider name")
        
        // Test search in modelUsed field
        let tinyResults = try await dataManager.fetchRecords(matching: "tiny", limit: nil, offset: nil)
        XCTAssertGreaterThan(tinyResults.count, 0, "Should find records by model name")
        
        // Performance comparison - ensure predicate search is reasonably fast
        let startTime = Date()
        _ = try await dataManager.fetchRecords(matching: "processing", limit: 50, offset: 0)
        let searchDuration = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(searchDuration, 1.0, "Database search should complete within 1 second")
    }
}
