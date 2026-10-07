import XCTest
@testable import AudioWhisper

@MainActor
final class RecordingBusyGuardTests: XCTestCase {
    func testBusyViewModelDoesNotStartAnotherRecording() {
        let recorder = MockAudioEngineRecorder()
        let permission = PermissionManager()
        permission.microphonePermissionState = .granted
        let viewModel = RecordingViewModel()
        viewModel.isProcessingForFlow = true
        viewModel.startRecording(
            audioRecorder: recorder, permissionManager: permission,
            setupRequirement: .ready, presentSetup: { XCTFail("Busy actions must be ignored") }
        )
        XCTAssertEqual(recorder.startRecordingCallCount, 0)
        viewModel.isProcessingForFlow = false
    }

}
