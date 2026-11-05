import XCTest
@testable import AudioWhisper

/// The daemon must recover from a crash loop without an app relaunch, and its
/// request timeouts must fit the work being asked for.
final class MLDaemonRecoveryTests: XCTestCase {
    /// A manager whose python is missing, so every spawn fails fast without
    /// launching anything but still counts toward the restart limit.
    private func failingManager() async -> MLDaemonManager {
        let manager = MLDaemonManager(allowsRuntimePreparation: false)
        await manager.setTestOverrides(
            python: URL(fileURLWithPath: "/nonexistent/python-\(UUID().uuidString)"),
            script: URL(fileURLWithPath: "/tmp/fake_ml_daemon_\(UUID().uuidString).py"))
        return manager
    }

    private func exhaustRestarts(_ manager: MLDaemonManager) async {
        let limit = await manager.maxRestartAttempts
        for _ in 0..<limit {
            _ = try? await manager.ensureDaemonRunning()
        }
    }

    private func isRestartLimit(_ manager: MLDaemonManager) async -> Bool {
        do {
            try await manager.ensureDaemonRunning()
        } catch MLDaemonError.restartLimitReached {
            return true
        } catch {
            return false
        }
        return false
    }

    // MARK: - Restart cool-down

    func testRestartLimitHoldsDuringTheCooldown() async {
        let manager = await failingManager()
        await exhaustRestarts(manager)
        let blocked = await isRestartLimit(manager)
        XCTAssertTrue(blocked, "A crash-looping daemon must stop respawning")
        let blockedAgain = await isRestartLimit(manager)
        XCTAssertTrue(blockedAgain, "It stays blocked until the cool-down passes")
    }

    func testOneMoreAttemptIsAllowedAfterTheCooldown() async {
        let manager = await failingManager()
        await manager.setRestartCooldownForTesting(.zero)
        await exhaustRestarts(manager)

        let retried = await isRestartLimit(manager)
        XCTAssertFalse(retried, "After the cool-down the daemon gets another spawn attempt")
        let count = await manager.restartAttemptsForTesting()
        let limit = await manager.maxRestartAttempts
        XCTAssertEqual(count, limit, "Only one extra attempt, not a full reset")
    }

    func testCooldownIsMeasuredFromTheLastAllowedAttempt() async {
        let manager = await failingManager()
        await exhaustRestarts(manager)
        guard let hitAt = await manager.restartLimitHitAt else {
            return XCTFail("Reaching the limit must start the cool-down")
        }
        let cooldown = await manager.restartCooldown
        let limit = await manager.maxRestartAttempts
        await manager.liftRestartLimitIfCooledDown(now: hitAt + cooldown - .seconds(1))
        let stillBlocked = await manager.restartAttemptsForTesting()
        XCTAssertEqual(stillBlocked, limit)

        await manager.liftRestartLimitIfCooledDown(now: hitAt + cooldown)
        let lifted = await manager.restartAttemptsForTesting()
        XCTAssertEqual(lifted, limit - 1)
    }

    func testExplicitResetClearsTheLimitImmediately() async {
        let manager = await failingManager()
        await exhaustRestarts(manager)
        await manager.resetRestartLimit()
        let count = await manager.restartAttemptsForTesting()
        let hitAt = await manager.restartLimitHitAt
        XCTAssertEqual(count, 0)
        XCTAssertNil(hitAt)
    }

    // MARK: - Request timeouts

    func testTimeoutsGrowWithTheWorkRequested() {
        let shortAudio = MLRequestTimeout.transcribe(pcmBytes: 10 * 16_000 * 4)
        let hourOfAudio = MLRequestTimeout.transcribe(pcmBytes: 3600 * 16_000 * 4)
        XCTAssertGreaterThanOrEqual(shortAudio, 60, "Never shorter than the old fixed limit")
        XCTAssertGreaterThan(hourOfAudio, 1800, "An hour of audio must not hit a one-minute timeout")

        let sentence = MLRequestTimeout.correct(text: "a short sentence to tidy up")
        let essay = MLRequestTimeout.correct(text: Array(repeating: "word", count: 1500).joined(separator: " "))
        XCTAssertGreaterThanOrEqual(sentence, 60)
        XCTAssertGreaterThan(essay, 1000, "A 4,096-token cleanup, generated twice, must fit")
        XCTAssertGreaterThan(MLRequestTimeout.summarize(text: "notes"), 300)
    }

    func testTimeoutsAreBounded() {
        XCTAssertEqual(MLRequestTimeout.transcribe(pcmBytes: Int.max / 2), MLRequestTimeout.maximum)
        XCTAssertEqual(MLRequestTimeout.transcribe(pcmBytes: -1), MLRequestTimeout.modelLoadSeconds)
        XCTAssertLessThan(MLRequestTimeout.ping, 60)
    }
}
