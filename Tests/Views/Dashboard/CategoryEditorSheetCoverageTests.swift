import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

/// Renders CategoryEditorSheet in create and edit modes to exercise its body
/// and the computed sections in CategoryEditorSheet+Sections.swift.
@MainActor
final class CategoryEditorSheetCoverageTests: XCTestCase {

    private func makeStore() -> CategoryStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatEditorCoverage-\(UUID().uuidString).json")
        return CategoryStore(storageURL: tmp)
    }

    private func render<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 680)
        host.layout()
    }

    func testRenderCreateMode() {
        let sheet = CategoryEditorSheet(
            category: nil,
            categoryStore: makeStore(),
            onSave: { _ in }
        )
        render(sheet)
        render(sheet.identitySection)
        render(sheet.appearanceSection)
        render(sheet.correctionSection)
    }

    func testRenderEditModeUserCategory() {
        let category = CategoryDefinition(
            id: "user-cat",
            displayName: "User Category",
            icon: "star.fill",
            colorHex: "#FF5500",
            promptDescription: "A user-defined category",
            promptTemplate: "Correct this text.",
            isSystem: false
        )
        var deleted = false
        let sheet = CategoryEditorSheet(
            category: category,
            categoryStore: makeStore(),
            onSave: { _ in },
            onDelete: { deleted = true }
        )
        render(sheet)
        render(sheet.identitySection)
        render(sheet.appearanceSection)
        render(sheet.correctionSection)
        XCTAssertFalse(deleted)
    }

    func testRenderEditModeSystemCategory() {
        let system = CategoryDefinition(
            id: "system-cat",
            displayName: "System Category",
            icon: "gear",
            colorHex: "#0088FF",
            promptDescription: "A system category",
            promptTemplate: "System correction template.",
            isSystem: true
        )
        let sheet = CategoryEditorSheet(
            category: system,
            categoryStore: makeStore(),
            onSave: { _ in }
        )
        render(sheet)
        // System categories disable the identifier field — exercise that branch.
        render(sheet.identitySection)
        XCTAssertTrue(sheet.isSystem)
    }

    func testRenderWithEmptyIconFallsBackToQuestionmark() {
        let category = CategoryDefinition(
            id: "no-icon",
            displayName: "No Icon Category",
            icon: "",
            colorHex: "#888888",
            promptDescription: "",
            promptTemplate: "Template",
            isSystem: false
        )
        let sheet = CategoryEditorSheet(
            category: category,
            categoryStore: makeStore(),
            onSave: { _ in }
        )
        render(sheet)
        render(sheet.appearanceSection)
    }

    func testFormHelpersRender() {
        let sheet = CategoryEditorSheet(
            category: nil,
            categoryStore: makeStore(),
            onSave: { _ in }
        )
        render(sheet.formSection("Section") { Text("content") })
        render(sheet.formField("Label") { Text("field") })
    }
}
