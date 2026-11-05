import XCTest

@testable import AudioWhisper

final class RebuildErrorTextTests: XCTestCase {
    private func message(_ error: Error) -> String { RebuildErrorText.userMessage(for: error) }

    func testDaemonFailuresBecomePlainSentencesWithANextStep() {
        XCTAssertTrue(message(MLDaemonError.timeout).hasPrefix("The local model took too long"))
        XCTAssertTrue(message(MLDaemonError.restartLimitReached).contains("Check installation"))
        for error in [MLDaemonError.writeFailed, .scriptNotFound, .daemonUnavailable("exited (9)"), .invalidResponse("x")] {
            let text = message(error)
            XCTAssertTrue(text.contains("isn't responding"), text)
            XCTAssertFalse(text.contains("daemon"), "Internal names stay out of the UI: \(text)")
        }
    }

    func testPythonErrorsAreRecognised() {
        let memory = MLDaemonError.remoteError("[METAL] Command buffer execution failed: Insufficient Memory")
        let missing = MLDaemonError.remoteError("LocalEntryNotFoundError: Cannot find the requested files in the local cache")
        let other = MLDaemonError.remoteError("ValueError: something internal")
        XCTAssertTrue(message(memory).contains("ran out of memory"))
        XCTAssertTrue(message(missing).contains("isn't fully downloaded"))
        XCTAssertTrue(message(other).hasPrefix("The local model reported a problem"))
        XCTAssertFalse(message(other).contains("ValueError"))
    }

    func testWrappedErrorsAreUnwrapped() {
        let wrapped = SpeechToTextError.localTranscriptionFailed(MLDaemonError.timeout)
        XCTAssertEqual(message(wrapped), message(MLDaemonError.timeout))
        let underlying = NSError(domain: "Outer", code: 1, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        ])
        XCTAssertTrue(message(underlying).hasPrefix("You're offline"))
    }

    func testFileSystemErrors() {
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        XCTAssertTrue(message(cocoa).hasPrefix("Your disk is full"))
        XCTAssertTrue(message(posix).hasPrefix("Your disk is full"))
    }

    func testMessagesTheAppAlreadyWroteAreKept() {
        let own = NSError(domain: "AudioWhisper", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "No speech was recognized. Try again or record clearer audio."
        ])
        XCTAssertEqual(message(own), own.localizedDescription)
        XCTAssertEqual(message(SpeechToTextError.noSpeechDetected), SpeechToTextError.noSpeechDetected.localizedDescription)
    }

    func testLocalTranscriptionCopyNoLongerMentionsCloud() {
        XCTAssertFalse(LocalizedStrings.Errors.localTranscriptionFailed.contains("cloud"))
    }
}
