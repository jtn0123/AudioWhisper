import XCTest
import AVFoundation
@testable import AudioWhisper

final class AudioValidatorTests: XCTestCase {
    
    func testValidateAudioFileReturnsFileNotFound() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).wav")
        
        let result = await AudioValidator.validateAudioFile(at: missingURL)
        
        guard case .invalid(.fileNotFound) = result else {
            return XCTFail("Expected fileNotFound, got \(result)")
        }
    }
    
    func testValidateAudioFileRejectsEmptyFile() async throws {
        let url = try temporaryFile(extension: "wav", contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        
        let result = await AudioValidator.validateAudioFile(at: url)
        
        guard case .invalid(.emptyFile) = result else {
            return XCTFail("Expected emptyFile, got \(result)")
        }
    }
    
    func testValidateAudioFileRejectsUnsupportedFormat() async throws {
        let url = try temporaryFile(extension: "txt", contents: Data([0x00, 0x01]))
        defer { try? FileManager.default.removeItem(at: url) }
        
        let result = await AudioValidator.validateAudioFile(at: url)
        
        guard case .invalid(.unsupportedFormat("txt")) = result else {
            return XCTFail("Expected unsupportedFormat(txt), got \(result)")
        }
    }
    
    func testValidateAudioFileReturnsValidForWellFormedAudio() async throws {
        let url = try makeValidAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        
        let result = await AudioValidator.validateAudioFile(at: url)
        
        guard case .valid(let info) = result else {
            return XCTFail("Expected valid result, got \(result)")
        }
        
        XCTAssertTrue(result.isValid)
        XCTAssertGreaterThan(info.sampleRate, 0)
        XCTAssertGreaterThan(info.channelCount, 0)
        XCTAssertGreaterThan(info.duration, 0)
        XCTAssertGreaterThan(info.fileSize, 0)
    }
    
    func testValidateAudioFileDetectsCorruptedAudio() async throws {
        let url = try makeCorruptedAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        
        let result = await AudioValidator.validateAudioFile(at: url)
        
        guard case .invalid(.corruptedFile) = result else {
            return XCTFail("Expected corruptedFile, got \(result)")
        }
    }
    
    func testIsFormatSupportedMatchesKnownExtensions() {
        let supported = URL(fileURLWithPath: "/tmp/audio.mp3")
        let unsupported = URL(fileURLWithPath: "/tmp/audio.doc")
        
        XCTAssertTrue(AudioValidator.isFormatSupported(url: supported))
        XCTAssertFalse(AudioValidator.isFormatSupported(url: unsupported))
    }
    
    func testIsFileSizeValidEnforcesLimit() throws {
        let smallFile = try temporaryFile(extension: "wav", contents: Data(repeating: 0xAA, count: 1_024))
        let largeFile = try temporaryFile(extension: "wav", contents: Data(repeating: 0xBB, count: 2_000_000))
        defer {
            try? FileManager.default.removeItem(at: smallFile)
            try? FileManager.default.removeItem(at: largeFile)
        }
        
        XCTAssertTrue(AudioValidator.isFileSizeValid(url: smallFile, maxSizeInMB: 1))
        XCTAssertFalse(AudioValidator.isFileSizeValid(url: largeFile, maxSizeInMB: 1))
    }
    
    // MARK: - Helpers
    
    private func temporaryFile(extension fileExtension: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioValidatorTests-\(UUID().uuidString).\(fileExtension)")
        FileManager.default.createFile(atPath: url.path, contents: contents, attributes: nil)
        return url
    }
    
    private func makeValidAudioFile() throws -> URL {
        // Use bundled test audio file to avoid AVAudioFile framework warnings
        guard let bundledURL = Bundle.module.url(forResource: "test_audio", withExtension: "wav", subdirectory: "Resources") else {
            throw NSError(domain: "AudioValidatorTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Bundled test audio file not found"])
        }

        // Copy to temp location so tests can safely delete it
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioValidatorTests-valid-\(UUID().uuidString).wav")
        try FileManager.default.copyItem(at: bundledURL, to: tempURL)
        return tempURL
    }
    
    private func makeCorruptedAudioFile() throws -> URL {
        let payload = Data("not a real wav file".utf8)
        return try temporaryFile(extension: "wav", contents: payload)
    }
}
