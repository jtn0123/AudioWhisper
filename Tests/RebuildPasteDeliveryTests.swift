import XCTest
@testable import AudioWhisper

/// Paste confirmation (watch the field, fall back to Edit ▸ Paste once) and
/// cursor-context fitting, driven through the real session and PasteManager
/// with Accessibility replaced by a scripted text field.
@MainActor
final class RebuildPasteDeliveryTests: IsolatedXCTestCase {
    private var session: RebuildSession!
    private var transcriptText = "We should go"
    private var copies: [String] = []
    private var events = 0
    private var menuPresses = 0
    private var field: FocusedTextState?
    private var pasteLands = true
    private var menuLands = true
    private var menuAvailable = true
    private var readsAfterPaste: Int?
    private var notifications = 0
    private var notifiesTransiently = false
    private var watchersStopped = 0
    private var keeper: ClipboardKeeper?
    private var announcements: [String] = []
    private var restoreWait: ((Duration) async throws -> Void)?

    private let empty = FocusedTextState(length: 15, selection: NSRange(location: 15, length: 0), preceding: "I told her that")
    private let pasted = FocusedTextState(length: 28, selection: NSRange(location: 28, length: 0), preceding: "that we should go")

    override func setUp() {
        super.setUp()
        AppDefaults.enableSmartPaste = true
        AppDefaults.matchCursorContext = true
        AppDefaults.playCompletionSound = false
        transcriptText = "We should go"
        copies = []
        events = 0
        menuPresses = 0
        field = empty
        pasteLands = true
        menuLands = true
        menuAvailable = true
        readsAfterPaste = nil
        notifications = 0
        notifiesTransiently = false
        watchersStopped = 0
        keeper = nil
        announcements = []
        restoreWait = nil
        session = makeSession()
    }

    override func tearDown() {
        session.cancel()
        session = nil
        super.tearDown()
    }

    func testConfirmedPasteNeedsNoFallback() async throws {
        try await recordAndDeliver()
        XCTAssertEqual(events, 1)
        XCTAssertEqual(menuPresses, 0)
        XCTAssertNil(session.notice)
        XCTAssertEqual(session.deliveryStatus, .pasted(clipboardRestored: false))
    }

    func testSwallowedShortcutFallsBackToTheEditMenuOnce() async throws {
        pasteLands = false
        try await recordAndDeliver()
        XCTAssertEqual(events, 1)
        XCTAssertEqual(menuPresses, 1)
        XCTAssertNil(session.notice, "the fallback delivered, so there is nothing to report")
    }

    func testFailedFallbackTellsTheUserToPasteManually() async throws {
        pasteLands = false
        menuLands = false
        try await recordAndDeliver()
        XCTAssertEqual(menuPresses, 1, "the fallback is attempted exactly once")
        XCTAssertEqual(session.notice, "Copied. Paste manually with Command V.")
    }

    func testMissingPasteMenuItemTellsTheUserToPasteManually() async throws {
        pasteLands = false
        menuAvailable = false
        try await recordAndDeliver()
        XCTAssertEqual(session.notice, "Copied. Paste manually with Command V.")
    }

    func testUnreadableFieldTrustsTheShortcutAndNeverPastesTwice() async throws {
        field = nil
        pasteLands = false
        try await recordAndDeliver()
        XCTAssertEqual(events, 1)
        XCTAssertEqual(menuPresses, 0)
        XCTAssertEqual(watchersStopped, 0, "an unreadable field is not observed")
        XCTAssertNil(session.notice)
        XCTAssertEqual(copies, ["We should go"], "no context means no fitting")
        XCTAssertEqual(session.deliveryStatus, .unverified(clipboardRestored: false))
    }

    func testChangeSeenOnlyByNotificationsCountsAsDelivered() async throws {
        // A web editor that empties its hidden input at once looks unchanged
        // to polling; pasting again would leave two copies in the document.
        pasteLands = false
        notifiesTransiently = true
        try await recordAndDeliver()
        XCTAssertEqual(menuPresses, 0)
        XCTAssertNil(session.notice)
        XCTAssertEqual(watchersStopped, 1, "the observer is always torn down")
    }

