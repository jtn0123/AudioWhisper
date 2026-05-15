import XCTest
import SwiftData
@testable import AudioWhisper

// Retention-policy tests, split out of DataManagerTests to keep each type
// within SwiftLint's body-length limits.
@MainActor
extension DataManagerTests {
    func testRetentionPeriodEnum() {
        XCTAssertEqual(RetentionPeriod.oneWeek.displayName, "1 Week")
        XCTAssertEqual(RetentionPeriod.oneMonth.displayName, "1 Month")
        XCTAssertEqual(RetentionPeriod.threeMonths.displayName, "3 Months")
        XCTAssertEqual(RetentionPeriod.forever.displayName, "Forever")

        XCTAssertNotNil(RetentionPeriod.oneWeek.timeInterval)
        XCTAssertNotNil(RetentionPeriod.oneMonth.timeInterval)
        XCTAssertNotNil(RetentionPeriod.threeMonths.timeInterval)
        XCTAssertNil(RetentionPeriod.forever.timeInterval)

        // Test time intervals are reasonable
        XCTAssertEqual(RetentionPeriod.oneWeek.timeInterval, 7 * 24 * 60 * 60)
        XCTAssertEqual(RetentionPeriod.oneMonth.timeInterval, 30 * 24 * 60 * 60)
        XCTAssertEqual(RetentionPeriod.threeMonths.timeInterval, 90 * 24 * 60 * 60)
    }

    func testCleanupExpiredRecordsWithForeverRetention() async throws {
        dataManager.retentionPeriod = .forever
        dataManager.isHistoryEnabled = true

        // Create an old record
        let oldRecord = TranscriptionRecord(text: "Old record", provider: .local)
        try await dataManager.saveTranscription(oldRecord)

        // Cleanup should not remove anything
        try await dataManager.cleanupExpiredRecords()

        let records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 1)
    }

    func testCleanupExpiredRecordsWithTimeBasedRetention() async throws {
        dataManager.retentionPeriod = .oneWeek
        dataManager.isHistoryEnabled = true

        // Create records with different dates
        let recentRecord = TranscriptionRecord(text: "Recent", provider: .local)
        let oldRecord = TranscriptionRecord(text: "Old", provider: .parakeet)

        // Manually set an old date for testing
        let oneMonthAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        oldRecord.date = oneMonthAgo

        try await dataManager.saveTranscription(recentRecord)
        try await dataManager.saveTranscription(oldRecord)

        var records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 2)

        // Cleanup should remove the old record
        try await dataManager.cleanupExpiredRecords()

        records = try await dataManager.fetchAllRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Recent")
    }

    func testCleanupExpiredRecordsQuietly() async {
        dataManager.retentionPeriod = .oneWeek
        dataManager.isHistoryEnabled = true

        let record = TranscriptionRecord(text: "Test", provider: .local)
        await dataManager.saveTranscriptionQuietly(record)

        // Should not throw
        await dataManager.cleanupExpiredRecordsQuietly()

        let records = await dataManager.fetchAllRecordsQuietly()
        XCTAssertEqual(records.count, 1)
    }
}
