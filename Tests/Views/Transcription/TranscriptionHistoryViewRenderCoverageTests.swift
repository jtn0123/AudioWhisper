import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import AudioWhisper

/// Renders TranscriptionHistoryView to exercise its body across empty and
/// populated states.
@MainActor
final class TranscriptionHistoryViewRenderCoverageTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func render() {
        let view = TranscriptionHistoryView().modelContainer(container)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    func testRendersEmptyState() {
        render()
    }

    func testRendersWithRecords() throws {
        for index in 0..<3 {
            let record = TranscriptionRecord(
                text: "Sample transcription number \(index)",
                provider: index.isMultiple(of: 2) ? .local : .parakeet,
                duration: Double(index) + 5.0,
                modelUsed: "base"
            )
            context.insert(record)
        }
        try context.save()
        render()
    }

    func testRendersAfterAllowingTaskToLoad() async throws {
        let record = TranscriptionRecord(
            text: "Loaded record",
            provider: .local,
            duration: 8.0
        )
        context.insert(record)
        try context.save()

        let view = TranscriptionHistoryView().modelContainer(container)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
        // Let the `.task` modifier run loadRecords.
        try? await Task.sleep(for: .milliseconds(150))
        host.layout()
    }
}
