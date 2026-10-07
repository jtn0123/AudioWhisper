import XCTest
@testable import AudioWhisper

private final class UnifiedCleanupDaemon: MLDaemonManaging {
    var prompts: [String] = []
    func correct(repo: String, text: String, prompt: String?) async throws -> String {
        prompts.append(prompt ?? "")
        return "Hello world."
    }
    func ping() async -> Bool { true }
}

@MainActor
final class UnifiedCleanupTests: XCTestCase {
    func testDestinationDoesNotSelectAProfileOrChangeThePrompt() async throws {
        try XCTSkipUnless(Arch.isAppleSilicon)
        let daemon = UnifiedCleanupDaemon()
        let service = SemanticCorrectionService(
            mlxService: MLXCorrectionService(daemon: daemon),
            preparePython: { URL(fileURLWithPath: "/unused-fixture-interpreter") })
        for app in [nil, "com.apple.mail", "com.apple.Terminal"] as [String?] {
            let result = await service.correctWithOutcome(
                text: "hello world", providerUsed: .parakeet, sourceAppBundleId: app,
                mode: .localMLX, modelRepo: "fixture/model")
            XCTAssertEqual(result.text, "Hello world.")
        }
        XCTAssertEqual(daemon.prompts.count, 3)
        XCTAssertEqual(Set(daemon.prompts), [CorrectionIntegrity.instruction + "\n\n" + CorrectionPrompt.template])
    }
}
