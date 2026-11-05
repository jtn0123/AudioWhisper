import Foundation
import WhisperKit
import XCTest
@testable import AudioWhisper

/// Tiny original models exercise real Core ML in normal CI, without
/// downloaded models. Speech recognition remains a separate nightly acceptance.
final class PreparedWhisperEncoderCoreMLTests: XCTestCase {
    func testRealCompilerPublishesAReusableEncoderWithoutChangingSources() async throws {
        let fixture = try CoreMLPreparationFixture(model: "encoder-shape")
        defer { fixture.remove() }
        let preparer = fixture.preparer()
        let first = try await preparer.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
        let compiled = try XCTUnwrap(first)
        try PreparedWhisperEncoder.validateModel(compiled, compute: .cpuOnly)
        let before = try FileManager.default.attributesOfItem(atPath: compiled.path)[.creationDate] as? Date
        let second = try await preparer.prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
        XCTAssertEqual(second, first)
        XCTAssertNotNil(before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: compiled.path)[.creationDate] as? Date, before)
        XCTAssertEqual(try ModelIntegrity.sha256(of: fixture.specification), fixture.recipe.specification)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.cache.path).count, 1)
    }

    func testRealCompilerRejectsWrongOutputShapeAndRemovesUnpublishedResources() async throws {
        let fixture = try CoreMLPreparationFixture(model: "wrong-shape")
        defer { fixture.remove() }
        do {
            _ = try await fixture.preparer().prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
            XCTFail("A loadable model with an incompatible output must not be published")
        } catch {
            XCTAssertEqual(error as? PreparedWhisperEncoder.PreparationError, .shape)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.cache.path), [])
        XCTAssertEqual(try ModelIntegrity.sha256(of: fixture.specification), fixture.recipe.specification)
    }

    func testRealCompilerFailureLeavesTheSourceAndNoPartialPreparedCache() async throws {
        let fixture = try CoreMLPreparationFixture(model: nil)
        defer { fixture.remove() }
        do {
            _ = try await fixture.preparer().prepare(model: .base, folder: fixture.folder, compute: .cpuOnly)
            XCTFail("An invalid model specification must fail compilation")
        } catch {
            XCTAssertFalse(error is PreparedWhisperEncoder.PreparationError,
                           "The original Core ML compiler failure must propagate")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.cache.path), [])
        XCTAssertEqual(try Data(contentsOf: fixture.specification), Data("invalid Core ML model".utf8))
    }

    func testFactoryFailsLocallyForMissingAssetsWithoutCreatingAModelDirectory() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: missing) }
        do {
            _ = try await WhisperEngineFactory.make(model: .base, folder: missing.path)
            XCTFail("The installed-assets factory must not replace missing assets with downloads")
        } catch let WhisperError.modelsUnavailable(message) {
            XCTAssertTrue(message.contains(missing.path))
        } catch { XCTFail("Expected the local missing-model error, got \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }
}

private struct CoreMLPreparationFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recipe: PreparedWhisperEncoder.Recipe
    var folder: URL { root.appendingPathComponent("upstream") }
    var specification: URL { folder.appendingPathComponent("AudioEncoder.mlmodelc/model.mlmodel") }
    var cache: URL { root.appendingPathComponent("prepared") }

    init(model: String?) throws {
        let original = root.appendingPathComponent("upstream/AudioEncoder.mlmodelc")
        try FileManager.default.createDirectory(at: original.appendingPathComponent("weights"),
                                                withIntermediateDirectories: true)
        try Data("synthetic fixture".utf8).write(to: original.appendingPathComponent("model.mil"))
        try Data().write(to: original.appendingPathComponent("weights/weight.bin"))
        let specification = original.appendingPathComponent("model.mlmodel")
        if let model {
            let source = try XCTUnwrap(Bundle.module.url(forResource: model, withExtension: "mlmodel",
                                                        subdirectory: "Resources/CoreMLFixtures"))
            try FileManager.default.copyItem(at: source, to: specification)
        } else {
            try Data("invalid Core ML model".utf8).write(to: specification)
        }
        recipe = try .init(mil: ModelIntegrity.sha256(of: original.appendingPathComponent("model.mil")),
                           specification: ModelIntegrity.sha256(of: specification),
                           weights: ModelIntegrity.sha256(of: original.appendingPathComponent("weights/weight.bin")))
    }

    func preparer() -> PreparedWhisperEncoder {
        .init(root: cache, environment: .init(major: 15, appleSilicon: true, build: "synthetic-contract-fixture"),
              recipe: recipe)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
