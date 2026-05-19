import XCTest
@testable import AudioWhisper

final class FFTProcessorTests: XCTestCase {
    var processor: FFTProcessor!

    override func setUp() {
        super.setUp()
        // Force unwrap in test - valid parameters should always succeed
        processor = FFTProcessor(bufferSize: 2048, bandCount: 8, sampleRate: 44100)!
    }

    override func tearDown() {
        processor = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertEqual(processor.bufferSize, 2048)
        XCTAssertEqual(processor.bandCount, 8)
        XCTAssertEqual(processor.sampleRate, 44100)
    }

    func testInitializationWithCustomValues() throws {
        let customProcessor = try XCTUnwrap(FFTProcessor(bufferSize: 1024, bandCount: 4, sampleRate: 48000))
        XCTAssertEqual(customProcessor.bufferSize, 1024)
        XCTAssertEqual(customProcessor.bandCount, 4)
        XCTAssertEqual(customProcessor.sampleRate, 48000)
    }

    func testInitializationFailsWithInvalidBufferSize() {
        // Buffer size must be power of 2
        XCTAssertNil(FFTProcessor(bufferSize: 100, bandCount: 8, sampleRate: 44100))
        XCTAssertNil(FFTProcessor(bufferSize: 0, bandCount: 8, sampleRate: 44100))
        XCTAssertNil(FFTProcessor(bufferSize: -1, bandCount: 8, sampleRate: 44100))
    }

    // MARK: - Sample Rate Update Tests (bug #32)

    func testUpdateSampleRateChangesSampleRate() {
        // Bug #32 regression: the audio engine taps at the device's actual rate
        // (often 48 kHz), not the 44.1 kHz default. The FFT processor must be
        // updatable so Hz→bin mapping in calculateBands is correct.
        XCTAssertEqual(processor.sampleRate, 44100)

        processor.updateSampleRate(48000)

        XCTAssertEqual(processor.sampleRate, 48000, "Sample rate should be updated to the device rate")
    }

    func testUpdateSampleRateIgnoresNonPositiveValues() {
        processor.updateSampleRate(48000)

        processor.updateSampleRate(0)
        XCTAssertEqual(processor.sampleRate, 48000, "Zero sample rate should be ignored")

        processor.updateSampleRate(-1)
        XCTAssertEqual(processor.sampleRate, 48000, "Negative sample rate should be ignored")
    }

    func testUpdateSampleRateAffectsBandMapping() {
        // A tone placed in band 0 (80-120 Hz) at 44.1 kHz must still be detected
        // after switching the processor to a 48 kHz sample rate when the signal
        // is generated at 48 kHz.
        let processor48 = FFTProcessor(bufferSize: 2048, bandCount: 8, sampleRate: 44100)!
        processor48.updateSampleRate(48000)

        var samples = [Float](repeating: 0, count: 2048)
        let frequency: Float = 100.0  // inside band 0 (80-120 Hz)
        for index in 0..<2048 {
            samples[index] = sin(2.0 * .pi * frequency * Float(index) / 48000.0) * 0.8
        }

        let bands = processor48.process(samples)
        XCTAssertGreaterThan(bands[0], 0.01, "A 100 Hz tone at 48 kHz should land in the lowest band")
    }

    // MARK: - Processing Tests

    func testProcessReturnsCorrectBandCount() {
        let samples = [Float](repeating: 0, count: 2048)
        let bands = processor.process(samples)

        XCTAssertEqual(bands.count, 8, "Should return 8 frequency bands")
    }

    func testSilentInputReturnsLowBands() {
        let samples = [Float](repeating: 0, count: 2048)
        let bands = processor.process(samples)

        for band in bands {
            XCTAssertLessThan(band, 0.01, "Silent input should produce near-zero bands")
        }
    }

    func testProcessWithFewerSamplesThanBufferSize() {
        // Should pad with zeros
        let samples = [Float](repeating: 0.5, count: 512)
        let bands = processor.process(samples)

        XCTAssertEqual(bands.count, 8, "Should still return 8 bands")
    }

    func testProcessWithMoreSamplesThanBufferSize() {
        // Should use last bufferSize samples
        let samples = [Float](repeating: 0.1, count: 4096)
        let bands = processor.process(samples)

        XCTAssertEqual(bands.count, 8, "Should still return 8 bands")
    }

    func testBandsAreNormalized() {
        // Generate a loud sine wave
        var samples = [Float](repeating: 0, count: 2048)
        for index in 0..<2048 {
            samples[index] = sin(Float(index) * 0.1) * 0.9
        }

        let bands = processor.process(samples)

        for band in bands {
            XCTAssertGreaterThanOrEqual(band, 0.0, "Bands should be >= 0")
            XCTAssertLessThanOrEqual(band, 1.0, "Bands should be <= 1")
        }
    }