    func testFieldThatStopsBeingReadableIsNotTreatedAsUnchanged() async throws {
        pasteLands = false
        readsAfterPaste = 0
        try await recordAndDeliver()
        XCTAssertEqual(menuPresses, 0, "losing sight of the field is not evidence the paste failed")
        XCTAssertNil(session.notice)
    }

    func testMidSentenceInsertionIsFittedBeforePasting() async throws {
        try await recordAndDeliver()
        XCTAssertEqual(copies, ["We should go", " we should go"])
        XCTAssertEqual(session.transcript, "We should go", "the record page keeps the transcript as recognised")
    }

    func testContextMatchingCanBeTurnedOff() async throws {
        AppDefaults.matchCursorContext = false
        try await recordAndDeliver()
        XCTAssertEqual(copies, ["We should go"])
    }

    func testUnreadableContextIsLeftAlone() async throws {
        field = FocusedTextState(length: 3, selection: nil, preceding: nil)
        try await recordAndDeliver()
        XCTAssertEqual(copies, ["We should go"])
    }

    // MARK: - Fixture

    private func recordAndDeliver() async throws {
        session.toggleRecording()
        session.finishRecording()
        try await waitFor { self.session.phase == .completed && self.session.deliveryStatus != .delivering }
    }

    private func makeSession() -> RebuildSession {
        var services = RebuildSessionServices(
            start: { _ in true },
            stop: { FileManager.default.temporaryDirectory.appendingPathComponent("delivery-\(UUID()).wav") },
            cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: self.transcriptText, correctionOutcome: nil) },
            copy: { self.copies.append($0) }, save: { _, _, _ in }, interruptionSource: nil)
        services.clipboardKeeper = { self.keeper }
        services.announce = { self.announcements.append($0) }
        services.capturePasteDestination = {
            RebuildPasteDestination(
                processIdentifier: 111, bundleIdentifier: "fixture.destination",
                activate: { true }, isTerminated: { false }, foregroundPID: { 111 })
        }
        let paste = PasteManager(
            accessibilityManager: AccessibilityPermissionManager(permissionCheck: { true }),
            foregroundPID: { 111 }, pasteEvent: { self.firePaste() })
        let access = FocusedTextAccess(
            read: { _ in self.readField() }, pressPasteMenuItem: { _ in self.pressMenu() },
            watchChanges: { _ in
                FocusedTextChanges(count: { self.notifications }, stop: { self.watchersStopped += 1 })
            })
        var delivery = RebuildPasteDelivery(
            focusedText: access, confirmationWindow: .milliseconds(120), pollInterval: .milliseconds(10),
            restoreGrace: .milliseconds(30))
        if let restoreWait { delivery.waitBeforeRestore = restoreWait }
        let session = RebuildSession(services: services, paste: paste, delivery: delivery)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        return session
    }

    private func firePaste() {
        events += 1
        if pasteLands, field != nil { field = pasted }
        if pasteLands || notifiesTransiently { notifications += 1 }
    }

    private func pressMenu() -> Bool {
        menuPresses += 1
        if menuLands, menuAvailable { field = pasted }
        return menuAvailable
    }

    private func readField() -> FocusedTextState? {
        guard events > 0, let remaining = readsAfterPaste else { return field }
        guard remaining > 0 else { return nil }
        readsAfterPaste = remaining - 1
        return field
    }

    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}

// MARK: - Giving the clipboard back

