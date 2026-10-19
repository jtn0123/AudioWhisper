import XCTest
@testable import AudioWhisper

@MainActor
final class MeetingEngineFixtureTests: XCTestCase {
    func testInstalledWhisperProducesSourceLabeledOffsetMeetingSegments() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_E2E"] == "1", "Opt-in installed-model acceptance")
        try XCTSkipUnless(WhisperKitStorage.isModelDownloaded(.base),
                          "Install Base before this fixture; tests never download it")
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
        let service = LocalWhisperService.shared
        let segments = try await service.meetingSegments(audioFileURL: audio, model: .base, language: .automatic,
                                                        source: .system, offset: 42)
        await service.clearCache()
        XCTAssertFalse(segments.isEmpty)
        XCTAssertTrue(segments.allSatisfy { $0.source == .system && $0.start >= 42 && $0.end >= $0.start && $0.end < 46 })
        let text = segments.map(\.text).joined(separator: " ")
        XCTAssertFalse(text.contains("<|"), "Meeting text must not expose Whisper control tokens")
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        XCTAssertGreaterThanOrEqual(words.intersection(["quick", "brown", "fox", "lazy", "dog"]).count, 4, text)
        print("REAL_MEETING_SEGMENTS count=\(segments.count) source=system offset=42 text=\(text)")
    }
}
