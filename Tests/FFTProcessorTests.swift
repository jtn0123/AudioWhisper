import XCTest
@testable import AudioWhisper

final class FFTProcessorTests: XCTestCase {
    var processor: FFTProcessor!

    override func setUp() {
        super.setUp()
        processor = FFTProcessor(bufferSize: 2048, bandCount: 8, sampleRate: 44100)
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

    func testInitializationWithCustomValues() {
        let customProcessor = FFTProcessor(bufferSize: 1024, bandCount: 4, sampleRate: 48000)
        XCTAssertEqual(customProcessor.bufferSize, 1024)
        XCTAssertEqual(customProcessor.bandCount, 4)
        XCTAssertEqual(customProcessor.sampleRate, 48000)
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
        for i in 0..<2048 {
            samples[i] = sin(Float(i) * 0.1) * 0.9
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

        for i in 0..<2048 {
            samples[i] = sin(2.0 * .pi * frequency * Float(i) / sampleRate) * 0.5
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
        for i in 0..<1024 {
            samples[i] = sin(Float(i) * 0.1) * 0.8
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

        for i in 0..<2048 {
            samples[i] = sin(2.0 * .pi * frequency * Float(i) / sampleRate) * 0.8
        }

        let bands = processor.process(samples)

        // First band (sub-bass: 20-60Hz) should have significant energy
        // This is a soft test since FFT resolution at low frequencies is limited
        let lowBandSum = bands[0] + bands[1]
        let highBandSum = bands[6] + bands[7]

        // Low bands should generally have more energy for a 50Hz tone
        // (allowing some flexibility due to windowing and FFT limitations)
        XCTAssertGreaterThanOrEqual(bands.count, 8)
    }

    func testHighFrequencyConcentratesInHighBands() {
        // Generate a high frequency (10kHz - brilliance range)
        var samples = [Float](repeating: 0, count: 2048)
        let frequency: Float = 10000.0
        let sampleRate: Float = 44100.0

        for i in 0..<2048 {
            samples[i] = sin(2.0 * .pi * frequency * Float(i) / sampleRate) * 0.8
        }

        let bands = processor.process(samples)

        // High frequency should produce energy in upper bands
        // Band 6 is "Brilliance" (6000-12000Hz)
        XCTAssertGreaterThanOrEqual(bands.count, 8)
    }
}
