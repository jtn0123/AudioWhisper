import Foundation
@testable import AudioWhisper

/// Mock implementation for testing semantic correction flows
final class MockSemanticCorrectionService: @unchecked Sendable {
    /// The result to return from correct(). If nil, returns the original text.
    var correctionResult: String?

    /// Whether correction should be applied
    var shouldApplyCorrection = true

    /// Track calls for assertions
    private(set) var correctCallCount = 0
    private(set) var lastText: String?
    private(set) var lastProvider: TranscriptionProvider?
    private(set) var lastSourceAppBundleId: String?

    /// Simulated delay for async testing
    var simulatedDelay: TimeInterval = 0

    /// Error to throw if set
    var errorToThrow: Error?

    func correct(text: String, providerUsed: TranscriptionProvider, sourceAppBundleId: String? = nil) async -> String {
        correctCallCount += 1
        lastText = text
        lastProvider = providerUsed
        lastSourceAppBundleId = sourceAppBundleId

        if simulatedDelay > 0 {
            try? await Task.sleep(for: .milliseconds(Int(simulatedDelay * 1000)))
        }

        if shouldApplyCorrection, let result = correctionResult {
            return result
        }
        return text
    }

    // MARK: - Test Helpers

    func reset() {
        correctionResult = nil
        shouldApplyCorrection = true
        correctCallCount = 0
        lastText = nil
        lastProvider = nil
        lastSourceAppBundleId = nil
        simulatedDelay = 0
        errorToThrow = nil
    }

    func setCorrectionResult(_ text: String) {
        correctionResult = text
        shouldApplyCorrection = true
    }

    func disableCorrection() {
        shouldApplyCorrection = false
    }
}
