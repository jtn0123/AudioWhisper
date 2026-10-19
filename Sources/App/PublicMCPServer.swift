import Foundation

enum MCPRequestID: Hashable {
    case string(String), number(Int64)
    init?(_ value: Any?) {
        if let string = value as? String, string.count <= 256 {
            self = .string(string)
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue.isFinite, abs(number.doubleValue) <= 9_007_199_254_740_991,
                number.doubleValue.rounded() == number.doubleValue { self = .number(number.int64Value) } else { return nil }
    }
    var json: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        }
    }
}

/// Bounded MCP 2025 stdio server. Transport remains responsive while one local
/// inference runs. No network listener, recording, clipboard or installation tools.
@MainActor
final class PublicMCPServer {
    typealias Transcribe = (String, UUID?, URL) async throws -> PublicTranscription
    private let directory: URL
    private let write: (Data) -> Void
    private let transcribe: Transcribe
    private let status: () async throws -> Data
    private var negotiated = false
    private var initialized = false
    private var requests: [MCPRequestID: Task<Void, Never>] = [:]
    private var inference: MCPRequestID?

    init(directory: URL, write: @escaping (Data) -> Void,
         transcribe: @escaping Transcribe = { try await PublicAutomation.transcribe(path: $0, modeID: $1, allowedDirectory: $2) },
         status: @escaping () async throws -> Data = { try JSONEncoder().encode(await RebuildDiagnostics.snapshot()) }) {
        self.directory = directory
        self.write = write
        self.transcribe = transcribe
        self.status = status
    }

    func receive(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line), let message = object as? [String: Any] else {
            failure(nil, -32700, "Parse error"); return
        }
        let id = MCPRequestID(message["id"])
        guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String,
              message["id"] == nil || id != nil else { failure(id, -32600, "Invalid request"); return }
        guard message["params"] == nil || message["params"] is [String: Any] else {
            failure(id, -32602, "Parameters must be an object"); return
        }
        let params = message["params"] as? [String: Any] ?? [:]
        if id == nil {
            if method == "notifications/initialized", negotiated { initialized = true }
            if method == "notifications/cancelled", let request = MCPRequestID(params["requestId"]) {
                requests[request]?.cancel()
            }
            return
        }
        guard let id else { return }
        if requests[id] != nil { failure(id, -32600, "Request ID is already active"); return }
        switch method {
        case "initialize": initialize(id, params: params)
        case "ping": result(id, [:])
        default:
            guard initialized else { failure(id, -32002, "Initialize the connection first"); return }
            if method == "tools/list" {
                result(id, ["tools": Self.tools])
            } else if method == "tools/call" {
                call(id, params: params)
            } else { failure(id, -32601, "Method not found") }
        }
    }

    private func initialize(_ id: MCPRequestID, params: [String: Any]) {
        guard !negotiated, let requested = params["protocolVersion"] as? String,
              params["capabilities"] is [String: Any], params["clientInfo"] is [String: Any] else {
            failure(id, -32602, "Invalid initialization parameters"); return
        }
        negotiated = true
        let supported = ["2025-11-25", "2025-06-18", "2025-03-26"]
        result(id, ["protocolVersion": supported.contains(requested) ? requested : "2025-11-25",
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "audiowhisper", "version": VersionInfo.version]])
    }

    private func call(_ id: MCPRequestID, params: [String: Any]) {
        guard let name = params["name"] as? String,
              let arguments = params["arguments"] as? [String: Any] ?? (params["arguments"] == nil ? [:] : nil) else {
            failure(id, -32602, "Invalid tool parameters"); return
        }
        if name == "status", arguments.isEmpty { start(id) { try await self.status() }; return }
        guard name == "transcribe_file" else { failure(id, -32602, "Unknown tool or invalid arguments"); return }
        guard inference == nil else { toolError(id, "Local transcription is busy. Retry after it finishes."); return }
        guard let path = arguments["path"] as? String, Set(arguments.keys).isSubset(of: ["path", "modeID"]),
              arguments["modeID"] == nil || (arguments["modeID"] as? String).flatMap(UUID.init(uuidString:)) != nil else {
            failure(id, -32602, "Use path and an optional saved modeID UUID"); return
        }
        inference = id
        let mode = (arguments["modeID"] as? String).flatMap(UUID.init(uuidString:))
        start(id) { try JSONEncoder().encode(await self.transcribe(path, mode, self.directory)) }
    }

    private func start(_ id: MCPRequestID, work: @escaping () async throws -> Data) {
        requests[id] = Task { [weak self] in
            guard let self else { return }
            defer { requests.removeValue(forKey: id); if inference == id { inference = nil } }
            do {
                let data = try await work()
                guard !Task.isCancelled else { return }
                result(id, ["content": [["type": "text", "text": String(data: data, encoding: .utf8) ?? ""]], "isError": false])
            } catch {
                guard !Task.isCancelled else { return }
                toolError(id, error.localizedDescription)
            }
        }
    }

    func shutdown() async {
        let active = Array(requests.values)
        active.forEach { $0.cancel() }
        for task in active { await task.value }
    }
    func oversized() async { failure(nil, -32600, "Message exceeds 1 MB"); await shutdown() }
    private func result(_ id: MCPRequestID, _ value: [String: Any]) { send(["jsonrpc": "2.0", "id": id.json, "result": value]) }
    private func failure(_ id: MCPRequestID?, _ code: Int, _ message: String) {
        send(["jsonrpc": "2.0", "id": id?.json ?? NSNull(), "error": ["code": code, "message": message]])
    }
    private func toolError(_ id: MCPRequestID, _ message: String) {
        result(id, ["content": [["type": "text", "text": message]], "isError": true])
    }
    private func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else { return }
        data.append(0x0a)
        write(data)
    }

    static let tools: [[String: Any]] = [
        ["name": "status", "description": "Report local model and permission readiness; requests no permissions.",
         "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
         "annotations": ["readOnlyHint": true, "idempotentHint": true, "openWorldHint": false]],
        ["name": "transcribe_file", "description": "Transcribe an audio file inside the configured allowed directory. "
            + "Installed local models only. No microphone, context, history, clipboard or paste effects.",
         "inputSchema": ["type": "object", "properties": ["path": ["type": "string"], "modeID": ["type": "string"]],
                         "required": ["path"], "additionalProperties": false],
         "annotations": ["readOnlyHint": true, "idempotentHint": true, "openWorldHint": false]]
    ]
}

enum PublicMCPTransport {
    /// Blocking reads run off the main actor; messages are bounded and passed
    /// across as Data. EOF cancels work rather than keeping a hidden process alive.
    static func run(_ server: PublicMCPServer) async {
        await Task.detached {
            var pending = Data()
            do {
                while let chunk = try FileHandle.standardInput.read(upToCount: 4_096), !chunk.isEmpty {
                    pending.append(chunk)
                    while let end = pending.firstIndex(of: 0x0a) {
                        guard end <= 1_048_576 else { await server.oversized(); return }
                        let line = Data(pending[..<end])
                        pending.removeSubrange(...end)
                        await server.receive(line)
                    }
                    guard pending.count <= 1_048_576 else { await server.oversized(); return }
                }
                if !pending.isEmpty { await server.receive(pending) }
            } catch { /* stdin closed; no content or credentials are logged. */ }
            await server.shutdown()
        }.value
    }
}
