import Foundation

/// Monotonic, session-local measurements. No audio, text, history or telemetry.
struct RebuildSessionTiming: Equatable {
    var requested = ProcessInfo.processInfo.systemUptime
    var recording: TimeInterval?
    var stopped: TimeInterval?
    var recognized: TimeInterval?
    var delivered: TimeInterval?
    var delivery = "Not delivered"

    var startupMilliseconds: Double? { milliseconds(from: requested, to: recording) }
    var processingMilliseconds: Double? { milliseconds(from: stopped, to: recognized) }
    var deliveryMilliseconds: Double? { milliseconds(from: stopped, to: delivered) }

    private func milliseconds(from start: TimeInterval?, to end: TimeInterval?) -> Double? {
        guard let start, let end else { return nil }
        return max(0, (end - start) * 1000)
    }
}
