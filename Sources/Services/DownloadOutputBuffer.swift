import Foundation

/// Pipe reads may split JSON, UTF-8 characters, or several events at once.
final class DownloadOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var failure: String?

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = String(bytes: pending[..<newline], encoding: .utf8) ?? ""
            pending.removeSubrange(...newline)
            lines.append(line)
            if case .failure(let message) = MLXDownloadEvent.parse(line: line) { failure = message }
        }
        return lines
    }

    var error: String? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }
}