extension RebuildPasteDeliveryTests {
    func testSelectedReferenceUsesCopyOnlyAndDoesNotReplaceTheSelection() async throws {
        let previous = AppDefaults.currentDictationSettings
        defer { AppDefaults.currentDictationSettings = previous }
        var settings = previous
        settings.cleanup = .localMLX
        settings.writing.contextSource = .selectedText
        AppDefaults.currentDictationSettings = settings
        session.toggleRecording()
        session.finishRecording()
        try await waitFor { self.session.deliveryStatus == .copied }
        XCTAssertEqual(events, 0)
        XCTAssertEqual(menuPresses, 0)
        XCTAssertEqual(copies, ["We should go"])
        XCTAssertEqual(session.recordingDestinationName, "Clipboard")
    }

    func testTheClipboardComesBackAfterAConfirmedPaste() async throws {
        let board = lendableBoard(holding: "what I had copied")
        defer { board.releaseGlobally() }
        try await recordAndDeliver()
        XCTAssertEqual(board.string(forType: .string), "what I had copied")
        XCTAssertEqual(copies, [], "a lent clipboard is written through the keeper only")
        XCTAssertEqual(session.deliveryStatus, .pasted(clipboardRestored: true))
        XCTAssertEqual(announcements, ["Recording started.", "Recording stopped. Transcribing.",
                                      session.deliveryStatus.announcement])
        XCTAssertTrue(session.deliveryStatus.detail.contains("previous clipboard was restored"))
    }

    func testAPasteThatCouldNotBeSeenLandingGivesTheClipboardBackAfterTheGrace() async throws {
        field = nil
        let board = lendableBoard(holding: "what I had copied")
        defer { board.releaseGlobally() }
        try await recordAndDeliver()
        XCTAssertEqual(board.string(forType: .string), "what I had copied")
        XCTAssertEqual(session.deliveryStatus, .unverified(clipboardRestored: true))
    }

    func testAFailedPasteLeavesTheTranscriptToPasteByHand() async throws {
        pasteLands = false
        menuLands = false
        let board = lendableBoard(holding: "what I had copied")
        defer { board.releaseGlobally() }
        try await recordAndDeliver()
        XCTAssertEqual(session.notice, "Copied. Paste manually with Command V.")
        XCTAssertEqual(board.string(forType: .string), " we should go", "the fitted transcript, ready to paste")
        XCTAssertEqual(session.deliveryStatus, .manual)
    }

    func testUserCopyDuringDeliveryIsPreservedAndNeverReportedAsRestored() async throws {
        field = nil
        var releaseRestore: CheckedContinuation<Void, Never>?
        restoreWait = { _ in await withCheckedContinuation { releaseRestore = $0 } }
        session = makeSession()
        let board = lendableBoard(holding: "before")
        defer { board.releaseGlobally() }
        session.toggleRecording()
        session.finishRecording()
        try await waitFor { releaseRestore != nil }
        board.clearContents()
        board.setString("new user copy", forType: .string)
        releaseRestore?.resume()
        try await waitFor { self.session.deliveryStatus != .delivering }
        XCTAssertEqual(board.string(forType: .string), "new user copy")
        XCTAssertEqual(session.deliveryStatus, .unverified(clipboardRestored: false))
    }

    func testExpressModeAnnouncesWithoutShowingTheRecorder() async throws {
        AppDefaults.immediateRecording = true
        defer { AppDefaults.immediateRecording = false }
        var shows = 0
        session.showRecorder = { shows += 1 }
        try await recordAndDeliver()
        XCTAssertEqual(shows, 0)
        XCTAssertEqual(announcements.count, 3)
        XCTAssertEqual(announcements.first, "Recording started.")
        XCTAssertEqual(announcements.last, session.deliveryStatus.announcement)
    }

    func testCancellationHasOneSessionAnnouncement() {
        session.toggleRecording()
        session.cancel()
        session.cancel()
        XCTAssertEqual(announcements, ["Recording started.", "Dictation cancelled."])
    }

    private func lendableBoard(holding text: String) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("audiowhisper.tests.\(UUID().uuidString)"))
        board.clearContents()
        board.setString(text, forType: .string)
        keeper = ClipboardKeeper(pasteboard: board)
        return board
    }
}
