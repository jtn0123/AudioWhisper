import XCTest
@testable import AudioWhisper

@MainActor
final class SoundManagerTests: IsolatedXCTestCase {
    // Deferred(D1): SoundManager reads `playCompletionSound` from
    // UserDefaults.standard directly. Once it accepts an injected
    // UserDefaults, route writes through a UUID-scoped suite and re-enable.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private var soundProvider: MockSoundProvider!
    private var soundManager: SoundManager!
    
    override func setUp() {
        super.setUp()
        soundProvider = MockSoundProvider()
        soundManager = SoundManager(soundProvider: soundProvider)
        AppDefaults.defaults.removeObject(forKey: "playCompletionSound")
    }
    
    override func tearDown() {
        AppDefaults.defaults.removeObject(forKey: "playCompletionSound")
        soundManager = nil
        soundProvider = nil
        super.tearDown()
    }
    
    func testPlayCompletionSound_DefaultPreferencePlaysGlass() {
        soundManager.playCompletionSound()
        
        XCTAssertEqual(soundProvider.requestedNames, ["Glass"])
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 1)
    }
    
    func testPlayCompletionSound_WhenDisabledDoesNotPlay() {
        AppDefaults.defaults.set(false, forKey: "playCompletionSound")
        
        soundManager.playCompletionSound()
        
        XCTAssertTrue(soundProvider.requestedNames.isEmpty)
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 0)
    }
    
    func testPlayCompletionSound_WhenEnabledPlaysOnce() {
        AppDefaults.defaults.set(true, forKey: "playCompletionSound")
        
        soundManager.playCompletionSound()
        
        XCTAssertEqual(soundProvider.requestedNames, ["Glass"])
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 1)
    }
    
    func testPlayRecordingStartSound_UsesPingSound() {
        soundManager.playRecordingStartSound()
        
        XCTAssertEqual(soundProvider.requestedNames, ["Ping"])
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 1)
    }
    
    func testPlayRecordingStartSound_WhenDisabledDoesNotPlay() {
        AppDefaults.defaults.set(false, forKey: "playCompletionSound")
        
        soundManager.playRecordingStartSound()
        
        XCTAssertTrue(soundProvider.requestedNames.isEmpty)
        XCTAssertEqual(soundProvider.defaultSound.playCallCount, 0)
    }
}
