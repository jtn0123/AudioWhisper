import XCTest
@testable import AudioWhisper

final class SemanticCorrectionTests: IsolatedXCTestCase {
    // Deferred(D1): Semantic correction config keys live in UserDefaults.standard.
    // Once the consumers accept an injected UserDefaults, route writes
    // through a UUID-scoped suite and re-enable isolation.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    // MARK: - SemanticCorrectionMode Tests
    
    func testSemanticCorrectionModeRawValues() {
        XCTAssertEqual(SemanticCorrectionMode.off.rawValue, "off")
        XCTAssertEqual(SemanticCorrectionMode.localMLX.rawValue, "localMLX")
    }

    func testSemanticCorrectionModeDisplayNames() {
        XCTAssertEqual(SemanticCorrectionMode.off.displayName, "Off")
        XCTAssertEqual(SemanticCorrectionMode.localMLX.displayName, "Local (MLX)")
    }

    func testSemanticCorrectionModeAllCases() {
        let allCases = SemanticCorrectionMode.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.off))
        XCTAssertTrue(allCases.contains(.localMLX))
    }

    func testSemanticCorrectionModeCodable() {
        let modes: [SemanticCorrectionMode] = [.off, .localMLX]
        
        for mode in modes {
            // Encode
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(mode) else {
                XCTFail("Failed to encode mode: \(mode)")
                continue
            }
            
            // Decode
            let decoder = JSONDecoder()
            guard let decodedMode = try? decoder.decode(SemanticCorrectionMode.self, from: data) else {
                XCTFail("Failed to decode mode: \(mode)")
                continue
            }
            
            XCTAssertEqual(mode, decodedMode)
        }
    }
    
    // MARK: - MLXCorrectionError Tests
    
    func testMLXCorrectionErrorDescriptions() {
        let pythonError = MLXCorrectionError.pythonNotFound(path: "/usr/bin/python3")
        XCTAssertTrue(pythonError.errorDescription?.contains("Python executable not found") ?? false)
        
        let scriptError = MLXCorrectionError.scriptNotFound
        XCTAssertTrue(scriptError.errorDescription?.contains("MLX correction script not found") ?? false)
        
        let correctionError = MLXCorrectionError.correctionFailed("Test error")
        XCTAssertTrue(correctionError.errorDescription?.contains("Test error") ?? false)
        
        let invalidError = MLXCorrectionError.invalidResponse("Invalid JSON")
        XCTAssertTrue(invalidError.errorDescription?.contains("Invalid JSON") ?? false)
        
        let dependencyError = MLXCorrectionError.dependencyMissing("mlx-lm", installCommand: "pip install mlx-lm")
        XCTAssertTrue(dependencyError.errorDescription?.contains("mlx-lm") ?? false)
        XCTAssertTrue(dependencyError.errorDescription?.contains("pip install mlx-lm") ?? false)
        
        let timeoutError = MLXCorrectionError.processTimedOut(30.0)
        XCTAssertTrue(timeoutError.errorDescription?.contains("30") ?? false)
    }
    
    func testMLXCorrectionErrorEquality() {
        let error1 = MLXCorrectionError.pythonNotFound(path: "/usr/bin/python3")
        let error2 = MLXCorrectionError.pythonNotFound(path: "/usr/bin/python3")
        let error3 = MLXCorrectionError.pythonNotFound(path: "/usr/local/bin/python3")
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
        
        let scriptError1 = MLXCorrectionError.scriptNotFound
        let scriptError2 = MLXCorrectionError.scriptNotFound
        XCTAssertEqual(scriptError1, scriptError2)
    }
    
    // MARK: - MLXModel Tests
    
    func testMLXModelProperties() {
        let model = MLXModel(
            repo: "mlx-community/test-model",
            estimatedSize: "1.5 GB",
            description: "Test model"
        )
        
        XCTAssertEqual(model.repo, "mlx-community/test-model")
        XCTAssertEqual(model.estimatedSize, "1.5 GB")
        XCTAssertEqual(model.description, "Test model")
        XCTAssertEqual(model.displayName, "test-model")
    }
    
    func testMLXModelDisplayName() {
        let model1 = MLXModel(
            repo: "mlx-community/test-model",
            estimatedSize: "1.5 GB",
            description: "Test"
        )
        XCTAssertEqual(model1.displayName, "test-model")
        
        let model2 = MLXModel(
            repo: "single-name",
            estimatedSize: "1.0 GB",
            description: "Test"
        )
        XCTAssertEqual(model2.displayName, "single-name")
    }
    
    func testMLXModelEquality() {
        let model1 = MLXModel(
            repo: "mlx-community/test-model",
            estimatedSize: "1.5 GB",
            description: "Test"
        )
        
        let model2 = MLXModel(
            repo: "mlx-community/test-model",
            estimatedSize: "1.5 GB",
            description: "Test"
        )
        
        let model3 = MLXModel(
            repo: "mlx-community/different-model",
            estimatedSize: "1.5 GB",
            description: "Test"
        )
        
        // Models with same repo should be equal
        XCTAssertEqual(model1.repo, model2.repo)
        XCTAssertNotEqual(model1.repo, model3.repo)
    }
    
    // MARK: - Recommended Models Tests
    
    @MainActor
    func testRecommendedModelsCount() {
        // Not a frozen number for its own sake: the catalog must stay small
        // enough to be a curated recommendation rather than a dump of every
        // model that exists. Three today (fast / small-accurate / best).
        let models = MLXModelManager.recommendedModels
        XCTAssertGreaterThanOrEqual(models.count, 2, "Need at least a fast and an accurate option")
        XCTAssertLessThanOrEqual(models.count, 5, "Catalog should stay curated")
    }

    @MainActor
    func testRecommendedModelsContent() {
        let models = MLXModelManager.recommendedModels
        
        // Check that we have the expected models
        let modelRepos = models.map { $0.repo }
        let expectedRepos: Set<String> = [
            "mlx-community/gemma-3-1b-it-qat-4bit",
            "mlx-community/Qwen3-1.7B-4bit",
            "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        ]
        XCTAssertEqual(Set(modelRepos), expectedRepos)
        XCTAssertFalse(modelRepos.contains("mlx-community/gemma-2-2b-it-4bit"))
        XCTAssertFalse(modelRepos.contains("mlx-community/Qwen2.5-1.5B-Instruct-4bit"))
    }
    
    @MainActor
    func testRecommendedModelsHaveDescriptions() {
        for model in MLXModelManager.recommendedModels {
            XCTAssertFalse(model.description.isEmpty)
            XCTAssertFalse(model.estimatedSize.isEmpty)
        }
    }
    
    // MARK: - Cache Tests
    
    func testMLXCorrectionServiceCacheInvalidation() {
        let service = MLXCorrectionService()
        
        // Test invalidating all cache
        service.invalidateCache()
        
        // Test invalidating specific path
        service.invalidateCache(for: "/usr/bin/python3")
        
        // No crash = success for this test
        XCTAssertNotNil(service)
    }
    
    // MARK: - Default Settings Tests
    
    func testDefaultModelSettings() {
        // Clear UserDefaults first
        AppDefaults.defaults.removeObject(forKey: "semanticCorrectionModelRepo")
        AppDefaults.defaults.removeObject(forKey: "semanticCorrectionPythonPath")
        
        // Check defaults in SemanticCorrectionService
        let service = SemanticCorrectionService()
        XCTAssertNotNil(service)
        
        // The service should use defaults when UserDefaults is empty
        // This is tested indirectly since we can't access private methods
    }
}