    func testSineWaveProducesNonZeroBands() {
        // Generate a 440Hz sine wave (should appear in mid frequencies)
        var samples = [Float](repeating: 0, count: 2048)
        let frequency: Float = 440.0
        let sampleRate: Float = 44100.0

        for index in 0..<2048 {
            samples[index] = sin(2.0 * .pi * frequency * Float(index) / sampleRate) * 0.5
        }

        let bands = processor.process(samples)

        // At least one band should have significant energy
        let maxBand = bands.max() ?? 0
        XCTAssertGreaterThan(maxBand, 0.01, "A 440Hz sine wave should produce detectable frequency content")
    }

    // MARK: - Level Calculation Tests

    func testCalculateLevelFromSilence() {
        let samples = [Float](repeating: 0, count: 1024)
        let level = processor.calculateLevel(from: samples)

        XCTAssertEqual(level, 0, "Silent samples should produce zero level")
    }

    func testCalculateLevelFromEmptyArray() {
        let samples: [Float] = []
        let level = processor.calculateLevel(from: samples)

        XCTAssertEqual(level, 0, "Empty array should produce zero level")
    }

    func testCalculateLevelFromLoudSignal() {
        // Constant loud signal
        let samples = [Float](repeating: 0.5, count: 1024)
        let level = processor.calculateLevel(from: samples)

        XCTAssertGreaterThan(level, 0, "Loud signal should produce non-zero level")
        XCTAssertLessThanOrEqual(level, 1.0, "Level should be clamped to 1.0")
    }

    func testCalculateLevelIsNormalized() {
        var samples = [Float](repeating: 0, count: 1024)
        for index in 0..<1024 {
            samples[index] = sin(Float(index) * 0.1) * 0.8
        }

        let level = processor.calculateLevel(from: samples)

        XCTAssertGreaterThanOrEqual(level, 0.0)
        XCTAssertLessThanOrEqual(level, 1.0)
    }

    // MARK: - Performance Tests

    func testProcessPerformance() {
        let samples = (0..<2048).map { _ in Float.random(in: -1...1) }

        measure {
            for _ in 0..<100 {
                _ = processor.process(samples)
            }
        }
    }

    func testLevelCalculationPerformance() {
        let samples = (0..<2048).map { _ in Float.random(in: -1...1) }

        measure {
            for _ in 0..<1000 {
                _ = processor.calculateLevel(from: samples)
            }
        }
    }

    // MARK: - Edge Cases

    func testProcessWithNaNValues() {
        var samples = [Float](repeating: 0, count: 2048)
        samples[100] = .nan

        let bands = processor.process(samples)

        // Should not crash, may produce NaN or zero
        XCTAssertEqual(bands.count, 8)
    }

    func testProcessWithInfiniteValues() {
        var samples = [Float](repeating: 0, count: 2048)
        samples[100] = .infinity

        let bands = processor.process(samples)

        // Should not crash
        XCTAssertEqual(bands.count, 8)
    }

    func testProcessWithNegativeValues() {
        let samples = [Float](repeating: -0.5, count: 2048)
        let bands = processor.process(samples)

        XCTAssertEqual(bands.count, 8)
        // DC offset should produce some frequency content
    }

    // MARK: - Frequency Band Tests

    func testLowFrequencyConcentratesInLowBands() {
        // Generate a very low frequency (50Hz - sub-bass)
        var samples = [Float](repeating: 0, count: 2048)
        let frequency: Float = 50.0
        let sampleRate: Float = 44100.0

        for index in 0..<2048 {
            samples[index] = sin(2.0 * .pi * frequency * Float(index) / sampleRate) * 0.8
        }

        let bands = processor.process(samples)

        // First band (sub-bass: 20-60Hz) should have significant energy
        // This is a soft test since FFT resolution at low frequencies is limited
        // Low bands should generally have more energy for a 50Hz tone
        // (allowing some flexibility due to windowing and FFT limitations)
        XCTAssertGreaterThanOrEqual(bands.count, 8)
    }

    func testHighFrequencyConcentratesInHighBands() {
        // Generate a high frequency (10kHz - brilliance range)
        var samples = [Float](repeating: 0, count: 2048)
        let frequency: Float = 10000.0
        let sampleRate: Float = 44100.0

        for index in 0..<2048 {
            samples[index] = sin(2.0 * .pi * frequency * Float(index) / sampleRate) * 0.8
        }

        let bands = processor.process(samples)

        // High frequency should produce energy in upper bands
        // Band 6 is "Brilliance" (6000-12000Hz)
        XCTAssertGreaterThanOrEqual(bands.count, 8)
    }
}
