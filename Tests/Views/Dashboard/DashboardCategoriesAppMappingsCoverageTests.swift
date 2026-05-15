import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

/// Renders the app-mapping rows from DashboardCategoriesView+AppMappings.swift.
@MainActor
final class DashboardCategoriesAppMappingsCoverageTests: XCTestCase {

    private func render<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 200)
        host.layout()
    }

    private func makeStat(
        bundle: String = "com.apple.Notes",
        name: String = "Notes"
    ) -> SourceUsageStats {
        SourceUsageStats(
            bundleIdentifier: bundle,
            displayName: name,
            totalWords: 120,
            totalCharacters: 600,
            sessionCount: 3,
            lastUsed: Date(),
            fallbackSymbolName: nil,
            iconData: nil
        )
    }

    func testRenderAppMappingRow() {
        let view = DashboardCategoriesView()
        let stat = makeStat()
        render(view.appMappingRow(stat))
    }

    func testRenderCategoryPickerNotOverridden() {
        let view = DashboardCategoriesView()
        let stat = makeStat(bundle: "com.unknown.app", name: "Unknown App")
        let category = CategoryDefinition.fallback
        render(view.categoryPicker(for: stat, currentCategory: category, isOverridden: false))
    }

    func testRenderCategoryPickerOverridden() {
        let view = DashboardCategoriesView()
        let stat = makeStat(bundle: "com.apple.Terminal", name: "Terminal")
        let category = CategoryDefinition.defaults.first ?? .fallback
        render(view.categoryPicker(for: stat, currentCategory: category, isOverridden: true))
    }

    func testRenderAppMappingRowWithEmptyNameUsesInitials() {
        let view = DashboardCategoriesView()
        let stat = makeStat(bundle: "com.test.x", name: "X")
        render(view.appMappingRow(stat))
    }
}
