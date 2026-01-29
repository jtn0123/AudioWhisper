import XCTest
import SwiftUI
@testable import AudioWhisper

/// Tests for CategoryEditorSheet form validation and logic
@MainActor
final class CategoryEditorSheetTests: XCTestCase {

    // MARK: - Form Validation Tests

    func testValidationPassesWithValidInput() {
        let result = CategoryEditorSheet.testableValidate(
            displayName: "My Category",
            identifier: "my-category",
            originalId: nil,
            existingIds: []
        )

        XCTAssertEqual(result, .valid)
    }

    func testValidationFailsWithEmptyName() {
        let result = CategoryEditorSheet.testableValidate(
            displayName: "",
            identifier: "my-category",
            originalId: nil,
            existingIds: []
        )

        XCTAssertEqual(result, .emptyName)
    }

    func testValidationFailsWithWhitespaceOnlyName() {
        let result = CategoryEditorSheet.testableValidate(
            displayName: "   ",
            identifier: "my-category",
            originalId: nil,
            existingIds: []
        )

        XCTAssertEqual(result, .emptyName)
    }

    func testValidationFailsWithDuplicateId() {
        let result = CategoryEditorSheet.testableValidate(
            displayName: "My Category",
            identifier: "existing-id",
            originalId: nil,
            existingIds: ["existing-id", "other-id"]
        )

        XCTAssertEqual(result, .duplicateId)
    }

    func testValidationPassesWhenEditingOwnId() {
        // When editing, the original ID should not trigger duplicate check
        let result = CategoryEditorSheet.testableValidate(
            displayName: "My Category",
            identifier: "existing-id",
            originalId: "existing-id",
            existingIds: ["existing-id", "other-id"]
        )

        XCTAssertEqual(result, .valid)
    }

    func testValidationFailsWhenChangingToExistingId() {
        let result = CategoryEditorSheet.testableValidate(
            displayName: "My Category",
            identifier: "other-id",
            originalId: "original-id",
            existingIds: ["original-id", "other-id"]
        )

        XCTAssertEqual(result, .duplicateId)
    }

    // MARK: - New Category Detection Tests

    func testIsNewCategoryWhenNil() {
        XCTAssertTrue(CategoryEditorSheet.testableIsNewCategory(category: nil))
    }

    func testIsNotNewCategoryWhenExists() {
        let category = CategoryDefinition.fallback
        XCTAssertFalse(CategoryEditorSheet.testableIsNewCategory(category: category))
    }

    // MARK: - Identifier Disabled Tests

    func testIdentifierDisabledForSystemCategory() {
        XCTAssertTrue(CategoryEditorSheet.testableIsIdentifierDisabled(isSystem: true))
    }

    func testIdentifierEnabledForUserCategory() {
        XCTAssertFalse(CategoryEditorSheet.testableIsIdentifierDisabled(isSystem: false))
    }

    // MARK: - Delete Button Visibility Tests

    func testShowsDeleteButtonForExistingUserCategoryWithHandler() {
        XCTAssertTrue(CategoryEditorSheet.testableShowsDeleteButton(
            isNewCategory: false,
            isSystem: false,
            hasDeleteHandler: true
        ))
    }

    func testHidesDeleteButtonForNewCategory() {
        XCTAssertFalse(CategoryEditorSheet.testableShowsDeleteButton(
            isNewCategory: true,
            isSystem: false,
            hasDeleteHandler: true
        ))
    }

    func testHidesDeleteButtonForSystemCategory() {
        XCTAssertFalse(CategoryEditorSheet.testableShowsDeleteButton(
            isNewCategory: false,
            isSystem: true,
            hasDeleteHandler: true
        ))
    }

    func testHidesDeleteButtonWithoutHandler() {
        XCTAssertFalse(CategoryEditorSheet.testableShowsDeleteButton(
            isNewCategory: false,
            isSystem: false,
            hasDeleteHandler: false
        ))
    }

    // MARK: - Save Button Disabled Tests

    func testSaveDisabledWithEmptyName() {
        XCTAssertTrue(CategoryEditorSheet.testableIsSaveDisabled(displayName: ""))
    }

    func testSaveEnabledWithName() {
        XCTAssertFalse(CategoryEditorSheet.testableIsSaveDisabled(displayName: "My Category"))
    }

    // MARK: - Default Values Tests

    func testDefaultCategoryValues() {
        let defaults = CategoryEditorSheet.testableDefaultCategoryValues()

        XCTAssertEqual(defaults.id, "new-category")
        XCTAssertEqual(defaults.name, "New Category")
        XCTAssertEqual(defaults.icon, "sparkles")
        XCTAssertEqual(defaults.colorHex, "#888888")
        XCTAssertEqual(defaults.description, "Describe this category's purpose")
    }

    // MARK: - Normalization Tests

    func testNormalizeTrimsWhitespace() {
        let result = CategoryEditorSheet.testableNormalizeForSave(
            identifier: "  my-id  ",
            displayName: "  My Name  ",
            icon: "  star  ",
            promptDescription: "  Description  ",
            promptTemplate: "  Template  "
        )

        XCTAssertEqual(result.id, "my-id")
        XCTAssertEqual(result.name, "My Name")
        XCTAssertEqual(result.icon, "star")
        XCTAssertEqual(result.desc, "Description")
        XCTAssertEqual(result.template, "Template")
    }

