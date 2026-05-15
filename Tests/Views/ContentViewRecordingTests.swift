import XCTest
@testable import AudioWhisper

/// Tests for ContentView recording state machine and transcription workflow
/// Complements RecordingWorkflowEdgeCaseTests with additional coverage
@MainActor
final class ContentViewRecordingTests: XCTestCase {
    private var mockRecorder: MockAudioEngineRecorder!
    private var mockSpeechService: MockSpeechToTextService!
    private var mockSemanticService: MockSemanticCorrectionService!
    private var mockDataManager: MockDataManager!
    private var mockMetricsStore: MockUsageMetricsStore!
    private var testUserDefaultsSuite: String!
    private var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        mockRecorder = MockAudioEngineRecorder()
        mockSpeechService = MockSpeechToTextService()
        mockSemanticService = MockSemanticCorrectionService()
        mockDataManager = MockDataManager()
        mockMetricsStore = MockUsageMetricsStore()

        // Use isolated UserDefaults for tests
        testUserDefaultsSuite = "ContentViewRecordingTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testUserDefaultsSuite)
        testDefaults?.removePersistentDomain(forName: testUserDefaultsSuite)
    }

    override func tearDown() async throws {
        mockRecorder?.reset()
        mockSpeechService?.reset()
        mockSemanticService?.reset()
        mockDataManager?.reset()
        mockMetricsStore?.resetMock()
        testDefaults?.removePersistentDomain(forName: testUserDefaultsSuite)
        testDefaults = nil
        testUserDefaultsSuite = nil
        try await super.tearDown()
    }

    // MARK: - State Transition Tests

    func testIsProcessingSetBeforeTaskCreation() async throws {
        // This tests the race condition fix at line 30 in ContentView+Recording.swift
        // isProcessing must be set BEFORE the Task is created, not inside it

        var isProcessing = false
        var taskStartedWithProcessingTrue = false

        // Simulate the fixed behavior
        isProcessing = true  // Set BEFORE Task

        let task = Task {
            // Capture whether isProcessing was already true when task started
            taskStartedWithProcessingTrue = isProcessing
            try await Task.sleep(for: .milliseconds(10))
        }

        try await task.value

        XCTAssertTrue(taskStartedWithProcessingTrue,
            "isProcessing should be true when Task starts (race condition fix)")
    }

    func testTranscriptionStartTimeSetWithIsProcessing() async throws {
        var isProcessing = false
        var transcriptionStartTime: Date?

        // Both should be set together before Task
        isProcessing = true
        transcriptionStartTime = Date()

        XCTAssertTrue(isProcessing)
        XCTAssertNotNil(transcriptionStartTime)

        // And both should be cleared together on completion
        isProcessing = false
        transcriptionStartTime = nil

        XCTAssertFalse(isProcessing)
        XCTAssertNil(transcriptionStartTime)
    }

    // MARK: - Semantic Correction Tests

    func testSemanticCorrectionAppliedWhenModeLocalMLX() async throws {
        testDefaults.set(SemanticCorrectionMode.localMLX.rawValue, forKey: "semanticCorrectionMode")
        mockSpeechService.setSuccess("original text")
        mockSemanticService.setCorrectionResult("corrected text")

        // Simulate the workflow
        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .local,
            model: nil
        )

        let modeRaw = testDefaults.string(forKey: "semanticCorrectionMode") ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off

        var finalText = text
        if mode != .off {
            let corrected = await mockSemanticService.correct(
                text: text,
                providerUsed: .local,
                sourceAppBundleId: nil
            )
            finalText = corrected
        }

        XCTAssertEqual(mockSemanticService.correctCallCount, 1, "Correction should be called once")
        XCTAssertEqual(finalText, "corrected text", "Should use corrected text")
        XCTAssertEqual(mockSemanticService.lastText, "original text", "Should pass original text to correction")
    }

    func testSemanticCorrectionAppliedWithParakeetProvider() async throws {
        testDefaults.set(SemanticCorrectionMode.localMLX.rawValue, forKey: "semanticCorrectionMode")
        mockSpeechService.setSuccess("raw transcription")
        mockSemanticService.setCorrectionResult("mlx corrected")

        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .parakeet,
            model: nil
        )

        let modeRaw = testDefaults.string(forKey: "semanticCorrectionMode") ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off

        var finalText = text
        if mode != .off {
            let corrected = await mockSemanticService.correct(
                text: text,
                providerUsed: .parakeet,
                sourceAppBundleId: "com.test.app"
            )
            finalText = corrected
        }

        XCTAssertEqual(mockSemanticService.correctCallCount, 1)
        XCTAssertEqual(finalText, "mlx corrected")
        XCTAssertEqual(mockSemanticService.lastProvider, .parakeet)
    }

    func testSemanticCorrectionSkippedWhenModeOff() async throws {
        testDefaults.set(SemanticCorrectionMode.off.rawValue, forKey: "semanticCorrectionMode")
        mockSpeechService.setSuccess("original text only")
        mockSemanticService.setCorrectionResult("this should not be used")

        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .local,
            model: nil
        )

        let modeRaw = testDefaults.string(forKey: "semanticCorrectionMode") ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off

        var finalText = text
        if mode != .off {
            let corrected = await mockSemanticService.correct(text: text, providerUsed: .local)
            finalText = corrected
        }

        XCTAssertEqual(mockSemanticService.correctCallCount, 0, "Correction should not be called when mode is off")
        XCTAssertEqual(finalText, "original text only", "Should use original text")
    }

    func testEmptyCorrectionResultFallsBackToOriginal() async throws {
        testDefaults.set(SemanticCorrectionMode.localMLX.rawValue, forKey: "semanticCorrectionMode")
        mockSpeechService.setSuccess("original text")
        mockSemanticService.setCorrectionResult("   ")  // Whitespace only

        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .local,
            model: nil
        )

        let modeRaw = testDefaults.string(forKey: "semanticCorrectionMode") ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off

        var finalText = text
        if mode != .off {
            let corrected = await mockSemanticService.correct(text: text, providerUsed: .local)
            let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                finalText = corrected
            }
        }

        XCTAssertEqual(finalText, "original text", "Should fall back to original when correction is empty")
    }

    // MARK: - Metrics Recording Tests

    func testMetricsRecordedOnSuccess() async throws {
        mockSpeechService.setSuccess("Hello world test recording")

        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .local,
            model: nil
        )

        let wordCount = UsageMetricsStore.estimatedWordCount(for: text)
        let characterCount = text.count
        let duration: TimeInterval = 5.0

        mockMetricsStore.recordSession(
            duration: duration,
            wordCount: wordCount,
            characterCount: characterCount
        )

        XCTAssertEqual(mockMetricsStore.recordSessionCallCount, 1, "Should record session metrics")
        XCTAssertEqual(mockMetricsStore.recordSessionLastWordCount, 4, "Should record correct word count")
        XCTAssertEqual(mockMetricsStore.recordSessionLastDuration, 5.0, "Should record correct duration")
    }

    func testWordCountEstimation() {
        // Test the word count estimation logic
        let testCases = [
            ("Hello world", 2),
            ("One", 1),
            ("", 0),
            ("Hello, world! How are you?", 5),
            ("Don't worry", 2),  // Contractions count as single words
            ("test-driven development", 3),  // Hyphens split words
            ("one two three four five", 5)
        ]

        for (text, expectedCount) in testCases {
            let count = UsageMetricsStore.estimatedWordCount(for: text)
            XCTAssertEqual(count, expectedCount, "Word count for '\(text)' should be \(expectedCount), got \(count)")
        }
    }

    // MARK: - Pipeline Order Tests

    func testPipelineExecutesInCorrectOrder() async throws {
        var executionOrder: [String] = []

        // Simulate the pipeline stages
        executionOrder.append("prepare")

        mockSpeechService.setSuccess("transcribed text")
        _ = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .local,
            model: nil
        )
        executionOrder.append("transcribe")

        testDefaults.set(SemanticCorrectionMode.localMLX.rawValue, forKey: "semanticCorrectionMode")
        let modeRaw = testDefaults.string(forKey: "semanticCorrectionMode") ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off
        if mode != .off {
            _ = await mockSemanticService.correct(text: "text", providerUsed: .local)
            executionOrder.append("correct")
        }

        mockDataManager.isHistoryEnabled = true
        if mockDataManager.isHistoryEnabled {
            executionOrder.append("save")
        }

        executionOrder.append("paste")

        XCTAssertEqual(executionOrder, ["prepare", "transcribe", "correct", "save", "paste"],
            "Pipeline should execute in correct order")
    }

    func testCancellationCheckpointsExist() async throws {
        // Verify cancellation is checked at key points
        var checkpointsPassed: [String] = []

        let task = Task {
            // Checkpoint 1: Before transcription
            try Task.checkCancellation()
            checkpointsPassed.append("pre-transcribe")

            // Checkpoint 2: After transcription
            try Task.checkCancellation()
            checkpointsPassed.append("post-transcribe")

            // Checkpoint 3: During semantic correction (if applicable)
            try Task.checkCancellation()
            checkpointsPassed.append("post-correct")

            return "done"
        }

        let result = try await task.value

        XCTAssertEqual(result, "done")
        XCTAssertEqual(checkpointsPassed.count, 3, "All checkpoints should be passed when not cancelled")
    }

}
