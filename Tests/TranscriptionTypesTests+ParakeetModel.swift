import XCTest
import Foundation
@testable import AudioWhisper

// ParakeetModel tests, split out of TranscriptionTypesTests to keep each type
// within SwiftLint's body-length limits.
extension TranscriptionTypesTests {
    func testParakeetModelCases() {
        let allCases = ParakeetModel.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.tdtCtc110mEnglish))
        XCTAssertTrue(allCases.contains(.v2English))
        XCTAssertTrue(allCases.contains(.v3Multilingual))

        // Picker order is smallest -> largest; assert it rather than relying on
        // declaration order staying put.
        XCTAssertEqual(allCases, [.tdtCtc110mEnglish, .v2English, .v3Multilingual])
    }

    func testParakeetModelDisplayNames() {
        XCTAssertEqual(ParakeetModel.tdtCtc110mEnglish.displayName, "110M English (~0.5 GB)")
        XCTAssertEqual(ParakeetModel.v2English.displayName, "v2 English (~2.5 GB)")
        XCTAssertEqual(ParakeetModel.v3Multilingual.displayName, "v3 Multilingual (~2.5 GB)")
    }

    func testParakeetModelDescriptions() {
        // Descriptions carry the published Open ASR Leaderboard WER, because the
        // picker previously implied v2 was merely "the original" when it is in
        // fact the most accurate English option.
        XCTAssertEqual(
            ParakeetModel.tdtCtc110mEnglish.description,
            "Lightest — 5× smaller, slightly less accurate (7.5% WER)"
        )
        XCTAssertEqual(ParakeetModel.v2English.description, "Most accurate for English (6.1% WER)")
        XCTAssertEqual(
            ParakeetModel.v3Multilingual.description,
            "25 languages with auto-detection (6.3% WER)"
        )
    }

    /// Every case must be loadable by `parakeet_mlx.from_pretrained`. Guard the
    /// repo ids so a future addition cannot silently point at a model published
    /// for the incompatible `mlx-audio` runtime.
    func testAllParakeetModelsAreMlxCommunityParakeetRepos() {
        for model in ParakeetModel.allCases {
            XCTAssertTrue(
                model.repoId.hasPrefix("mlx-community/parakeet"),
                "\(model) repo \(model.repoId) is not a parakeet-mlx-compatible repo"
            )
        }
    }

    func testParakeetModelRawValues() {
        XCTAssertEqual(ParakeetModel.tdtCtc110mEnglish.rawValue, "mlx-community/parakeet-tdt_ctc-110m")
        XCTAssertEqual(ParakeetModel.v2English.rawValue, "mlx-community/parakeet-tdt-0.6b-v2")
        XCTAssertEqual(ParakeetModel.v3Multilingual.rawValue, "mlx-community/parakeet-tdt-0.6b-v3")
    }

    func testParakeetModelRepoId() {
        XCTAssertEqual(ParakeetModel.tdtCtc110mEnglish.repoId, "mlx-community/parakeet-tdt_ctc-110m")
        XCTAssertEqual(ParakeetModel.v2English.repoId, "mlx-community/parakeet-tdt-0.6b-v2")
        XCTAssertEqual(ParakeetModel.v3Multilingual.repoId, "mlx-community/parakeet-tdt-0.6b-v3")
    }

    func testParakeetModelFromRawValue() {
        XCTAssertEqual(ParakeetModel(rawValue: "mlx-community/parakeet-tdt_ctc-110m"), .tdtCtc110mEnglish)
        XCTAssertEqual(ParakeetModel(rawValue: "mlx-community/parakeet-tdt-0.6b-v2"), .v2English)
        XCTAssertEqual(ParakeetModel(rawValue: "mlx-community/parakeet-tdt-0.6b-v3"), .v3Multilingual)
        XCTAssertNil(ParakeetModel(rawValue: "invalid"))
    }

    func testParakeetModelCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for model in ParakeetModel.allCases {
            let data = try encoder.encode(model)
            let decoded = try decoder.decode(ParakeetModel.self, from: data)
            XCTAssertEqual(decoded, model)
        }
    }

    func testParakeetModelRepoIdIsHuggingFaceFormat() {
        for model in ParakeetModel.allCases {
            let repoId = model.repoId
            // Hugging Face repo format: organization/model-name
            XCTAssertTrue(repoId.contains("/"), "Repo ID should contain /")
            let components = repoId.split(separator: "/")
            XCTAssertEqual(components.count, 2, "Repo ID should have exactly 2 components")
            XCTAssertEqual(String(components[0]), "mlx-community", "Should be from mlx-community")
            XCTAssertTrue(String(components[1]).contains("parakeet"), "Should be a parakeet model")
        }
    }

    func testParakeetModelDisplayNamesContainVersion() {
        XCTAssertTrue(ParakeetModel.v2English.displayName.contains("v2"))
        XCTAssertTrue(ParakeetModel.v3Multilingual.displayName.contains("v3"))
    }

    func testParakeetModelDisplayNamesContainLanguageInfo() {
        XCTAssertTrue(ParakeetModel.v2English.displayName.contains("English"))
        XCTAssertTrue(ParakeetModel.v3Multilingual.displayName.contains("Multilingual"))
    }

    func testParakeetModelDescriptionsAreDistinct() {
        let descriptions = ParakeetModel.allCases.map { $0.description }
        let uniqueDescriptions = Set(descriptions)
        XCTAssertEqual(descriptions.count, uniqueDescriptions.count)
    }
}