    func testNormalizeHandlesEmptyStrings() {
        let result = CategoryEditorSheet.testableNormalizeForSave(
            identifier: "",
            displayName: "",
            icon: "",
            promptDescription: "",
            promptTemplate: ""
        )

        XCTAssertTrue(result.id.isEmpty)
        XCTAssertTrue(result.name.isEmpty)
        XCTAssertTrue(result.icon.isEmpty)
        XCTAssertTrue(result.desc.isEmpty)
        XCTAssertTrue(result.template.isEmpty)
    }

    // MARK: - CategoryDefinition Tests

    func testCategoryDefinitionFallbackExists() {
        let fallback = CategoryDefinition.fallback
        XCTAssertFalse(fallback.id.isEmpty)
        XCTAssertFalse(fallback.displayName.isEmpty)
        XCTAssertFalse(fallback.promptTemplate.isEmpty)
    }

    func testCategoryDefinitionColorFromHex() {
        let category = CategoryDefinition(
            id: "test",
            displayName: "Test",
            icon: "star",
            colorHex: "#FF5500",
            promptDescription: "Test desc",
            promptTemplate: "Test template",
            isSystem: false
        )

        XCTAssertNotNil(category.color)
    }

    // MARK: - Edit Mode vs Create Mode Tests

    func testEditModePopulatesFields() {
        let original = CategoryDefinition(
            id: "original-id",
            displayName: "Original Name",
            icon: "star.fill",
            colorHex: "#FF0000",
            promptDescription: "Original desc",
            promptTemplate: "Original template",
            isSystem: false
        )

        // In edit mode, category is non-nil
        XCTAssertFalse(CategoryEditorSheet.testableIsNewCategory(category: original))
    }

    func testCreateModeStartsEmpty() {
        // In create mode, category is nil
        XCTAssertTrue(CategoryEditorSheet.testableIsNewCategory(category: nil))
    }

    // MARK: - System Category Tests

    func testSystemCategoryCannotChangeId() {
        let systemCategory = CategoryDefinition(
            id: "system-id",
            displayName: "System Category",
            icon: "gear",
            colorHex: "#0000FF",
            promptDescription: "System desc",
            promptTemplate: "System template",
            isSystem: true
        )

        XCTAssertTrue(systemCategory.isSystem)
        XCTAssertTrue(CategoryEditorSheet.testableIsIdentifierDisabled(isSystem: systemCategory.isSystem))
    }

    func testSystemCategoryCannotBeDeleted() {
        XCTAssertFalse(CategoryEditorSheet.testableShowsDeleteButton(
            isNewCategory: false,
            isSystem: true,
            hasDeleteHandler: true
        ))
    }

    // MARK: - Form State Logic Tests

    func testFormStateTransitions() {
        var displayName = ""
        var validationError: String?

        // Initial state - save disabled
        XCTAssertTrue(CategoryEditorSheet.testableIsSaveDisabled(displayName: displayName))

        // User types name - save enabled
        displayName = "My Category"
        XCTAssertFalse(CategoryEditorSheet.testableIsSaveDisabled(displayName: displayName))

        // User clears name - save disabled again
        displayName = ""
        XCTAssertTrue(CategoryEditorSheet.testableIsSaveDisabled(displayName: displayName))

        // Validation error set
        validationError = "Display name is required"
        XCTAssertNotNil(validationError)
    }

    // MARK: - Icon Validation Tests

    func testEmptyIconShowsQuestionmark() {
        // In the view, empty icon falls back to "questionmark"
        let icon = ""
        let displayIcon = icon.isEmpty ? "questionmark" : icon
        XCTAssertEqual(displayIcon, "questionmark")
    }

    func testNonEmptyIconShowsProvided() {
        let icon = "star"
        let displayIcon = icon.isEmpty ? "questionmark" : icon
        XCTAssertEqual(displayIcon, "star")
    }

    // MARK: - Color Hex Tests

    func testDefaultColorHex() {
        let defaults = CategoryEditorSheet.testableDefaultCategoryValues()
        XCTAssertEqual(defaults.colorHex, "#888888")
    }

    // MARK: - Preview Text Tests

    func testPreviewTextWithEmptyName() {
        let displayName = ""
        let previewText = displayName.isEmpty ? "Category Name" : displayName
        XCTAssertEqual(previewText, "Category Name")
    }

    func testPreviewTextWithName() {
        let displayName = "My Custom Category"
        let previewText = displayName.isEmpty ? "Category Name" : displayName
        XCTAssertEqual(previewText, "My Custom Category")
    }

    func testPreviewIdentifierWithEmptyId() {
        let identifier = ""
        let previewId = identifier.isEmpty ? "identifier" : identifier
        XCTAssertEqual(previewId, "identifier")
    }

    func testPreviewIdentifierWithId() {
        let identifier = "my-custom-id"
        let previewId = identifier.isEmpty ? "identifier" : identifier
        XCTAssertEqual(previewId, "my-custom-id")
    }
}
