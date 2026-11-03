import SwiftUI
import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildDiagnosticHistoryTests: IsolatedXCTestCase {
    override func setUp() {
        super.setUp()
        DiagnosticController.enabled = true
        DiagnosticController.detailed = false
    }

    override func tearDown() {
        AppDefaults.defaults.removeObject(forKey: "diagnostics.historyEnabled")
        AppDefaults.defaults.removeObject(forKey: "diagnostics.resourceSampling")
        super.tearDown()
    }

    private func record() -> DiagnosticRecord {
        .init(id: UUID(), started: Date(), finished: Date(), build: "fixture", system: "fixture", architecture: "arm64",
              entry: .recording, provider: "local", voiceModel: "base", preferredInput: false,
              outcome: .completed, delivery: .copied,
              spans: DiagnosticStage.allCases.map { .init(stage: $0, milliseconds: 42, outcome: .completed) }, resources: [])
    }

    func testCollectionOffDisablesSamplingAndActuallyStopsNewSessions() throws {
        DiagnosticController.enabled = true
        DiagnosticController.detailed = false
        let controller = DiagnosticController(store: DiagnosticStore(file: nil))
        let state = RebuildDiagnosticHistoryState(controller: controller, destination: { nil })
        let view = RebuildDiagnosticHistoryView(state: state)
        try view.inspect().find(ViewType.Toggle.self, where: {
            try $0.labelView().text().string() == "Keep recent diagnostic history"
        }).tap()
        XCTAssertFalse(DiagnosticController.enabled)
        let updated = RebuildDiagnosticHistoryView(state: state)
        XCTAssertTrue(try updated.inspect().find(ViewType.Toggle.self, where: {
            try $0.labelView().text().string().hasPrefix("Sample application")
        }).isDisabled())
        XCTAssertNil(controller.start(.init(provider: .local, whisperModel: .base), id: UUID(), entry: .recording, mode: nil))
        DiagnosticController.enabled = true
        let enabled = RebuildDiagnosticHistoryView(state: state)
        try enabled.inspect().find(ViewType.Toggle.self, where: {
            try $0.labelView().text().string().hasPrefix("Sample application")
        }).tap()
        XCTAssertTrue(DiagnosticController.detailed)
    }

    func testRetainedStageTimingsAndSafetyExplanationAreVisible() async throws {
        let store = DiagnosticStore(file: nil)
        await store.append(record())
        let state = RebuildDiagnosticHistoryState(controller: DiagnosticController(store: store), destination: { nil })
        await state.refresh()
        let view = RebuildDiagnosticHistoryView(state: state)
        _ = try view.inspect().find(text: "1 sessions · 0 failed · 0 window events")
        for stage in DiagnosticStage.allCases { _ = try view.inspect().find(text: stage.label) }
        XCTAssertFalse(try view.inspect().find(button: "Export diagnostics…").isDisabled())
        _ = try view.inspect().find(text: "Completed stage timings · milliseconds")
        try view.inspect().find(button: "Refresh").tap()
        try view.inspect().find(button: "Done").tap()
    }

    func testExplicitExportWritesOnlyMetadataAndClearRefreshesTheSheet() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = DiagnosticStore(file: nil)
        await store.append(record())
        let state = RebuildDiagnosticHistoryState(controller: DiagnosticController(store: store), destination: { file })
        await state.export()
        let data = try Data(contentsOf: file)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schema"] as? Int, 1)
        let sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0]["text"])
        XCTAssertNil(sessions[0]["audioURL"])
        XCTAssertTrue(state.message?.contains("Review the file") == true)
        _ = try RebuildDiagnosticHistoryView(state: state).inspect().find(text: try XCTUnwrap(state.message))
        await state.clear()
        XCTAssertTrue(state.archive.sessions.isEmpty)
        XCTAssertFalse(state.storageFailed)
        XCTAssertEqual(state.message, "Diagnostic history cleared.")
    }

    func testExportCancellationPreservesTheArchive() async throws {
        let store = DiagnosticStore(file: nil)
        await store.append(record())
        var choices = 0
        let state = RebuildDiagnosticHistoryState(controller: DiagnosticController(store: store), destination: {
            choices += 1
            return nil
        })
        await state.export()
        await state.refresh()
        XCTAssertEqual(choices, 1)
        XCTAssertNil(state.message)
        XCTAssertEqual(state.archive.sessions.count, 1)
    }

    func testCorruptHistoryDisablesExportAndExplicitClearRecovers() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Data("corrupt archive must be preserved".utf8)
        try original.write(to: file)
        var choices = 0
        let state = RebuildDiagnosticHistoryState(controller: DiagnosticController(store: DiagnosticStore(file: file)),
            destination: { choices += 1; return nil })
        await state.refresh()
        XCTAssertTrue(state.storageFailed)
        XCTAssertTrue(try RebuildDiagnosticHistoryView(state: state).inspect().find(button: "Export diagnostics…").isDisabled())
        await state.export()
        XCTAssertEqual(choices, 0, "Do not open a save panel after a failed diagnostic read")
        XCTAssertEqual(state.message, "Could not export diagnostics.")
        XCTAssertEqual(try Data(contentsOf: file), original)
        await state.clear()
        XCTAssertFalse(state.storageFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testExportWriteFailureIsShownAndRetainedDataIsPreserved() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DiagnosticStore(file: nil)
        await store.append(record())
        let state = RebuildDiagnosticHistoryState(controller: DiagnosticController(store: store), destination: { folder })
        await state.export()
        XCTAssertEqual(state.message, "Could not export diagnostics.")
        await state.refresh()
        XCTAssertEqual(state.archive.sessions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }
}
