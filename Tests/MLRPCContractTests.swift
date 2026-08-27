import XCTest
@testable import AudioWhisper

/// Runs the real `ml_daemon.py` and checks that it and `MLRPCProtocol.swift`
/// still describe the same wire format.
///
/// This is the gap neither language's type system can close. `MLRPCProtocol`
/// makes the Swift side internally consistent and `Sources/ml/protocol.py` does
/// the same for Python, but nothing relates the two: renaming `pcm_path` on
/// either side compiles clean, type-checks clean, and fails only in a
/// subprocess at runtime — as a 60-second timeout, because the daemon replies
/// with an error the caller was not expecting.
///
/// So the assertions here deliberately use the PRODUCTION encoder and decoder.
/// A fixture string hand-written in this file would drift with the code it is
/// meant to police; `JSONEncoder().encode(MLRPCRequest(...))` cannot.
///
/// No models and no venv: every mlx/parakeet import in `Sources/ml` is lazy, so
/// the daemon boots on stock `python3` and answers `ping` in milliseconds. The
/// model-dependent methods fail at their import — which is itself the signal
/// this test wants, because reaching the import means the parameters were
/// accepted.
final class MLRPCContractTests: XCTestCase {

    // MARK: - Harness

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
    }

    private func pythonExecutable() throws -> URL {
        let candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("no system python3 available to run the daemon contract check")
        }
        return URL(fileURLWithPath: found)
    }

    /// Feeds `requests` to one daemon process and returns its replies, decoded
    /// with the production envelope type.
    ///
    /// stdin is closed after writing, which ends the daemon's `for line in
    /// sys.stdin` loop, so the process exits on its own.
    ///
    /// The reply count is asserted HERE rather than in each test. The first
    /// version of this file left it to the callers, and when an import error
    /// stopped the daemon booting at all, the tests that zip replies against
    /// expectations passed vacuously — `zip` over an empty array iterates zero
    /// times and asserts nothing. A silent no-op is the one outcome a contract
    /// test must never have.
    @discardableResult
    private func exchange(
        _ requests: [Data],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [MLRPCEnvelope] {
        let root = repoRoot()
        let process = Process()
        process.executableURL = try pythonExecutable()
        process.arguments = [root.appendingPathComponent("Sources/ml_daemon.py").path]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = root.appendingPathComponent("Sources").path
        // Keep a stray user-level HF token or cache out of the run.
        environment["HF_HUB_OFFLINE"] = "1"
        process.environment = environment

        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout

        // stderr goes to a file, not a pipe: a traceback large enough to fill a
        // pipe buffer would block the daemon while this side waits on stdout.
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mlrpc-contract-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardError = stderrHandle
        addTeardownBlock { try? FileManager.default.removeItem(at: stderrURL) }

        try process.run()
        for request in requests {
            stdin.fileHandleForWriting.write(request)
            stdin.fileHandleForWriting.write(Data([0x0a]))
        }
        try stdin.fileHandleForWriting.close()

        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try? stderrHandle.close()
        let errorText = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        let lines = (String(bytes: out, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let envelopes = try lines.map { line in
            try JSONDecoder().decode(MLRPCEnvelope.self, from: Data(line.utf8))
        }

        XCTAssertEqual(
            envelopes.count, requests.count,
            """
            daemon answered \(envelopes.count) of \(requests.count) requests \
            (exit \(process.terminationStatus)). stderr:
            \(errorText.isEmpty ? "<empty>" : errorText)
            """,
            file: file, line: line
        )
        return envelopes
    }

    /// Encodes a request exactly as `MLDaemonManager` does.
    private func encode<Params: Encodable>(id: Int, method: MLRPCMethod, params: Params?) throws -> Data {
        try JSONEncoder().encode(MLRPCRequest(id: id, method: method, params: params))
    }

    private func message(_ envelope: MLRPCEnvelope) -> String {
        envelope.error?.message ?? ""
    }

    // MARK: - Round trip

    /// The one method that completes end-to-end without a model: production
    /// request type in, production result type out.
    func testPingRoundTripsThroughTheRealDaemon() throws {
        let request = try encode(id: 1, method: .ping, params: MLRPCParams.Empty?.none)

        let replies = try exchange([request])

        XCTAssertEqual(replies.count, 1)
        let reply = try XCTUnwrap(replies.first)
        XCTAssertEqual(reply.id, 1, "the daemon must echo the id the caller keys `pending` by")
        XCTAssertNil(reply.error, "ping should not error: \(message(reply))")

        let result = try XCTUnwrap(reply.result)
        let decoded = try JSONDecoder().decode(MLRPCResult.Ping.self, from: JSONEncoder().encode(result))
        XCTAssertTrue(decoded.pong)
    }

    // MARK: - Method names

    /// Every case of `MLRPCMethod` must be a method the daemon dispatches.
    ///
    /// This is the assertion that catches a rename on either side. The
    /// model-backed methods still fail here — no mlx installed — but they fail
    /// *inside* the handler, so the check is specifically that none of them
    /// comes back "Unknown method".
    func testEveryMethodIsRecognisedByTheDaemon() throws {
        let requests = try MLRPCMethod.allCases.enumerated().map { index, method in
            try encode(id: index + 1, method: method, params: paramsFor(method))
        }

        let replies = try exchange(requests)

        XCTAssertEqual(replies.count, MLRPCMethod.allCases.count)
        for (method, reply) in zip(MLRPCMethod.allCases, replies) {
            XCTAssertFalse(
                message(reply).contains("Unknown method"),
                "the daemon does not implement '\(method.rawValue)' — Swift and rpc.py disagree"
            )
        }
    }

    /// Minimal well-formed parameters per method, so each request reaches its
    /// handler rather than stopping at validation.
    private func paramsFor(_ method: MLRPCMethod) throws -> Data? {
        switch method {
        case .ping:
            return nil
        case .transcribe:
            return try JSONEncoder().encode(
                MLRPCParams.Transcribe(repo: "contract-test", pcmPath: "/nonexistent.pcm")
            )
        case .correct:
            return try JSONEncoder().encode(
                MLRPCParams.Correct(repo: "contract-test", text: "hi", prompt: nil)
            )
        case .warmup:
            return try JSONEncoder().encode(
                MLRPCParams.Warmup(type: .parakeet, repo: "contract-test")
            )
        }
    }

    /// Every `MLWarmupKind` raw value must be one the daemon accepts.
    ///
    /// `warmup` used to take a bare `String`, and the unit test asserted it was
    /// called with `"transcription"` — a value `rpc.py` has never accepted and
    /// answers with "Unknown warmup type". Nothing caught it, because the test
    /// stub did not validate and no test ran the daemon.
    func testEveryWarmupKindIsAcceptedByTheDaemon() throws {
        let requests = try MLWarmupKind.allCases.enumerated().map { index, kind in
            try encode(
                id: index + 1,
                method: .warmup,
                params: MLRPCParams.Warmup(type: kind, repo: "contract-test")
            )
        }

        let replies = try exchange(requests)

        for (kind, reply) in zip(MLWarmupKind.allCases, replies) {
            XCTAssertFalse(
                message(reply).contains("Unknown warmup type"),
                "the daemon rejects warmup type '\(kind.rawValue)': \(message(reply))"
            )
        }
    }

    // MARK: - Parameter keys

    /// The keys `MLRPCParams.Transcribe` encodes must be the keys `rpc.py`
    /// reads. `pcmPath` maps to `pcm_path` through a CodingKey, which is
    /// exactly the kind of mapping that silently rots.
    ///
    /// Reaching "PCM file not found" proves the daemon found and accepted both
    /// parameters; a rename would surface as "'pcm_path' must be a string".
    func testTranscribeParameterKeysMatchWhatTheDaemonReads() throws {
        let request = try encode(
            id: 1,
            method: .transcribe,
            params: MLRPCParams.Transcribe(repo: "contract-test", pcmPath: "/nonexistent-contract.pcm")
        )

        let reply = try XCTUnwrap(try exchange([request]).first)

        XCTAssertTrue(
            message(reply).contains("PCM file not found"),
            "expected the daemon to accept both params and fail on the missing file, got: \(message(reply))"
        )
        XCTAssertFalse(message(reply).contains("must be a string"),
                       "a parameter key did not survive encoding: \(message(reply))")
    }

    /// Same check for `correct`. Its parameters are accepted when the failure
    /// is the absent mlx-lm import rather than validation.
    func testCorrectParameterKeysMatchWhatTheDaemonReads() throws {
        let request = try encode(
            id: 1,
            method: .correct,
            params: MLRPCParams.Correct(repo: "contract-test", text: "hello", prompt: "Fix grammar")
        )

        let reply = try XCTUnwrap(try exchange([request]).first)

        XCTAssertFalse(message(reply).contains("must be a string"),
                       "a parameter key did not survive encoding: \(message(reply))")
        XCTAssertTrue(
            message(reply).contains("mlx-lm import failed") || message(reply).contains("not available offline"),
            "expected params to be accepted and the model load to be what fails, got: \(message(reply))"
        )
    }

    /// A nil prompt must leave the member out of the payload entirely, which is
    /// what the hand-built dictionary used to do. `optional_str` treats absent
    /// and null alike, so either encoding works — but the wire form is part of
    /// the contract, so it is pinned rather than assumed.
    func testNilPromptIsOmittedFromTheEncodedRequest() throws {
        let data = try JSONEncoder().encode(
            MLRPCParams.Correct(repo: "r", text: "t", prompt: nil)
        )
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertNil(decoded["prompt"], "a nil prompt must not appear on the wire")
        XCTAssertEqual(decoded["repo"], "r")
        XCTAssertEqual(decoded["text"], "t")
    }

    /// `ping` sends no `params` member at all.
    func testPingSendsNoParamsMember() throws {
        let data = try encode(id: 9, method: .ping, params: MLRPCParams.Empty?.none)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertNil(decoded["params"])
        XCTAssertEqual(decoded["jsonrpc"], "2.0")
        XCTAssertEqual(decoded["method"], "ping")
        XCTAssertEqual(decoded["id"], 9)
    }

    // MARK: - Error envelope

    /// An unparseable line comes back with `"id": null`, which the production
    /// envelope must decode rather than reject — `MLDaemonManager.handle(line:)`
    /// relies on the nil id to log and drop it instead of resuming a caller.
    func testMalformedLineYieldsAnEnvelopeWithNoID() throws {
        let reply = try XCTUnwrap(try exchange([Data("this is not json".utf8)]).first)

        XCTAssertNil(reply.id)
        XCTAssertTrue(message(reply).contains("Invalid JSON"), "got: \(message(reply))")
    }

    /// A method outside the enum is refused, and the refusal keeps the id so
    /// the waiting caller fails fast instead of timing out.
    func testUnknownMethodIsRefusedWithTheIDEchoed() throws {
        let raw = Data(#"{"jsonrpc":"2.0","id":42,"method":"definitely_not_a_method"}"#.utf8)

        let reply = try XCTUnwrap(try exchange([raw]).first)

        XCTAssertEqual(reply.id, 42)
        XCTAssertTrue(message(reply).contains("Unknown method"), "got: \(message(reply))")
    }

    /// The validation `protocol.py` added: a wrongly-typed parameter is named
    /// at the boundary. Previously `pcm_path: 123` passed the truthiness guard
    /// and reached `os.path.exists(123)`.
    func testWronglyTypedParameterIsNamedRatherThanFailingDeeper() throws {
        let raw = Data(#"{"jsonrpc":"2.0","id":7,"method":"transcribe","params":{"pcm_path":123}}"#.utf8)

        let reply = try XCTUnwrap(try exchange([raw]).first)

        XCTAssertEqual(reply.id, 7)
        XCTAssertTrue(message(reply).contains("'pcm_path' must be a string"), "got: \(message(reply))")
    }

    /// Several requests in flight come back in order, each keyed to its own id —
    /// the property `MLDaemonManager.pending` depends on.
    func testRepliesCarryTheIDOfTheirOwnRequest() throws {
        let requests = try (1...4).map { try encode(id: $0 * 10, method: .ping, params: MLRPCParams.Empty?.none) }

        let replies = try exchange(requests)

        XCTAssertEqual(replies.map(\.id), [10, 20, 30, 40])
    }
}
