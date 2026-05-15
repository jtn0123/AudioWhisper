import XCTest
import SwiftUI
import SwiftData
@testable import AudioWhisper

// Delete-operation integration tests, split out of TranscriptionHistoryIntegrationTests
// to keep each type within SwiftLint body-length limits.
@MainActor
extension TranscriptionHistoryIntegrationTests {
    // MARK: - Delete Operations Integration Tests
    
    func testSingleRecordDeletion() async throws {
        // Given - Multiple records
        let records = [
            createSampleRecord(text: "Keep this record", provider: .local),
            createSampleRecord(text: "Delete this record", provider: .parakeet),
            createSampleRecord(text: "Keep this one too", provider: .local)
        ]
        
        for record in records {
            modelContext.insert(record)
        }
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        var allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(allRecords.count, 3, "Should start with 3 records")
        
        // When - Delete specific record
        let recordToDelete = allRecords.first { $0.text == "Delete this record" }!
        modelContext.delete(recordToDelete)
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        // Then - Verify deletion
        allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(allRecords.count, 2, "Should have 2 records after deletion")
        
        let remainingTexts = allRecords.map { $0.text }
        XCTAssertTrue(remainingTexts.contains("Keep this record"))
        XCTAssertTrue(remainingTexts.contains("Keep this one too"))
        XCTAssertFalse(remainingTexts.contains("Delete this record"))
    }
    
    func testBulkDeletion() async throws {
        // Given - Many records
        var records: [TranscriptionRecord] = []
        for index in 1...10 {
            records.append(createSampleRecord(
                text: "Record number \(index)",
                provider: index % 2 == 0 ? .local : .parakeet
            ))
        }

        for record in records {
            modelContext.insert(record)
        }
        try modelContext.save()

        await waitForAsyncOperation()

        var allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(allRecords.count, 10, "Should start with 10 records")

        // When - Delete all local records (should be 5)
        let localRecords = allRecords.filter { $0.provider == "local" }
        XCTAssertEqual(localRecords.count, 5, "Should have 5 local records")

        for record in localRecords {
            modelContext.delete(record)
        }
        try modelContext.save()

        await waitForAsyncOperation()

        // Then - Verify bulk deletion
        allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(allRecords.count, 5, "Should have 5 records after bulk deletion")

        // All remaining should be parakeet records
        for record in allRecords {
            XCTAssertEqual(record.provider, "parakeet", "All remaining records should be parakeet")
        }
    }
    
    func testDeleteAllRecords() async throws {
        // Given - Multiple records
        let records = [
            createSampleRecord(text: "Record 1", provider: .local),
            createSampleRecord(text: "Record 2", provider: .parakeet),
            createSampleRecord(text: "Record 3", provider: .local),
            createSampleRecord(text: "Record 4", provider: .parakeet)
        ]
        
        for record in records {
            modelContext.insert(record)
        }
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        var allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(allRecords.count, 4, "Should start with 4 records")
        
        // When - Delete all records
        for record in allRecords {
            modelContext.delete(record)
        }
        try modelContext.save()
        
        await waitForAsyncOperation()
        
        // Then - Verify all deleted
        allRecords = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
        XCTAssertEqual(allRecords.count, 0, "Should have no records after delete all")
    }
    
}
