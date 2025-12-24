import XCTest
@testable import AudioWhisper

final class CategoryStoreTests: XCTestCase {
    private var tempStorageURL: URL!
    private var store: CategoryStore!

    override func setUp() {
        super.setUp()
        // Create a unique temp file for each test
        tempStorageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategoryStoreTests-\(UUID().uuidString).json")
        store = CategoryStore(storageURL: tempStorageURL)
    }

    override func tearDown() {
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempStorageURL)
        store = nil
        tempStorageURL = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationLoadsDefaults() {
        XCTAssertFalse(store.categories.isEmpty, "Store should have default categories")
        XCTAssertEqual(store.categories.count, CategoryDefinition.defaults.count)
    }

    // MARK: - Category Lookup Tests

    func testCategoryWithIdReturnsCorrectCategory() {
        let terminalCategory = store.category(withId: "terminal")
        XCTAssertEqual(terminalCategory.id, "terminal")
        XCTAssertEqual(terminalCategory.displayName, "Terminal")
    }

    func testCategoryWithIdReturnsFallbackForUnknown() {
        let unknownCategory = store.category(withId: "nonexistent-category")
        XCTAssertEqual(unknownCategory.id, CategoryDefinition.fallback.id)
    }

    func testContainsCategoryReturnsTrueForExisting() {
        XCTAssertTrue(store.containsCategory(withId: "terminal"))
        XCTAssertTrue(store.containsCategory(withId: "coding"))
        XCTAssertTrue(store.containsCategory(withId: "general"))
    }

    func testContainsCategoryReturnsFalseForMissing() {
        XCTAssertFalse(store.containsCategory(withId: "nonexistent"))
        XCTAssertFalse(store.containsCategory(withId: ""))
    }

    // MARK: - Upsert Tests

    func testUpsertCreatesNewCategory() {
        let newCategory = CategoryDefinition(
            id: "custom-test",
            displayName: "Custom Test",
            icon: "star",
            colorHex: "#FF0000",
            promptDescription: "A test category",
            promptTemplate: "Test prompt template",
            isSystem: false
        )

        let initialCount = store.categories.count
        store.upsert(newCategory)

        XCTAssertEqual(store.categories.count, initialCount + 1)
        XCTAssertTrue(store.containsCategory(withId: "custom-test"))
        XCTAssertEqual(store.category(withId: "custom-test").displayName, "Custom Test")
    }

    func testUpsertUpdatesExistingCategory() {
        // First, add a custom category
        let original = CategoryDefinition(
            id: "update-test",
            displayName: "Original Name",
            icon: "circle",
            colorHex: "#00FF00",
            promptDescription: "Original description",
            promptTemplate: "Original template",
            isSystem: false
        )
        store.upsert(original)

        let countAfterInsert = store.categories.count

        // Now update it
        let updated = CategoryDefinition(
            id: "update-test",
            displayName: "Updated Name",
            icon: "square",
            colorHex: "#0000FF",
            promptDescription: "Updated description",
            promptTemplate: "Updated template",
            isSystem: false
        )
        store.upsert(updated)

        // Count should remain the same
        XCTAssertEqual(store.categories.count, countAfterInsert)

        // Values should be updated
        let retrieved = store.category(withId: "update-test")
        XCTAssertEqual(retrieved.displayName, "Updated Name")
        XCTAssertEqual(retrieved.icon, "square")
        XCTAssertEqual(retrieved.colorHex, "#0000FF")
    }

    // MARK: - Delete Tests

    func testDeleteRemovesUserCategory() {
        // Add a custom category
        let custom = CategoryDefinition(
            id: "deletable",
            displayName: "Deletable",
            icon: "trash",
            colorHex: "#999999",
            promptDescription: "Will be deleted",
            promptTemplate: "Template",
            isSystem: false
        )
        store.upsert(custom)
        XCTAssertTrue(store.containsCategory(withId: "deletable"))

        // Delete it
        store.delete(custom)

        XCTAssertFalse(store.containsCategory(withId: "deletable"))
    }

