import XCTest
@testable import AudioWhisper

/// Tests for the real ExtAudioFile decoding path.
///
/// Audit item D3. `AudioProcessor.swift` measured 7.4% coverage with a test file
/// named after it, and the reason was structural rather than neglect:
/// `loadAudio` returns a hardcoded five-element array whenever
/// `AppEnvironment.isRunningTests` is true, so the decode was unreachable from
/// any test and `AudioProcessorTests` could only assert on the stub. Those
/// assertions were true of the stub and said nothing about decoding.
///
/// The decode now lives in `decodeAudio(url:samplingRate:)`, which these tests
/// call directly against `Tests/Resources/test_audio.wav`. `loadAudio` keeps its
/// short-circuit, so the rest of the suite stays free of CoreMedia warnings.
final class AudioDecodeTests: XCTestCase {

    /// The bundled fixture. `Tests/Resources` is copied into the test bundle by
    /// `Package.swift`.
    private func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "test_audio", withExtension: "wav") else {
            throw XCTSkip("test_audio.wav fixture missing from the test bundle")
        }
        return url
    }

    func testDecodeReturnsSamplesFromARealFile() throws {
        let url = try fixtureURL()

        let samples = try decodeAudio(url: url, samplingRate: 16_000)

        XCTAssertFalse(samples.isEmpty, "a real decode must produce samples")
        XCTAssertGreaterThan(samples.count, 5,
                             "more than the five-element stub loadAudio returns under test")
    }

    /// Every sample must be finite and in range — a conversion or buffer-stride
    /// mistake shows up here as NaN or wild values rather than as a crash.
    func testDecodedSamplesAreFiniteAndNormalised() throws {
        let url = try fixtureURL()

        let samples = try decodeAudio(url: url, samplingRate: 16_000)

        XCTAssertTrue(samples.allSatisfy { $0.isFinite }, "decoded samples must all be finite")
        XCTAssertTrue(samples.allSatisfy { $0 >= -1.0 && $0 <= 1.0 },
                      "float32 PCM must stay within [-1, 1]")
    }

    /// The client format asks for a specific rate, so a higher rate must yield
    /// proportionally more samples. This is what proves resampling is actually
    /// applied rather than the file's native rate being passed through.
    func testHigherSampleRateYieldsProportionallyMoreSamples() throws {
        let url = try fixtureURL()

        let low = try decodeAudio(url: url, samplingRate: 16_000)
        let high = try decodeAudio(url: url, samplingRate: 48_000)

        XCTAssertFalse(low.isEmpty)
        XCTAssertGreaterThan(high.count, low.count,
                             "3x the sample rate must decode to more samples")

        // Allow generous slack for codec priming/padding, but the ratio should
        // be recognisably ~3x rather than ~1x.
        let ratio = Double(high.count) / Double(low.count)
        XCTAssertGreaterThan(ratio, 2.0, "expected roughly 3x, got \(ratio)")
        XCTAssertLessThan(ratio, 4.0, "expected roughly 3x, got \(ratio)")
    }

    func testDecodeIsDeterministic() throws {
        let url = try fixtureURL()

        let first = try decodeAudio(url: url, samplingRate: 16_000)
        let second = try decodeAudio(url: url, samplingRate: 16_000)

        XCTAssertEqual(first, second, "decoding the same file twice must agree")
    }

    // MARK: - Failure paths

    func testDecodingAMissingFileThrowsOpenFailed() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no_such_audio_\(UUID().uuidString).wav")

        XCTAssertThrowsError(try decodeAudio(url: missing, samplingRate: 16_000)) { error in
            guard case AudioLoadError.openFailed = error else {
                return XCTFail("expected .openFailed, got \(error)")
            }
        }
    }

    /// A file that exists but is not audio must fail cleanly rather than
    /// returning garbage samples.
    func testDecodingANonAudioFileThrows() throws {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("not_audio_\(UUID().uuidString).wav")
        try Data("this is definitely not a wav file".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        XCTAssertThrowsError(try decodeAudio(url: bogus, samplingRate: 16_000)) { error in
            XCTAssertTrue(error is AudioLoadError, "expected AudioLoadError, got \(error)")
        }
    }

    // MARK: - The short-circuit itself

    /// Documents the behaviour these tests exist to work around, so that if the
    /// short-circuit is ever removed this fails loudly rather than silently
    /// changing what every other test sees.
    func testLoadAudioStillShortCircuitsUnderTest() throws {
        let url = try fixtureURL()

        let stub = try loadAudio(url: url, samplingRate: 16_000)

        XCTAssertEqual(stub, [0.0, 0.1, -0.1, 0.2, -0.2],
                       "loadAudio short-circuits under test; decodeAudio is the real path")
    }
}
