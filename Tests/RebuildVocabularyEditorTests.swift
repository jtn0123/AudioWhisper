import XCTest
import ViewInspector
@testable import AudioWhisper

@MainActor
final class RebuildVocabularyEditorTests: IsolatedXCTestCase {
    func testAddEditSearchRemoveAndUndoThroughTheEditor() throws {
        AppDefaults.customVocabulary = "# Keep this comment\nKubernetes"
        let state = RebuildVocabularyEditorState()
        state.draft.written = "AudioWhisper"
        try RebuildVocabularyEditor(state: state).inspect().find(button: "Add entry").tap()
        XCTAssertEqual(CustomVocabulary(parsing: AppDefaults.customVocabulary).terms, ["Kubernetes", "AudioWhisper"])
        XCTAssertFalse(state.isError)
        state.query = "audiowhisper"
        let entry = try XCTUnwrap(RebuildVocabularyDocument(source: AppDefaults.customVocabulary).matching(state.query).first)
        state.edit(entry)
        state.draft.written = "AudioWhisper Rebuild"
        try RebuildVocabularyEditor(state: state).inspect().find(button: "Save changes").tap()
        XCTAssertTrue(AppDefaults.customVocabulary.contains("AudioWhisper Rebuild"))
        XCTAssertEqual(state.query, "")
        let updatedEntry = try XCTUnwrap(RebuildVocabularyDocument(source: AppDefaults.customVocabulary).entries.last)
        AppDefaults.customVocabulary = try XCTUnwrap(state.remove(updatedEntry, in: AppDefaults.customVocabulary))
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(AppDefaults.customVocabulary.contains("AudioWhisper"))
        try RebuildVocabularyEditor(state: state).inspect().find(button: "Undo remove").tap()
        XCTAssertTrue(AppDefaults.customVocabulary.contains("AudioWhisper Rebuild"))
        XCTAssertTrue(AppDefaults.customVocabulary.hasPrefix("# Keep this comment"))
        XCTAssertFalse(state.canUndo)
    }

    func testValidationAndUndoNeverOverwriteNewerChanges() throws {
        let state = RebuildVocabularyEditorState()
        XCTAssertNil(state.save(in: "Existing"))
        XCTAssertTrue(state.isError)
        state.draft.written = "existing"
        XCTAssertNil(state.save(in: "Existing"))
        let entry = try XCTUnwrap(RebuildVocabularyDocument(source: "Existing").entries.first)
        XCTAssertEqual(state.remove(entry, in: "Existing"), "")
        XCTAssertNil(state.undo(in: "Added elsewhere"))
        XCTAssertTrue(state.isError)
        XCTAssertEqual(state.undo(in: ""), "Existing")
        state.edit(entry)
        state.cancelEdit()
        XCTAssertNil(state.draft.entry)
        XCTAssertNil(state.message)
        XCTAssertNil(state.remove(entry, in: "Changed elsewhere"))
    }

    func testCorrectionSheetSavesOnlyTheExplicitReplacement() throws {
        AppDefaults.customVocabulary = "Kubernetes"
        let draft = RebuildVocabularyDocument.correction(from: "I use post gress.", to: "I use Postgres.")
        var saved = 0
        let view = RebuildRememberCorrectionView(draft: draft, saved: { saved += 1 })
        try view.inspect().find(button: "Save correction").tap()
        XCTAssertEqual(saved, 1)
        XCTAssertEqual(CustomVocabulary(parsing: AppDefaults.customVocabulary).apply(to: "I use post gress."), "I use Postgres.")
        XCTAssertEqual(CustomVocabulary(parsing: AppDefaults.customVocabulary).terms, ["Kubernetes"])
    }
}
