import SwiftData
import XCTest
@testable import AudioWhisper

@MainActor
final class HistoryExporterTests: XCTestCase {
    func testExportsMultiplePagesWithoutChangingExistingText() async throws {
        try await exerciseExport(cancel: false)
    }

    func testCancellationPreservesExistingFileAndRemovesPartialExport() async throws {
        try await exerciseExport(cancel: true)
    }

    private func exerciseExport(cancel: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: TranscriptionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        for index in 0..<1001 {
            context.insert(TranscriptionRecord(
                text: "Saved transcript \(index)", provider: .local, modelUsed: nil,
                wordCount: 3, characterCount: 20))
        }
        try context.save()
        let target = directory.appendingPathComponent("export.txt")
        try "existing file".write(to: target, atomically: true, encoding: .utf8)
        var pages: [Int] = []
        let exporting = Task {
            try await HistoryExporter.export(container: container, to: target) { count in
                await MainActor.run { pages.append(count) }
                if cancel { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        if cancel {
            for _ in 0..<200 where pages.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(pages, [500])
            exporting.cancel()
            do { _ = try await exporting.value; XCTFail("Expected cancellation") } catch is CancellationError {}
            XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "existing file")
        } else {
            let count = try await exporting.value
            XCTAssertEqual(count, 1001)
            XCTAssertEqual(pages, [500, 1000, 1001])
            let output = try String(contentsOf: target, encoding: .utf8)
            XCTAssertEqual(output.components(separatedBy: "\n\n---\n\n").count, 1001)
            XCTAssertTrue(output.contains("Saved transcript 1000"))
            XCTAssertTrue(output.contains("Saved transcript 0"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["export.txt"])
    }
}
