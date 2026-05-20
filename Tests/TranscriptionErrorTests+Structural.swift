import XCTest
@testable import AudioWhisper

// Structural NSError matcher tests (M13), split out of TranscriptionErrorTests
// to keep each type within SwiftLint body-length limits.
extension TranscriptionErrorTests {

    // MARK: - M13 Structural Matcher Tests

    /// M13: URLError.timedOut routes to .networkTimeout regardless of localization.
    func testFromErrorMapsURLErrorTimedOutToNetworkTimeout() {
        let urlError = URLError(.timedOut)
        let result = TranscriptionError.from(error: urlError)
        guard case .networkTimeout = result else {
            XCTFail("Expected .networkTimeout for URLError.timedOut, got: \(result)")
            return
        }
    }

    /// M13: URLError.notConnectedToInternet routes to .networkConnectionError.
    func testFromErrorMapsURLErrorNotConnectedToInternet() {
        let urlError = URLError(.notConnectedToInternet)
        let result = TranscriptionError.from(error: urlError)
        guard case .networkConnectionError = result else {
            XCTFail("Expected .networkConnectionError for URLError.notConnectedToInternet, got: \(result)")
            return
        }
    }

    /// M13: NSURLErrorDomain timeouts route correctly via NSError shape too.
    func testFromErrorMapsNSURLDomainTimeout() {
        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let result = TranscriptionError.from(error: nsError)
        guard case .networkTimeout = result else {
            XCTFail("Expected .networkTimeout for NSURLErrorDomain NSURLErrorTimedOut, got: \(result)")
            return
        }
    }

    /// M13: An unknown domain falls back to substring matching using
    /// `localizedDescription` — verify the fallback path is still intact.
    func testFromErrorFallsBackToMessageMatcher() {
        let nsError = NSError(
            domain: "ai.audiowhisper.SomethingUnknown",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "API key is invalid"]
        )
        let result = TranscriptionError.from(error: nsError)
        guard case .invalidAPIKey = result else {
            XCTFail("Expected .invalidAPIKey from message-based fallback, got: \(result)")
            return
        }
    }
}
