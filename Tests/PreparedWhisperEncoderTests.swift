import CoreML
import XCTest
@testable import AudioWhisper

final class PreparedWhisperEncoderTests: XCTestCase {
    func testPolicyIsLimitedToBaseOnAppleSiliconMacOS15() {
        let affected = PreparedWhisperEncoder.Environment(major: 15, appleSilicon: true, build: "15A")
        XCTAssertTrue(affected.applies(to: .base))
        for model in [WhisperModel.tiny, .small, .largeTurbo] { XCTAssertFalse(affected.applies(to: model)) }
        XCTAssertFalse(PreparedWhisperEncoder.Environment(major: 26, appleSilicon: true, build: "26A").applies(to: .base))
        XCTAssertFalse(PreparedWhisperEncoder.Environment(major: 15, appleSilicon: false, build: "15A").applies(to: .base))
    }

    func testSameSourceCoalescesPreparationAndReusesValidatedCache() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let count = CompileCounter()
        let prepare = fixture.preparer { package in
            await count.increment()
            let manifestData = try Data(contentsOf: package.appendingPathComponent("Manifest.json"))
            let manifest = try JSONSerialization.jsonObject(with: manifestData)
            XCTAssertNotNil((manifest as? [String: Any])?["rootModelIdentifier"])
            let weights = package.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin")
            XCTAssertEqual(try Data(contentsOf: weights), Data("weights".utf8))
            return try fixture.compiled()
        }
        async let first = prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuAndNeuralEngine)
        async let second = prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuAndNeuralEngine)
        let results = try await (first, second)
        XCTAssertEqual(results.0, results.1)
        let cached = try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuAndNeuralEngine)
        XCTAssertEqual(cached, results.0)
        let calls = await count.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.original.appendingPathComponent("model.mil")), Data("mil".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.cache.path).count, 1)
    }

    func testBuildAndComputePolicyInvalidatePreparedCache() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let count = CompileCounter()
        let compile: PreparedWhisperEncoder.Compile = { _ in await count.increment(); return try fixture.compiled() }
        let prepare = fixture.preparer(compile: compile)
        let first = try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
        let second = try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuAndNeuralEngine)
        let updated = fixture.preparer(build: "15B", compile: compile)
        let third = try await updated.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, third)
        let calls = await count.value
        XCTAssertEqual(calls, 3)
    }

    func testUnknownArtifactIsUntouchedAndChangedKnownSourcesFailClearly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prepare = fixture.preparer { _ in XCTFail("Must not compile unknown or damaged sources"); return fixture.folder }
        try Data("other".utf8).write(to: fixture.original.appendingPathComponent("model.mil"))
        let unknown = try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
        XCTAssertNil(unknown)
        try Data("mil".utf8).write(to: fixture.original.appendingPathComponent("model.mil"))
        try Data("changed".utf8).write(to: fixture.original.appendingPathComponent("weights/weight.bin"))
        do {
            _ = try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
            XCTFail("Recognized affected artifacts must not fall back to their failing encoder")
        } catch { XCTAssertEqual(error as? PreparedWhisperEncoder.PreparationError, .source) }
    }

    func testPackageOnlyInstallationKeepsTheSdkPath() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prepare = fixture.preparer { _ in XCTFail("A package-only encoder is outside the allowlist"); return fixture.folder }
        try FileManager.default.removeItem(at: fixture.original)
        try FileManager.default.createDirectory(at: fixture.folder.appendingPathComponent("AudioEncoder.mlpackage"),
                                                withIntermediateDirectories: true)
        let prepared = try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuAndNeuralEngine)
        XCTAssertNil(prepared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.path))
    }

    func testCorruptDerivedCacheRebuildsOnceAndCompileFailureCanRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let count = CompileCounter()
        let prepare = fixture.preparer { _ in await count.increment(); return try fixture.compiled() }
        let prepared = try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
        let first = try XCTUnwrap(prepared)
        try Data("bad".utf8).write(to: first.appendingPathComponent("valid"))
        let rebuilt = try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
        XCTAssertEqual(rebuilt, first)
        let calls = await count.value
        XCTAssertEqual(calls, 2)
        let failing = fixture.preparer(build: "15B") { _ in throw CocoaError(.fileWriteOutOfSpace) }
        do {
            _ = try await failing.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
            XCTFail("Compilation failures must propagate")
        } catch { XCTAssertEqual((error as? CocoaError)?.code, .fileWriteOutOfSpace) }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: fixture.cache.path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix("staging-") })
        let retried = try await fixture.preparer(build: "15B", compile: { _ in try fixture.compiled() })
            .prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
        XCTAssertNotNil(retried)
    }

    func testCancelledWaiterDrainsSharedPreparationWithoutDiscardingAnotherCallersResult() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let started = expectation(description: "Preparation entered its compiler")
        let gate = PreparationGate(started: started)
        let prepare = fixture.preparer { _ in
            await gate.wait()
            return try fixture.compiled()
        }
        let cancelled = Task { try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly) }
        await fulfillment(of: [started], timeout: 5)
        let survivor = Task { try await prepare.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly) }
        cancelled.cancel()
        await gate.open()
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled caller must not receive an engine")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        let result = try await survivor.value
        XCTAssertNotNil(result)
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.cache.path)
        XCTAssertEqual(files.count, 1, "Shared preparation must publish one model and close its staging resources")
    }

    private struct Fixture: Sendable {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recipe: PreparedWhisperEncoder.Recipe
        var folder: URL { root.appendingPathComponent("upstream") }
        var original: URL { folder.appendingPathComponent("AudioEncoder.mlmodelc") }
        var cache: URL { root.appendingPathComponent("prepared") }

        init() throws {
            let original = root.appendingPathComponent("upstream/AudioEncoder.mlmodelc")
            let weights = original.appendingPathComponent("weights")
            try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
            for (name, value) in [("model.mil", "mil"), ("model.mlmodel", "spec"), ("weights/weight.bin", "weights")] {
                try Data(value.utf8).write(to: original.appendingPathComponent(name))
            }
            recipe = try .init(mil: ModelIntegrity.sha256(of: original.appendingPathComponent("model.mil")),
                specification: ModelIntegrity.sha256(of: original.appendingPathComponent("model.mlmodel")),
                weights: ModelIntegrity.sha256(of: original.appendingPathComponent("weights/weight.bin")))
        }

        func preparer(build: String = "15A", compile: @escaping PreparedWhisperEncoder.Compile) -> PreparedWhisperEncoder {
            .init(root: cache, environment: .init(major: 15, appleSilicon: true, build: build), recipe: recipe,
                  compile: compile, validate: { url, _ in
                      guard try Data(contentsOf: url.appendingPathComponent("valid")) == Data("yes".utf8) else {
                          throw CocoaError(.coderInvalidValue)
                      }
                  })
        }

        func compiled() throws -> URL {
            let url = root.appendingPathComponent("compiled-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("yes".utf8).write(to: url.appendingPathComponent("valid"))
            return url
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

private actor CompileCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor PreparationGate {
    let started: XCTestExpectation
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(started: XCTestExpectation) { self.started = started }
    func wait() async {
        started.fulfill()
        guard !opened else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}
