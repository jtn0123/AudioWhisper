import Foundation

/// One structured event from the model-download subprocess.
///
/// Audit item B2. Download outcome used to be inferred by scanning the
/// subprocess's **stderr** for substrings — `"Fetching"`, `"Downloading"`,
/// `"%"`, `"it/s"`, `"MB/s"`, `"GB/s"` were treated as progress, and
/// `"no module"` / `"not found"` as errors. That is a heuristic over
/// `huggingface_hub`'s progress-bar format, which is not a stable contract:
/// when it changes, a genuine failure gets reclassified as progress and the
/// user watches a spinner that never resolves. The file sat at 8.3% coverage,
/// so nothing would have caught the flip.
///
/// The download script already prints newline-delimited JSON on **stdout** and
/// already exits non-zero on failure. This type makes that the only channel
/// that decides anything: stdout JSON drives the UI, the exit code decides
/// success, and stderr is diagnostics — logged, never interpreted.
internal enum MLXDownloadEvent: Equatable {
    /// Progress to display verbatim.
    case progress(String)
    /// The script reported a failure. The process is expected to exit non-zero
    /// too; this carries the human-readable reason.
    case failure(String)
    /// The script reported completion.
    case complete
    /// A line that carried no structured event — log it, do not interpret it.
    case unstructured(String)

    /// Parses a single line of the subprocess's stdout.
    ///
    /// Only well-formed JSON objects produce an actionable event. Anything else
    /// — a bare progress bar, a warning, a partial write — is `.unstructured`.
    /// There is deliberately no substring fallback: guessing at an unstructured
    /// line is what this item removed.
    static func parse(line: String) -> MLXDownloadEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unstructured("") }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unstructured(trimmed)
        }

        let message = (object["message"] as? String) ?? ""

        switch object["status"] as? String {
        case "error":
            // An error line with no message still has to read as an error.
            return .failure(message.isEmpty ? "Download failed" : message)
        case "complete":
            return .complete
        case "downloading":
            return .progress(message.isEmpty ? "Downloading model files..." : message)
        default:
            // A JSON object carrying a message but an unknown/absent status is
            // treated as progress — matching the prior behaviour, which keyed
            // only on `message` being present.
            return message.isEmpty ? .unstructured(trimmed) : .progress(message)
        }
    }

    /// The string to show the user, or `nil` when the event should not change
    /// what is displayed.
    var displayText: String? {
        switch self {
        case .progress(let message): return message
        case .failure(let message): return "Error: \(message)"
        case .complete, .unstructured: return nil
        }
    }
}
