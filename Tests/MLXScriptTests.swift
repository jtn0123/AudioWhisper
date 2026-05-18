import XCTest

final class MLXScriptTests: XCTestCase {
    private func scriptSource() throws -> String {
        let scriptURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // drop file name
            .deletingLastPathComponent() // drop Tests directory
            .appendingPathComponent("Sources/mlx_semantic_correct.py")
        return try String(contentsOf: scriptURL)
    }

    func testMaxTokensLimit() throws {
        let content = try scriptSource()
        XCTAssertTrue(content.contains("min(4096"), "Script should cap generation at 4096 tokens")
    }

    /// Audit #28: the offline-load failure path must not use `return print(...)`
    /// — `print` returns None and `sys.exit(None)` exits 0, masking failure.
    func testOfflineLoadFailureDoesNotReturnPrint() throws {
        let content = try scriptSource()
        XCTAssertFalse(
            content.contains("return print("),
            "`return print(...)` returns None -> sys.exit(0); failure paths must return a non-zero int"
        )
        // The offline-failure branch must end with an explicit non-zero return.
        XCTAssertTrue(
            content.contains("MLX model not available offline"),
            "Offline-failure message should still be emitted"
        )
        XCTAssertTrue(content.contains("return 5"), "Offline-failure path must return a non-zero code")
    }

    /// Audit #40: the script must emit a structured marker for a genuine
    /// missing-dependency case so callers can key off it precisely.
    func testEmitsStructuredDependencyMissingMarker() throws {
        let content = try scriptSource()
        XCTAssertTrue(
            content.contains("dependency_missing"),
            "Script should emit a structured error_kind for the missing-mlx-lm case"
        )
    }
}
