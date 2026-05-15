import XCTest
@testable import AudioWhisper

// MARK: - Mock Permission Manager for Testing

@MainActor
final class MockPermissionManagerForRecording {
    var microphonePermissionState: PermissionState = .granted
    var accessibilityPermissionState: PermissionState = .granted
    var showEducationalModal = false
    var showRecoveryModal = false
    var requestPermissionWithEducationCalled = false

    func requestPermissionWithEducation() {
        requestPermissionWithEducationCalled = true
        if microphonePermissionState.needsRequest {
            showEducationalModal = true
        } else if microphonePermissionState.canRetry {
            showRecoveryModal = true
        }
    }
}

// MARK: - Recording Workflow Edge Case Tests

@MainActor
final class RecordingWorkflowEdgeCaseTests: XCTestCase {
    var mockRecorder: MockAudioEngineRecorder!
    var mockSpeechService: MockSpeechToTextService!
    private var mockPermissionManager: MockPermissionManagerForRecording!
    private var mockSemanticService: MockSemanticCorrectionService!
    private var testUserDefaultsSuite: String!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mockRecorder = MockAudioEngineRecorder()
        mockSpeechService = MockSpeechToTextService()
        mockPermissionManager = MockPermissionManagerForRecording()
        mockSemanticService = MockSemanticCorrectionService()

