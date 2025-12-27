import Accelerate
import Foundation

/// Real-time FFT processor for audio frequency analysis.
/// Uses the Accelerate framework for SIMD-optimized processing.
///
/// ## Thread Safety
/// Marked `@unchecked Sendable` because:
/// - Each `AudioEngineRecorder` creates its own `FFTProcessor` instance
/// - Audio tap callbacks for a single input node are serialized by AVAudioEngine
/// - The mutable working buffers (`realPart`, `imagPart`, `window`) are only
///   accessed from the audio tap callback via `processAudioBuffer`
/// - Never shared across multiple `AudioEngineRecorder` instances
final class FFTProcessor: @unchecked Sendable {
    // MARK: - Configuration

    /// Number of samples per FFT frame (power of 2)
    let bufferSize: Int

    /// Number of output frequency bands
    let bandCount: Int

    /// Sample rate of the audio
    let sampleRate: Float

    // MARK: - FFT Setup

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]

    // MARK: - Frequency Band Boundaries (Hz)

    /// Frequency ranges for each band (in Hz)
    /// Voice-optimized: concentrates on fundamental voice frequencies (80Hz-1200Hz)
    private let bandRanges: [(low: Float, high: Float)] = [
        (80, 120),     // Low male fundamental
        (120, 180),    // High male fundamental
        (180, 260),    // Low female fundamental
        (260, 380),    // High female / low F1
        (380, 550),    // F1 core (vowel body)
        (550, 750),    // F1-F2 transition
        (750, 950),    // F2 core (vowel color)
        (950, 1200)    // F2 upper (clarity)
    ]

    // MARK: - Initialization

    /// Initialize the FFT processor.
    /// - Parameters:
    ///   - bufferSize: Number of samples per FFT (default 2048, must be power of 2)
    ///   - bandCount: Number of frequency bands to output (default 8)
    ///   - sampleRate: Audio sample rate (default 44100)
    /// - Returns: nil if FFT setup fails (extremely rare, indicates system memory issues)
    init?(bufferSize: Int = 2048, bandCount: Int = 8, sampleRate: Float = 44100) {
        guard bufferSize > 0 && (bufferSize & (bufferSize - 1)) == 0 else {
            return nil // Buffer size must be a power of 2
        }

        self.bufferSize = bufferSize
        self.bandCount = bandCount
        self.sampleRate = sampleRate

        // Calculate log2 of buffer size
        self.log2n = vDSP_Length(log2(Double(bufferSize)))

        // Create FFT setup
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil // FFT setup failed (system memory issue)
        }
        self.fftSetup = setup

        // Allocate buffers
        self.window = [Float](repeating: 0, count: bufferSize)
        self.realPart = [Float](repeating: 0, count: bufferSize / 2)
        self.imagPart = [Float](repeating: 0, count: bufferSize / 2)

        // Create Hanning window to reduce spectral leakage
        vDSP_hann_window(&window, vDSP_Length(bufferSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Processing

    /// Process audio samples and return frequency band levels.
    /// - Parameter samples: Array of audio samples (should be `bufferSize` length)
    /// - Returns: Array of normalized frequency band levels (0.0 to 1.0)
    func process(_ samples: [Float]) -> [Float] {
        guard samples.count >= bufferSize else {
            // Pad with zeros if not enough samples
            var paddedSamples = samples
            paddedSamples.append(contentsOf: [Float](repeating: 0, count: bufferSize - samples.count))
            return processInternal(paddedSamples)
        }

        // Use the last bufferSize samples if we have more
        let startIndex = samples.count - bufferSize
        return processInternal(Array(samples[startIndex...]))
    }

    private func processInternal(_ samples: [Float]) -> [Float] {
        // Apply Hanning window
        var windowedSamples = [Float](repeating: 0, count: bufferSize)
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(bufferSize))

        // Calculate magnitudes using stable pointers for DSPSplitComplex
        var magnitudes = [Float](repeating: 0, count: bufferSize / 2)

        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else {
                    return // Return with zero magnitudes (silence)
                }
                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)

                // Pack into split complex format
                windowedSamples.withUnsafeBufferPointer { ptr in
                    guard let ptrBase = ptr.baseAddress else { return }
                    ptrBase.withMemoryRebound(to: DSPComplex.self, capacity: bufferSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(bufferSize / 2))
                    }
                }

                // Perform FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Calculate magnitudes
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(bufferSize / 2))
            }
        }

        // Scale magnitudes
        var scaleFactor = Float(2.0 / Float(bufferSize))
        vDSP_vsmul(magnitudes, 1, &scaleFactor, &magnitudes, 1, vDSP_Length(bufferSize / 2))

        // Calculate frequency bands
        return calculateBands(from: magnitudes)
    }

    private func calculateBands(from magnitudes: [Float]) -> [Float] {
        let binWidth = sampleRate / Float(bufferSize)
        var bands = [Float](repeating: 0, count: bandCount)

        for (bandIndex, range) in bandRanges.prefix(bandCount).enumerated() {
            let lowBin = max(0, Int(range.low / binWidth))  // Ensure non-negative
            let highBin = min(Int(range.high / binWidth), magnitudes.count - 1)

            guard lowBin < highBin, lowBin < magnitudes.count else {
                bands[bandIndex] = 0
                continue
            }

            // Average magnitude in this band
            var sum: Float = 0
            vDSP_sve(Array(magnitudes[lowBin...highBin]), 1, &sum, vDSP_Length(highBin - lowBin + 1))
            let average = sum / Float(highBin - lowBin + 1)

            // Apply logarithmic scaling for perceptual uniformity (50x boost for better visibility)
            let logValue = log10(1 + average * 50) / log10(51)

            // Clamp to 0-1 range
            bands[bandIndex] = min(1.0, max(0.0, logValue))
        }

        return bands
    }

    /// Calculate the overall audio level from samples.
    /// - Parameter samples: Audio samples
    /// - Returns: Normalized level (0.0 to 1.0)
    func calculateLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        // Convert RMS to normalized level with gain for responsive visualization
        let level = min(1.0, rms * 8.0)
        return level
    }
}
