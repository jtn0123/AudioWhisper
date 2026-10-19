import CoreML
import CryptoKit

/// Workaround for one qualified Base artifact on Apple Silicon macOS 15.
/// Upstream assets are never modified. Unknown artifacts keep the SDK path.
struct PreparedWhisperEncoder: Sendable {
    struct Environment: Sendable {
        var major: Int
        var appleSilicon: Bool
        var build: String
        static var current: Self {
            .init(major: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                  appleSilicon: Arch.isAppleSilicon, build: ProcessInfo.processInfo.operatingSystemVersionString)
        }
        func applies(to model: WhisperModel) -> Bool { model == .base && appleSilicon && major == 15 }
    }

    struct Recipe: Sendable {
        var mil: String
        var specification: String
        var weights: String
        static let base15 = Self(
            mil: "dc74813e26fce790fe22a33dcef8be535b9dce566f38a8bdb677f5e07dcf9138",
            specification: "1d42038f84b508da5ce9b953302387ffedc097c346d36a56b765109002b6080e",
            weights: "061ff4d74e5de3937b31288465d6c6f2697f92d121c80b23f51dd26bbdfe642b")
    }

    typealias Compile = @Sendable (URL) async throws -> URL
    typealias Validate = @Sendable (URL, MLComputeUnits) throws -> Void
    static let serializer = DiskMutationSerializer<String>()
    let root: URL
    let environment: Environment
    let recipe: Recipe
    let compile: Compile
    let validate: Validate

    init(root: URL = RebuildStorage.root.appendingPathComponent("PreparedWhisperEncoders/base"),
         environment: Environment = .current, recipe: Recipe = .base15,
         compile: @escaping Compile = { try await MLModel.compileModel(at: $0) },
         validate: @escaping Validate = { try Self.validateModel($0, compute: $1) }) {
        self.root = root
        self.environment = environment
        self.recipe = recipe
        self.compile = compile
        self.validate = validate
    }

    func prepare(model: WhisperModel, folder: URL, compute: MLComputeUnits) async throws -> URL? {
        guard environment.applies(to: model) else { return nil }
        let original = folder.appendingPathComponent("AudioEncoder.mlmodelc")
        guard try ModelIntegrity.sha256(of: original.appendingPathComponent("model.mil")) == recipe.mil else { return nil }
        guard (try? ModelIntegrity.sha256(of: original.appendingPathComponent("model.mlmodel"))) == recipe.specification,
              (try? ModelIntegrity.sha256(of: original.appendingPathComponent("weights/weight.bin"))) == recipe.weights else {
            throw PreparationError.source
        }
        let identity = "recipe1|\(recipe.specification)|\(recipe.weights)|\(environment.build)|arm64|\(compute.rawValue)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = root.appendingPathComponent(key + ".mlmodelc", isDirectory: true)
        try await Self.serializer.run(key: destination.path) {
            try await prepare(original: original, destination: destination, compute: compute)
        }
        try Task.checkCancellation()
        return destination
    }

    private func prepare(original: URL, destination: URL, compute: MLComputeUnits) async throws {
        let files = FileManager.default
        if files.fileExists(atPath: destination.path) {
            do { try validate(destination, compute); return } catch { try files.removeItem(at: destination) }
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent("staging-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        let package = try Self.package(original: original, staging: staging)
        let compiled = try await compile(package)
        defer { try? files.removeItem(at: compiled) }
        try Task.checkCancellation()
        try validate(compiled, compute)
        let ready = staging.appendingPathComponent("ready.mlmodelc", isDirectory: true)
        try files.copyItem(at: compiled, to: ready)
        do { try files.moveItem(at: ready, to: destination) } catch {
            // Another app process may have published the same identity first.
            guard files.fileExists(atPath: destination.path) else { throw error }
            try validate(destination, compute)
        }
    }

    private static func package(original: URL, staging: URL) throws -> URL {
        let package = staging.appendingPathComponent("AudioEncoder.mlpackage", isDirectory: true)
        let data = package.appendingPathComponent("Data/com.apple.CoreML", isDirectory: true)
        let weights = data.appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: original.appendingPathComponent("model.mlmodel"),
                                        to: data.appendingPathComponent("model.mlmodel"))
        try FileManager.default.copyItem(at: original.appendingPathComponent("weights/weight.bin"),
                                        to: weights.appendingPathComponent("weight.bin"))
        let modelID = UUID().uuidString, weightsID = UUID().uuidString
        let manifest: [String: Any] = ["fileFormatVersion": "1.0.0", "rootModelIdentifier": modelID,
            "itemInfoEntries": [
                modelID: ["author": "com.apple.CoreML", "description": "CoreML Model Specification",
                          "name": "model.mlmodel", "path": "com.apple.CoreML/model.mlmodel"],
                weightsID: ["author": "com.apple.CoreML", "description": "CoreML Model Weights",
                            "name": "weights", "path": "com.apple.CoreML/weights"]]]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: package.appendingPathComponent("Manifest.json"), options: .atomic)
        return package
    }

    static func validateModel(_ url: URL, compute: MLComputeUnits) throws {
        let config = MLModelConfiguration()
        config.computeUnits = compute
        let model = try MLModel(contentsOf: url, configuration: config)
        let inputs = model.modelDescription.inputDescriptionsByName
        let outputs = model.modelDescription.outputDescriptionsByName
        guard inputs["melspectrogram_features"]?.multiArrayConstraint?.shape == [1, 80, 1, 3000],
              outputs["encoder_output_embeds"]?.multiArrayConstraint?.shape == [1, 512, 1, 1500] else {
            throw PreparationError.shape
        }
    }

    enum PreparationError: String, LocalizedError {
        case source = "Whisper Base has incomplete or changed encoder preparation sources. Reinstall Base in Models & setup."
        case shape = "The prepared Whisper Base encoder has an unexpected model shape. Reinstall Base in Models & setup."
        var errorDescription: String? { rawValue }
    }
}