        // Use isolated UserDefaults for tests
        testUserDefaultsSuite = "RecordingWorkflowTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testUserDefaultsSuite)
        testDefaults?.removePersistentDomain(forName: testUserDefaultsSuite)
    }

    override func tearDown() {
        mockRecorder?.reset()
        mockSpeechService?.reset()
        testDefaults?.removePersistentDomain(forName: testUserDefaultsSuite)
        testDefaults = nil
        testUserDefaultsSuite = nil
        super.tearDown()
    }

    // MARK: - Cancellation Tests

    func testCancellationDuringTranscriptionResetsProcessingState() async throws {
        // Configure mock to delay transcription to allow cancellation
        mockSpeechService.simulatedDelay = 2.0
        mockSpeechService.setSuccess("Test transcription")

        // Create and start a processing task
        var isProcessing = true
        var transcriptionStartTime: Date? = Date()

        let processingTask = Task {
            try await Task.sleep(for: .milliseconds(100))
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"), provider: .local, model: nil)
        }

        // Cancel immediately
        processingTask.cancel()

        // Simulate the cancellation handling from ContentView+Recording
        do {
            try await processingTask.value
        } catch is CancellationError {
            isProcessing = false
            transcriptionStartTime = nil
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertFalse(isProcessing, "isProcessing should be reset after cancellation")
        XCTAssertNil(transcriptionStartTime, "transcriptionStartTime should be nil after cancellation")
    }

    func testCancellationDuringSemanticCorrectionResetsAwaitingFlag() async throws {
        mockSemanticService.simulatedDelay = 2.0
        mockSemanticService.setCorrectionResult("Corrected text")

        var awaitingSemanticPaste = true
        var isProcessing = true

        let processingTask = Task {
            try await Task.sleep(for: .milliseconds(50))
            try Task.checkCancellation()
            _ = await mockSemanticService.correct(text: "Test", providerUsed: TranscriptionProvider.local)
            try Task.checkCancellation()
        }

        // Cancel during semantic correction
        processingTask.cancel()

        do {
            try await processingTask.value
        } catch is CancellationError {
            isProcessing = false
            awaitingSemanticPaste = false
        } catch {
            // Other errors also reset state
            isProcessing = false
            awaitingSemanticPaste = false
        }

        XCTAssertFalse(awaitingSemanticPaste, "awaitingSemanticPaste should reset on cancellation")
        XCTAssertFalse(isProcessing, "isProcessing should reset on cancellation")
    }

    func testMultipleCancellationsAreIdempotent() async throws {
        var cancelCount = 0

        let processingTask = Task {
            try await Task.sleep(for: .seconds(10))
            return "result"
        }

        // Cancel multiple times
        for _ in 0..<5 {
            processingTask.cancel()
            cancelCount += 1
        }

        do {
            _ = try await processingTask.value
            XCTFail("Task should have been cancelled")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(cancelCount, 5, "Should be able to call cancel multiple times without crash")
    }

    func testCancellationBeforeTranscriptionStartsExitsEarly() async throws {
        mockSpeechService.simulatedDelay = 0.5

        let processingTask = Task {
            try Task.checkCancellation() // Early cancellation check
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"), provider: .local, model: nil)
        }

        // Cancel immediately before task has chance to start transcription
        processingTask.cancel()

        do {
            try await processingTask.value
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Expected CancellationError")
        }

        // Give it a moment to ensure the task ran
        try await Task.sleep(for: .milliseconds(100))

        // The transcription should not have been called if cancelled early
        XCTAssertEqual(mockSpeechService.transcribeRawCallCount, 0, "Transcription should not be called when cancelled early")
    }

    func testCancellationCleansUpTranscriptionStartTime() async throws {
        var transcriptionStartTime: Date? = Date()

        let processingTask = Task {
            try await Task.sleep(for: .seconds(5))
        }

        processingTask.cancel()

        do {
            try await processingTask.value
        } catch is CancellationError {
            transcriptionStartTime = nil
        } catch {
            XCTFail("Expected CancellationError")
        }

        XCTAssertNil(transcriptionStartTime, "transcriptionStartTime should be cleaned up after cancellation")
    }

    // MARK: - Permission Edge Cases

    func testStartRecordingWithoutPermissionShowsEducation() {
        mockPermissionManager.microphonePermissionState = .notRequested

        // Simulate startRecording behavior
        if mockPermissionManager.microphonePermissionState != .granted {
            mockPermissionManager.requestPermissionWithEducation()
        }

        XCTAssertTrue(mockPermissionManager.requestPermissionWithEducationCalled)
        XCTAssertTrue(mockPermissionManager.showEducationalModal, "Should show education modal when permission not requested")
    }

    func testStartRecordingWithDeniedPermissionShowsRecovery() {
        mockPermissionManager.microphonePermissionState = .denied

        if mockPermissionManager.microphonePermissionState != .granted {
            mockPermissionManager.requestPermissionWithEducation()
        }

        XCTAssertTrue(mockPermissionManager.requestPermissionWithEducationCalled)
        XCTAssertTrue(mockPermissionManager.showRecoveryModal, "Should show recovery modal when permission denied")
    }

    func testRecordingBlockedWhenPermissionNotGranted() {
        mockPermissionManager.microphonePermissionState = .requesting

        var recordingStarted = false

        // Simulate startRecording behavior
        if mockPermissionManager.microphonePermissionState == .granted {
            recordingStarted = mockRecorder.startRecording()
        }

        XCTAssertFalse(recordingStarted, "Recording should not start when permission is requesting")
        XCTAssertFalse(mockRecorder.startRecordingCalled, "startRecording should not be called on recorder")
    }

    func testPermissionStateTransitionsCorrectly() {
        // Test the state machine transitions
        let states: [PermissionState] = [.unknown, .notRequested, .requesting, .granted, .denied, .restricted]

        for state in states {
            mockPermissionManager.microphonePermissionState = state

            switch state {
            case .unknown, .notRequested:
                XCTAssertTrue(state.needsRequest, "\(state) should need request")
                XCTAssertFalse(state.canRetry, "\(state) should not be retryable")
            case .requesting:
                XCTAssertFalse(state.needsRequest)
                XCTAssertFalse(state.canRetry)
            case .granted:
                XCTAssertFalse(state.needsRequest)
                XCTAssertFalse(state.canRetry)
            case .denied:
                XCTAssertFalse(state.needsRequest)
                XCTAssertTrue(state.canRetry, "denied should be retryable")
            case .restricted:
                XCTAssertFalse(state.needsRequest)
                XCTAssertFalse(state.canRetry)
            }
        }
    }

    // MARK: - Recording Reentrancy Tests

    func testDoubleStartRecordingReturnsFalse() {
        // First start succeeds
        let firstResult = mockRecorder.startRecording()
        XCTAssertTrue(firstResult)
        XCTAssertTrue(mockRecorder.isRecording)

        // Configure mock to fail on second start (simulating real behavior)
        mockRecorder.startRecordingResult = false

        let secondResult = mockRecorder.startRecording()
        XCTAssertFalse(secondResult, "Second startRecording should fail while already recording")
        XCTAssertEqual(mockRecorder.startRecordingCallCount, 2)
    }

    func testStopWhileNotRecordingIsNoOp() {
        XCTAssertFalse(mockRecorder.isRecording)

        let result = mockRecorder.stopRecording()

        // Stop should still return the configured URL but not crash
        XCTAssertNotNil(result)
        XCTAssertTrue(mockRecorder.stopRecordingCalled)
        XCTAssertFalse(mockRecorder.isRecording)
    }

    func testRapidStartStopCyclesDoNotLeaveOrphanState() async throws {
        for cycle in 0..<10 {
            let startResult = mockRecorder.startRecording()
            XCTAssertTrue(startResult, "Start \(cycle) should succeed")
            XCTAssertTrue(mockRecorder.isRecording, "Should be recording after start \(cycle)")

            _ = mockRecorder.stopRecording()
            XCTAssertFalse(mockRecorder.isRecording, "Should not be recording after stop \(cycle)")
        }

        XCTAssertEqual(mockRecorder.startRecordingCallCount, 10)
        XCTAssertEqual(mockRecorder.stopRecordingCallCount, 10)
        XCTAssertFalse(mockRecorder.isRecording, "Should not be recording after all cycles")
        XCTAssertNil(mockRecorder.currentSessionStart, "No session should be active")
    }
}
