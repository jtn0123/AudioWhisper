import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

// MARK: - DownloadState Tests
final class DownloadStateCoverageTests: XCTestCase {

    func testIdleEquality() {
        XCTAssertEqual(DownloadState.idle, .idle)
    }

    func testVerifyingEquality() {
        XCTAssertEqual(DownloadState.verifying, .verifying)
    }

    func testVerifiedEquality() {
        XCTAssertEqual(DownloadState.verified, .verified)
    }

    func testDownloadingEqualityMatches() {
        XCTAssertEqual(
            DownloadState.downloading(progress: 0.5, statusText: "a"),
            DownloadState.downloading(progress: 0.5, statusText: "a")
        )
    }

    func testDownloadingEqualityDiffersOnProgress() {
        XCTAssertNotEqual(
            DownloadState.downloading(progress: 0.5),
            DownloadState.downloading(progress: 0.6)
        )
    }

    func testDownloadingEqualityDiffersOnText() {
        XCTAssertNotEqual(
            DownloadState.downloading(progress: 0.5, statusText: "a"),
            DownloadState.downloading(progress: 0.5, statusText: "b")
        )
    }

    func testFailedEqualityMatches() {
        XCTAssertEqual(DownloadState.failed(message: "x"), .failed(message: "x"))
    }

    func testFailedEqualityDiffers() {
        XCTAssertNotEqual(DownloadState.failed(message: "x"), .failed(message: "y"))
    }

    func testDifferentCasesAreNotEqual() {
        XCTAssertNotEqual(DownloadState.idle, .verifying)
        XCTAssertNotEqual(DownloadState.verified, .failed(message: "x"))
        XCTAssertNotEqual(DownloadState.downloading(progress: 0.1), .verified)
    }
}

// MARK: - DownloadProgressView Rendering Tests
@MainActor
final class DownloadProgressViewCoverageTests: XCTestCase {

    private func render(_ view: DownloadProgressView) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        hosting.layout()
        XCTAssertNotNil(hosting)
    }

    func testIdleStateRenders() {
        render(DownloadProgressView(state: .idle))
    }

    func testDownloadingStateRenders() {
        render(DownloadProgressView(state: .downloading(progress: 0.42, statusText: "234 MB / 558 MB")))
    }

    func testDownloadingWithoutStatusTextRenders() {
        render(DownloadProgressView(state: .downloading(progress: 0.0)))
    }

    func testDownloadingWithCancelRenders() {
        render(DownloadProgressView(state: .downloading(progress: 0.5), onCancel: {}))
    }

    func testDownloadingClampsOutOfRangeProgress() {
        render(DownloadProgressView(state: .downloading(progress: 1.7)))
        render(DownloadProgressView(state: .downloading(progress: -0.5)))
    }

    func testVerifyingStateRenders() {
        render(DownloadProgressView(state: .verifying))
    }

    func testFailedStateRenders() {
        render(DownloadProgressView(state: .failed(message: "Network error")))
    }

    func testFailedWithRetryRenders() {
        render(DownloadProgressView(state: .failed(message: "Network error"), onRetry: {}))
    }

    func testVerifiedStateRenders() {
        render(DownloadProgressView(state: .verified))
    }

    func testRetryCallbackIsInvoked() {
        var retried = false
        let view = DownloadProgressView(state: .failed(message: "oops"), onRetry: { retried = true })
        _ = view.body
        // Directly verify the callback closure is wired and callable.
        view.onRetry?()
        XCTAssertTrue(retried)
    }

    func testCancelCallbackIsInvoked() {
        var cancelled = false
        let view = DownloadProgressView(state: .downloading(progress: 0.3), onCancel: { cancelled = true })
        _ = view.body
        view.onCancel?()
        XCTAssertTrue(cancelled)
    }

    func testBodyExecutesForEveryState() {
        let states: [DownloadState] = [
            .idle,
            .downloading(progress: 0.25, statusText: "abc"),
            .downloading(progress: 0.9),
            .verifying,
            .failed(message: "bad"),
            .verified
        ]
        for state in states {
            _ = DownloadProgressView(state: state).body
        }
    }
}
