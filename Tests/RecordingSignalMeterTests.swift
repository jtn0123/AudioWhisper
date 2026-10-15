// swiftlint:disable:next unused_import - verified required: removing it breaks the build (AVAudioPCMBuffer)
import AVFoundation
import XCTest
@testable import AudioWhisper

final class RecordingSignalMeterTests: XCTestCase {
    func testEmptyMeterIsNotSilentBecauseNothingWasMeasured() {
        let meter = RecordingSignalMeter()
        XCTAssertFalse(meter.isSilent)
        XCTAssertFalse(meter.warrantsSilenceWarning)
        XCTAssertEqual(meter.duration, 0)
    }

    func testDigitalSilenceIsSilentAndWarnsOnlyAfterTheDelay() {
        var meter = RecordingSignalMeter()
        meter.add([Float](repeating: 0, count: 48_000), sampleRate: 48_000)
        XCTAssertTrue(meter.isSilent)
        XCTAssertFalse(meter.warrantsSilenceWarning, "one second is too early to call the microphone dead")

        meter.add([Float](repeating: 0, count: 72_000), sampleRate: 48_000)
        XCTAssertEqual(meter.duration, 2.5, accuracy: 0.0001)
        XCTAssertTrue(meter.warrantsSilenceWarning)
    }

    func testOneAudibleBufferClearsTheWholeRecording() {
        var meter = RecordingSignalMeter()
        meter.add([Float](repeating: 0.0001, count: 160_000), sampleRate: 16_000)
        XCTAssertTrue(meter.isSilent)

        meter.add(sine(amplitude: 0.05, count: 1_024), sampleRate: 16_000)
        XCTAssertFalse(meter.isSilent)
        XCTAssertFalse(meter.warrantsSilenceWarning)
    }

    func testQuietRoomNoiseAboveTheFloorIsNotTreatedAsSilence() {
        // About -54 dBFS: a quiet room on a built-in microphone. The gate is for
        // dead inputs, not for deciding whether someone spoke.
        var meter = RecordingSignalMeter()
        meter.add(sine(amplitude: 0.003, count: 48_000 * 3), sampleRate: 48_000)
        XCTAssertFalse(meter.isSilent)
    }

    func testNonFiniteLevelsAreIgnored() {
        var meter = RecordingSignalMeter()
        meter.add(rms: .nan, frames: 48_000 * 3, sampleRate: 48_000)
        meter.add(rms: .infinity, frames: 1, sampleRate: 48_000)
        XCTAssertTrue(meter.isSilent)
    }

    func testRMSMatchesTheDefinition() {
        XCTAssertEqual(RecordingSignalMeter.rms(of: [3, -4]), sqrt(12.5), accuracy: 0.00001)
    }
}

@MainActor
final class AudioEngineRecorderSignalTests: XCTestCase {
    func testSilentCaptureRaisesTheLiveWarningAndIsReportedAtStop() async throws {
        let recorder = AudioEngineRecorder()
        recorder.isRecording = true
        for _ in 0..<26 { recorder.processAudioBuffer(try pcmBuffer(amplitude: 0)) }
        // The level publish is throttled to 60 Hz; let the next one through.
        try await Task.sleep(for: .milliseconds(25))
        recorder.processAudioBuffer(try pcmBuffer(amplitude: 0))
        try await waitUntil { recorder.inputAppearsSilent }

        _ = recorder.stopRecording()
        XCTAssertEqual(recorder.lastRecordingSignal?.isSilent, true)
        XCTAssertFalse(recorder.inputAppearsSilent, "stopping clears the live warning")
    }

    func testSpeechClearsTheLiveWarning() async throws {
        let recorder = AudioEngineRecorder()
        recorder.isRecording = true
        for _ in 0..<26 { recorder.processAudioBuffer(try pcmBuffer(amplitude: 0)) }
        try await Task.sleep(for: .milliseconds(25))
        recorder.processAudioBuffer(try pcmBuffer(amplitude: 0))
        try await waitUntil { recorder.inputAppearsSilent }

        try await Task.sleep(for: .milliseconds(25))
        recorder.processAudioBuffer(try pcmBuffer(amplitude: 0.2))
        try await waitUntil { !recorder.inputAppearsSilent }
        _ = recorder.stopRecording()
        XCTAssertEqual(recorder.lastRecordingSignal?.isSilent, false)
    }

    func testCancelForgetsTheLastSignal() throws {
        let recorder = AudioEngineRecorder()
        recorder.processAudioBuffer(try pcmBuffer(amplitude: 0))
        _ = recorder.stopRecording()
        XCTAssertNotNil(recorder.lastRecordingSignal)
        recorder.cancelRecording()
        XCTAssertNil(recorder.lastRecordingSignal)
    }

    func testWrittenAudioMakesAUsableRecording() throws {
        let recorder = AudioEngineRecorder()
        let url = captureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try recorder.beginCaptureFile(at: url, format: try format(channels: 1))
        for _ in 0..<3 { recorder.processAudioBuffer(try pcmBuffer(amplitude: 0.2)) }
        XCTAssertEqual(recorder.stopRecording(), url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecordingWhoseEveryWriteFailedIsDiscarded() throws {
        let recorder = AudioEngineRecorder()
        let url = captureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // A stereo file fed mono buffers: every write throws, as it did on
        // stereo devices before the file matched the tap's channel count.
        try recorder.beginCaptureFile(at: url, format: try format(channels: 2))
        for _ in 0..<3 { recorder.processAudioBuffer(try pcmBuffer(amplitude: 0.2)) }
        XCTAssertNil(recorder.stopRecording())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the unusable file is removed")
    }

    func testANewCaptureForgetsThePreviousSignal() throws {
        let recorder = AudioEngineRecorder()
        recorder.processAudioBuffer(try pcmBuffer(amplitude: 0))
        let url = captureURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try recorder.beginCaptureFile(at: url, format: try format(channels: 1))
        _ = recorder.stopRecording()
        XCTAssertEqual(recorder.lastRecordingSignal?.frames, 0)
    }

    private func captureURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signal-\(UUID()).m4a")
    }

    private func format(channels: AVAudioChannelCount) throws -> AVAudioFormat {
        try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: channels))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}

private func sine(amplitude: Float, count: Int) -> [Float] {
    (0..<count).map { amplitude * sin(Float($0) * 0.07) * sqrt(2) }
}

/// A 0.1 s mono buffer at 48 kHz.
private func pcmBuffer(amplitude: Float) throws -> AVAudioPCMBuffer {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
    buffer.frameLength = 4_800
    let channel = try XCTUnwrap(buffer.floatChannelData?[0])
    for (index, value) in sine(amplitude: amplitude, count: 4_800).enumerated() { channel[index] = value }
    return buffer
}