    func testDeletePreventsSystemCategoryDeletion() {
        // Get a system category
        let terminal = store.category(withId: "terminal")
        XCTAssertTrue(terminal.isSystem)

        let countBefore = store.categories.count

        // Try to delete it
        store.delete(terminal)

        // Should still exist
        XCTAssertEqual(store.categories.count, countBefore)
        XCTAssertTrue(store.containsCategory(withId: "terminal"))
    }

    // MARK: - Reset Tests

    func testResetToDefaultsRestoresAllCategories() {
        // Add a custom category
        let custom = CategoryDefinition(
            id: "will-be-removed",
            displayName: "Temporary",
            icon: "xmark",
            colorHex: "#123456",
            promptDescription: "Temporary category",
            promptTemplate: "Template",
            isSystem: false
        )
        store.upsert(custom)
        XCTAssertTrue(store.containsCategory(withId: "will-be-removed"))

        // Reset to defaults
        store.resetToDefaults()

        // Custom category should be gone
        XCTAssertFalse(store.containsCategory(withId: "will-be-removed"))

        // Should have exactly the default categories
        XCTAssertEqual(store.categories.count, CategoryDefinition.defaults.count)
    }

    // MARK: - Persistence Tests

    func testPersistenceWritesToDisk() {
        // Add a custom category
        let custom = CategoryDefinition(
            id: "persisted",
            displayName: "Persisted Category",
            icon: "doc",
            colorHex: "#ABCDEF",
            promptDescription: "Should be saved",
            promptTemplate: "Template",
            isSystem: false
        )
        store.upsert(custom)

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempStorageURL.path))

        // Verify content
        let data = try? Data(contentsOf: tempStorageURL)
        XCTAssertNotNil(data)

        if let data = data {
            let decoded = try? JSONDecoder().decode([CategoryDefinition].self, from: data)
            XCTAssertNotNil(decoded)
            XCTAssertTrue(decoded?.contains(where: { $0.id == "persisted" }) ?? false)
        }
    }

    func testLoadFromDiskRestoresPersistedCategories() {
        // Add a custom category and verify it's persisted
        let custom = CategoryDefinition(
            id: "reload-test",
            displayName: "Reload Test",
            icon: "arrow.clockwise",
            colorHex: "#654321",
            promptDescription: "For reload testing",
            promptTemplate: "Template",
            isSystem: false
        )
        store.upsert(custom)

        // Create a new store with the same storage URL
        let newStore = CategoryStore(storageURL: tempStorageURL)

        // Should load the persisted category
        XCTAssertTrue(newStore.containsCategory(withId: "reload-test"))
        XCTAssertEqual(newStore.category(withId: "reload-test").displayName, "Reload Test")
    }

    // MARK: - Index Consistency Tests

    func testIndexConsistencyAfterMultipleOperations() {
        // Add several categories
        for i in 1...5 {
            let category = CategoryDefinition(
                id: "test-\(i)",
                displayName: "Test \(i)",
                icon: "number",
                colorHex: "#000000",
                promptDescription: "Test \(i)",
                promptTemplate: "Template",
                isSystem: false
            )
            store.upsert(category)
        }

        // Delete some
        store.delete(store.category(withId: "test-2"))
        store.delete(store.category(withId: "test-4"))

        // Update one
        var updated = store.category(withId: "test-3")
        updated.displayName = "Updated Test 3"
        store.upsert(updated)

        // Verify index is consistent
        XCTAssertTrue(store.containsCategory(withId: "test-1"))
        XCTAssertFalse(store.containsCategory(withId: "test-2"))
        XCTAssertTrue(store.containsCategory(withId: "test-3"))
        XCTAssertFalse(store.containsCategory(withId: "test-4"))
        XCTAssertTrue(store.containsCategory(withId: "test-5"))

        // Verify lookup returns correct values
        XCTAssertEqual(store.category(withId: "test-3").displayName, "Updated Test 3")
    }
}
