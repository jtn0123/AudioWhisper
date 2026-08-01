// swiftlint:disable:next unused_import - verified required: removing it breaks the build
import AVFoundation

// AVAudioEngine is @unchecked Sendable; a subclass must restate it. This mock
// is only ever touched from a single test at a time.
class MockAVAudioEngine: AVAudioEngine, @unchecked Sendable {
    private var mockIsRunning = false
    
    override var isRunning: Bool {
        return mockIsRunning
    }
    
    override func prepare() {
        // Mock preparation
    }
    
    override func start() throws {
        mockIsRunning = true
    }
    
    override func stop() {
        mockIsRunning = false
    }
    
    func setMockRunningState(_ isRunning: Bool) {
        mockIsRunning = isRunning
    }
}
