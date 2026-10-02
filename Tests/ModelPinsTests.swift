import XCTest
@testable import AudioWhisper

/// `ModelPins` is only as good as its coverage of what the app actually offers:
/// a model added to the picker without a pin silently downloads `main` again.
@MainActor
final class ModelPinsTests: XCTestCase {

    func testEveryParakeetModelIsPinned() {
        for model in ParakeetModel.allCases {
            XCTAssertNotNil(ModelPins.revision(for: model.rawValue), "\(model.rawValue) has no pinned revision")
        }
    }

    func testEveryRecommendedCorrectionModelIsPinned() {
        for model in MLXModelManager.recommendedModels {
            XCTAssertNotNil(ModelPins.revision(for: model.repo), "\(model.repo) has no pinned revision")
        }
    }

    /// The default correction model is what a fresh install downloads first.
    func testTheDefaultCorrectionModelIsPinned() {
        XCTAssertNotNil(ModelPins.revision(for: AppDefaults.defaultSemanticCorrectionModelRepo))
    }

    /// A pin must be a full commit hash. A branch or tag name would move, which
    /// is the thing pinning exists to stop; and `isModelCachedOnDisk` rejects a
    /// `refs/main` that is not pure hex, so a short or malformed pin would make
    /// a freshly downloaded model look absent.
    func testEveryPinIsAFullLowercaseCommitHash() {
        for (repo, revision) in ModelPins.revisions {
            XCTAssertEqual(revision.count, 40, "\(repo): pin must be a full 40-character commit")
            XCTAssertTrue(revision.allSatisfy { $0.isHexDigit && !$0.isUppercase },
                          "\(repo): pin must be lowercase hex")
        }
    }

    /// Nothing outside the offered set: a stale pin for a removed model is dead
    /// weight that the next person has to reason about.
    func testNoPinsForModelsTheAppDoesNotOffer() {
        let offered = Set(ParakeetModel.allCases.map(\.rawValue))
            .union(MLXModelManager.recommendedModels.map(\.repo))
        XCTAssertEqual(Set(ModelPins.revisions.keys).subtracting(offered), [])
    }

    func testScriptArgumentsCarryThePinOnlyForShippedModels() {
        let shipped = ParakeetModel.tdtCtc110mEnglish.rawValue
        XCTAssertEqual(ModelPins.scriptArguments(for: shipped), [ModelPins.revisions[shipped]!])
        XCTAssertEqual(ModelPins.scriptArguments(for: "someone/custom-model"), [])
    }
}
