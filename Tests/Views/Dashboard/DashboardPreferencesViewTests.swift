import XCTest
@testable import AudioWhisper

final class DashboardPreferencesViewTests: XCTestCase {

    // MARK: - Gigabytes Formatting

    func testFormattedGigabytesWholeNumbers() {
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(1), "1 GB")
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(5), "5 GB")
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(10), "10 GB")
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(20), "20 GB")
    }

    func testFormattedGigabytesDecimalNumbers() {
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(1.5), "1.5 GB")
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(2.5), "2.5 GB")
    }

    func testFormattedGigabytesZero() {
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(0), "0 GB")
    }

    func testFormattedGigabytesLargeNumbers() {
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(100), "100 GB")
        // NumberFormatter without usesGroupingSeparator doesn't add commas
        XCTAssertEqual(DashboardPreferencesView.testableFormattedGigabytes(1000), "1000 GB")
    }

    // MARK: - Retention Period Parsing

    func testRetentionPeriodFromValidValues() {
        XCTAssertEqual(
            DashboardPreferencesView.testableRetentionPeriod(from: "oneWeek"),
            .oneWeek
        )
        XCTAssertEqual(
            DashboardPreferencesView.testableRetentionPeriod(from: "oneMonth"),
            .oneMonth
        )
        XCTAssertEqual(
            DashboardPreferencesView.testableRetentionPeriod(from: "threeMonths"),
            .threeMonths
        )
        XCTAssertEqual(
            DashboardPreferencesView.testableRetentionPeriod(from: "forever"),
            .forever
        )
    }

    func testRetentionPeriodFromInvalidValue() {
        // Should default to oneMonth
        XCTAssertEqual(
            DashboardPreferencesView.testableRetentionPeriod(from: "invalid"),
            .oneMonth
        )
        XCTAssertEqual(
            DashboardPreferencesView.testableRetentionPeriod(from: ""),
            .oneMonth
        )
    }

    // MARK: - Storage Options

    func testStorageOptionsAreValid() {
        let options = DashboardPreferencesView.testableStorageOptions()

        XCTAssertEqual(options.count, 5)
        XCTAssertTrue(options.contains(1))
        XCTAssertTrue(options.contains(2))
        XCTAssertTrue(options.contains(5))
        XCTAssertTrue(options.contains(10))
        XCTAssertTrue(options.contains(20))
    }

    func testStorageOptionsAreSorted() {
        let options = DashboardPreferencesView.testableStorageOptions()
        let sorted = options.sorted()

        XCTAssertEqual(options, sorted, "Storage options should be in ascending order")
    }

    func testStorageOptionsArePositive() {
        let options = DashboardPreferencesView.testableStorageOptions()

        for option in options {
            XCTAssertGreaterThan(option, 0, "All storage options should be positive")
        }
    }

    // MARK: - Retention Period Display Names

    func testRetentionPeriodDisplayNames() {
        // Verify all retention periods have meaningful display names
        for period in RetentionPeriod.allCases {
            XCTAssertFalse(period.displayName.isEmpty, "Retention period \(period) should have a display name")
            XCTAssertNotEqual(period.displayName, period.rawValue, "Display name should be human-readable")
        }
    }
}
