import XCTest
@testable import AudioWhisper

@MainActor
final class ProviderDownloadRetryTests: XCTestCase {
    func testRetryDownloadsTheFailedModelInsteadOfAnotherActiveModel() {
        let state = ProviderSettingsState()
        state.beginDownload(.base)
        state.finishDownload(.base, error: "Connection lost")
        state.downloadStartTime[.tiny] = Date()
        var retried: WhisperModel?
        state.retryFailedDownload { retried = $0 }
        XCTAssertEqual(retried, .base)
        XCTAssertNil(state.downloadStartTime[.base])
        XCTAssertNotNil(state.downloadStartTime[.tiny])
    }

}
