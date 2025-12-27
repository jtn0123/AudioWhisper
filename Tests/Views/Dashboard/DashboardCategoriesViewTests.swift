import XCTest
@testable import AudioWhisper

final class DashboardCategoriesViewTests: XCTestCase {

    // MARK: - Last Category Detection

    func testIsLastCategoryReturnsTrueForLastItem() {
        let categories = CategoryDefinition.defaults
        guard let lastCategory = categories.last else {
            XCTFail("Expected at least one category")
            return
        }

        XCTAssertTrue(DashboardCategoriesView.testableIsLastCategory(lastCategory.id, in: categories))
    }

    func testIsLastCategoryReturnsFalseForFirstItem() {
        let categories = CategoryDefinition.defaults
        guard let firstCategory = categories.first else {
            XCTFail("Expected at least one category")
            return
        }

        XCTAssertFalse(DashboardCategoriesView.testableIsLastCategory(firstCategory.id, in: categories))
    }

    func testIsLastCategoryReturnsFalseForMiddleItem() throws {
        let categories = CategoryDefinition.defaults
        guard categories.count > 2 else {
            throw XCTSkip("Need at least 3 categories for this test")
        }

        let middleIndex = categories.count / 2
        let middleCategory = categories[middleIndex]

        XCTAssertFalse(DashboardCategoriesView.testableIsLastCategory(middleCategory.id, in: categories))
    }

    func testIsLastCategoryReturnsFalseForEmptyList() {
        let categories: [CategoryDefinition] = []
        XCTAssertFalse(DashboardCategoriesView.testableIsLastCategory("any-id", in: categories))
    }

    // MARK: - Initials Generation

    func testInitialsFromTwoWordName() {
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "Visual Studio"), "VS")
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "Google Chrome"), "GC")
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "Apple Music"), "AM")
    }

    func testInitialsFromSingleWordName() {
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "Safari"), "S")
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "Xcode"), "X")
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "Slack"), "S")
    }

    func testInitialsFromMultiWordName() {
        // Should only use first two words
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "Microsoft Visual Studio"), "MV")
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "JetBrains IntelliJ IDEA"), "JI")
    }

    func testInitialsFromEmptyString() {
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: ""), "?")
    }

    func testInitialsAreCaseSensitive() {
        // Should preserve case of first letters
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "visual studio"), "vs")
        XCTAssertEqual(DashboardCategoriesView.testableInitials(from: "VISUAL STUDIO"), "VS")
    }

    // MARK: - Last Source Detection

    func testIsLastSourceWithMatchingId() {
        let now = Date()
        let sources = [
            SourceUsageStats(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                totalWords: 100,
                totalCharacters: 500,
                sessionCount: 5,
                lastUsed: now
            ),
            SourceUsageStats(
                bundleIdentifier: "com.google.Chrome",
                displayName: "Chrome",
                totalWords: 200,
                totalCharacters: 1000,
                sessionCount: 10,
                lastUsed: now
            ),
            SourceUsageStats(
                bundleIdentifier: "com.apple.mail",
                displayName: "Mail",
                totalWords: 50,
                totalCharacters: 250,
                sessionCount: 2,
                lastUsed: now
            )
        ]

        XCTAssertTrue(DashboardCategoriesView.testableIsLastSource(sources.last!.id, in: sources))
        XCTAssertFalse(DashboardCategoriesView.testableIsLastSource(sources.first!.id, in: sources))
    }

    func testIsLastSourceWithEmptyList() {
        let sources: [SourceUsageStats] = []
        XCTAssertFalse(DashboardCategoriesView.testableIsLastSource("any-id", in: sources))
    }

    // MARK: - Category Definitions

    func testDefaultCategoriesExist() {
        let categories = CategoryDefinition.defaults
        XCTAssertGreaterThan(categories.count, 0, "Should have default categories")
    }

    func testDefaultCategoriesHaveUniqueIds() {
        let categories = CategoryDefinition.defaults
        let ids = categories.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All category IDs should be unique")
    }

    func testDefaultCategoriesAreSystemCategories() {
        let categories = CategoryDefinition.defaults
        for category in categories {
            XCTAssertTrue(category.isSystem, "Default category '\(category.id)' should be marked as system")
        }
    }
}
