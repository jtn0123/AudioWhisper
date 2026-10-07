import Foundation
// swiftlint:disable:next unused_import - verified required: removing it breaks the build
import AVFoundation

class MockAVAudioRecorder: AVAudioRecorder, @unchecked Sendable {
    private var mockIsRecording = false
    
    override convenience init() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mock_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
        ]
        do {
            try self.init(url: tempURL, settings: settings)
        } catch {
            fatalError("MockAVAudioRecorder failed to initialize: \(error)")
        }
    }
    private var mockCurrentTime: TimeInterval = 0
    private var mockAveragePower: Float = -10.0
    private var mockPeakPower: Float = -5.0
    private var shouldFailToRecord = false
    private var shouldFailToStop = false
    
    override var isRecording: Bool {
        return mockIsRecording
    }
    
    override var currentTime: TimeInterval {
        return mockCurrentTime
    }
    
    override func record() -> Bool {
        if shouldFailToRecord {
            return false
        }
        mockIsRecording = true
        mockCurrentTime = 0
        return true
    }
    
    override func stop() {
        mockIsRecording = false
        if !shouldFailToStop {
            delegate?.audioRecorderDidFinishRecording?(self, successfully: true)
        }
    }
    
    override func updateMeters() {
        // Simulate meter updates
    }
    
    override func averagePower(forChannel channelNumber: Int) -> Float {
        return mockAveragePower
    }
    
    override func peakPower(forChannel channelNumber: Int) -> Float {
        return mockPeakPower
    }
}
