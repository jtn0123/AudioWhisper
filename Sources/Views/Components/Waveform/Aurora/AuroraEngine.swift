import Foundation

/// Signal maths shared by the Aurora engine.
enum AuroraSignal {
    /// Below this the microphone counts as silent.
    static let noiseGate = 0.02

    /// Gate plus a gentle perceptual lift. Monotonic: louder always looks louder.
    static func shape(_ raw: Double) -> Double {
        guard raw > noiseGate else { return 0 }
        return pow(min(1, (raw - noiseGate) / (1 - noiseGate)), 0.75)
    }

    /// One-pole follower with separate attack and release time constants.
    static func follow(_ current: Double, _ target: Double, attack: Double, release: Double, dt: Double) -> Double {
        let tau = target > current ? attack : release
        return current + (target - current) * (1 - exp(-dt / max(tau, 0.0001)))
    }

    /// Soft ceiling so loud speech rounds off instead of flat-topping.
    static func softClip(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        return min(1, tanh(1.3 * value) / tanh(1.3))
    }
}

/// The three overlapping mountains: value-bucket counts, gains and placement.
enum AuroraLobes {
    /// Value buckets per mountain: wide (centre), left, right.
    static let sizes = [7, 10, 13]
    static let gains = [1.0, 0.85, 0.72]
    /// Horizontal centre and half-width of each mountain (fractions of the strip).
    static let centers = [0.5, 0.36, 0.64]
    static let spreads = [0.5, 0.36, 0.36]
    static var valueCount: Int { sizes.reduce(0, +) }

    static func offset(of lobe: Int) -> Int { sizes[0..<lobe].reduce(0, +) }

    static func gain(forValueIndex index: Int) -> Double {
        var start = 0
        for (lobe, size) in sizes.enumerated() {
            if index < start + size { return gains[lobe] }
            start += size
        }
        return 1
    }
}

/// Per-frame state for the Aurora styles.
///
/// Every height comes from the gated, shaped mic level times the real sample
/// texture. The extra state is either a time-constant follower of that signal
/// (reflection afterglow) or the colour crawl, which idles slowly and speeds up
/// with the voice. Reduce Motion removes texture, afterglow lag, crawl and glint.
final class AuroraEngine {
    /// Shaped level with fast attack and controlled release.
    private(set) var level = 0.0
    /// Per-bucket smoothed heights in 0…1, all three mountains concatenated.
    private(set) var values = [Double](repeating: 0, count: AuroraLobes.valueCount)
    /// Slower-release copy of `values` that drives the Horizon reflection.
    private(set) var glow = [Double](repeating: 0, count: AuroraLobes.valueCount)
    /// Colour-field phase, in palette cycles. Advances left → right.
    private(set) var crawl = 0.0
    /// Position of the travelling rim glint (0…1.4, wraps).
    private(set) var glint = 0.0

    private var texture = [Double](repeating: 1, count: AuroraLobes.valueCount)
    private var lastTime: Double?
    private var reduceMotion = false

    /// True once nothing is left to animate: silent, flat and not crawling.
    var isAtRest: Bool {
        level < 0.001 && (values.max() ?? 0) < 0.002 && (glow.max() ?? 0) < 0.002
    }

    func advance(to time: Double, rawLevel: Float, samples: [Float], reduceMotion: Bool) {
        if reduceMotion != self.reduceMotion {
            self.reduceMotion = reduceMotion
            lastTime = nil
        }
        guard let previous = lastTime else { lastTime = time; return }
        guard time > previous else { return }
        let dt = min(time - previous, 0.25)   // a long gap relaxes, never bursts
        lastTime = time

        let target = AuroraSignal.shape(Double(rawLevel))
        level = reduceMotion
            ? AuroraSignal.follow(level, target, attack: 0.07, release: 0.34, dt: dt)
            : AuroraSignal.follow(level, target, attack: 0.02, release: 0.15, dt: dt)
        fillTexture(samples)
        stepValues(target: target, dt: dt)
        stepGlow(dt: dt)
        guard !reduceMotion else { return }
        crawl += dt * (0.045 + 0.22 * level)
        glint += dt * (0.22 + 0.55 * level)
        if glint > 1.4 { glint -= 1.4 }
    }

    /// Bucket magnitudes of the sample buffer, normalised to mean 1 per mountain.
    private func fillTexture(_ samples: [Float]) {
        guard !reduceMotion, !samples.isEmpty else {
            for index in texture.indices { texture[index] = 1 }
            return
        }
        for lobe in AuroraLobes.sizes.indices {
            fillBuckets(samples, from: AuroraLobes.offset(of: lobe), count: AuroraLobes.sizes[lobe])
        }
    }

    private func fillBuckets(_ samples: [Float], from offset: Int, count: Int) {
        var sum = 0.0
        for bucket in 0..<count {
            let low = bucket * samples.count / count
            let high = min(samples.count, max(low + 1, (bucket + 1) * samples.count / count))
            var total = 0.0
            for index in low..<high { total += abs(Double(samples[index])) }
            texture[offset + bucket] = total / Double(max(1, high - low))
            sum += texture[offset + bucket]
        }
        let mean = max(1e-5, sum / Double(count))
        for bucket in 0..<count { texture[offset + bucket] /= mean }
    }

    private func stepValues(target: Double, dt: Double) {
        let attack = reduceMotion ? 0.07 : 0.032
        let release = reduceMotion ? 0.34 : 0.24
        for index in values.indices {
            let textured = min(1.45, max(0.45, texture[index]))
            let goal = AuroraSignal.softClip(target * AuroraLobes.gain(forValueIndex: index) * textured)
            values[index] = AuroraSignal.follow(values[index], goal, attack: attack, release: release, dt: dt)
        }
    }

    private func stepGlow(dt: Double) {
        for index in glow.indices {
            glow[index] = reduceMotion
                ? values[index]
                : AuroraSignal.follow(glow[index], values[index], attack: 0.05, release: 0.30, dt: dt)
        }
    }
}
