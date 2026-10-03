import XCTest
@testable import AudioWhisper

/// Tests for the model-download event parser.
///
/// Audit item B2: download outcome used to be inferred by substring-scanning
/// the subprocess's stderr against `huggingface_hub`'s progress-bar format —
/// an unstable contract we do not own. `MLXModelManager+Downloads` sat at 8.3%
/// coverage, so a format change that flipped a genuine failure into "progress"
/// (spinner forever) would have shipped unnoticed.
final class MLXDownloadEventTests: XCTestCase {

    // MARK: - Structured events

    func testDownloadingStatusIsProgress() {
        let event = MLXDownloadEvent.parse(
            line: #"{"status": "downloading", "message": "Downloading model files..."}"#
        )
        XCTAssertEqual(event, .progress("Downloading model files..."))
        XCTAssertEqual(event.displayText, "Downloading model files...")
    }

    func testCompleteStatusIsComplete() {
        let event = MLXDownloadEvent.parse(
            line: #"{"status": "complete", "message": "Download complete"}"#
        )
        XCTAssertEqual(event, .complete)
        XCTAssertNil(event.displayText, "completion is signalled by exit code, not by progress text")
    }

    func testErrorStatusIsFailureAndIsPrefixedForDisplay() {
        let event = MLXDownloadEvent.parse(
            line: #"{"status": "error", "message": "huggingface_hub not installed"}"#
        )
        XCTAssertEqual(event, .failure("huggingface_hub not installed"))
        XCTAssertEqual(event.displayText, "Error: huggingface_hub not installed")
    }

    /// An error line that arrives without a message still has to read as an
    /// error rather than an empty progress string.
    func testErrorStatusWithNoMessageStillReportsFailure() {
        let event = MLXDownloadEvent.parse(line: #"{"status": "error"}"#)
        XCTAssertEqual(event, .failure("Download failed"))
        XCTAssertEqual(event.displayText, "Error: Download failed")
    }

    /// Matches the prior behaviour, which keyed only on `message` being present.
    func testJSONWithAMessageButNoStatusIsTreatedAsProgress() {
        let event = MLXDownloadEvent.parse(line: #"{"message": "Resolving files"}"#)
        XCTAssertEqual(event, .progress("Resolving files"))
    }

    // MARK: - Unstructured input is never interpreted

    /// The core of B2. Every one of these previously tripped a substring rule.
    func testProgressBarNoiseIsNeverInterpreted() {
        let noise = [
            "model.safetensors:  47%|████      | 1.2G/2.5G [00:31<00:35, 38.1MB/s]",
            "Fetching 12 files:  8%|▊         | 1/12 [00:00<00:03,  3.02it/s]",
            "Downloading (…)of-00002.safetensors:  91%",
            "config.json: 100%|██████████| 1.42k/1.42k [00:00<00:00, 4.21MB/s]"
        ]
        for line in noise {
            let event = MLXDownloadEvent.parse(line: line)
            XCTAssertEqual(event, .unstructured(line), "must not interpret: \(line)")
            XCTAssertNil(event.displayText, "unstructured output must not move the UI: \(line)")
        }
    }

    /// The inverse failure mode: a traceback on stderr must not be able to set
    /// error state on its own. Only `{"status":"error"}` and the exit code do.
    func testTracebackTextIsUnstructuredNotAFailure() {
        let line = "Traceback (most recent call last): OSError: model not found"
        let event = MLXDownloadEvent.parse(line: line)
        XCTAssertEqual(event, .unstructured(line))
        XCTAssertNil(event.displayText)
    }

    /// A repo or filename containing "error" used to be enough to report a
    /// failed download.
    func testTheWordErrorInOrdinaryOutputDoesNotReportFailure() {
        let line = "Fetching mlx-community/error-correction-model: 40%"
        XCTAssertEqual(MLXDownloadEvent.parse(line: line), .unstructured(line))
    }

    func testMalformedJSONIsUnstructured() {
        // Truncated mid-write — a real possibility when a pipe read splits a line.
        let line = #"{"status": "downloading", "message""#
        XCTAssertEqual(MLXDownloadEvent.parse(line: line), .unstructured(line))
    }

    func testNonObjectJSONIsUnstructured() {
        XCTAssertEqual(MLXDownloadEvent.parse(line: "[1, 2, 3]"), .unstructured("[1, 2, 3]"))
    }

    // MARK: - Whitespace handling

    func testSurroundingWhitespaceIsTrimmedBeforeParsing() {
        let event = MLXDownloadEvent.parse(
            line: "   {\"status\": \"complete\", \"message\": \"Download complete\"}  \n"
        )
        XCTAssertEqual(event, .complete)
    }

    func testBlankLineIsUnstructuredAndEmpty() {
        XCTAssertEqual(MLXDownloadEvent.parse(line: "   \n  "), .unstructured(""))
        XCTAssertNil(MLXDownloadEvent.parse(line: "").displayText)
    }
}
