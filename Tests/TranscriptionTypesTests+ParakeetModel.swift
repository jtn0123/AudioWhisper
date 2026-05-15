import XCTest
import Foundation
@testable import AudioWhisper

// ParakeetModel tests, split out of TranscriptionTypesTests to keep each type
// within SwiftLint's body-length limits.
extension TranscriptionTypesTests {
    func testParakeetModelCases() {
        let allCases = ParakeetModel.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.v2English))
        XCTAssertTrue(allCases.contains(.v3Multilingual))
    }

    func testParakeetModelDisplayNames() {
        XCTAssertEqual(ParakeetModel.v2English.displayName, "v2 English (~2.5 GB)")
        XCTAssertEqual(ParakeetModel.v3Multilingual.displayName, "v3 Multilingual (~2.5 GB)")
    }

    func testParakeetModelDescriptions() {
        XCTAssertEqual(ParakeetModel.v2English.description, "English only, original model")
        XCTAssertEqual(ParakeetModel.v3Multilingual.description, "25 languages, auto-detection")
    }

    func testParakeetModelRawValues() {
        XCTAssertEqual(ParakeetModel.v2English.rawValue, "mlx-community/parakeet-tdt-0.6b-v2")
        XCTAssertEqual(ParakeetModel.v3Multilingual.rawValue, "mlx-community/parakeet-tdt-0.6b-v3")
    }

    func testParakeetModelRepoId() {
        XCTAssertEqual(ParakeetModel.v2English.repoId, "mlx-community/parakeet-tdt-0.6b-v2")
        XCTAssertEqual(ParakeetModel.v3Multilingual.repoId, "mlx-community/parakeet-tdt-0.6b-v3")
    }

    func testParakeetModelFromRawValue() {
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
