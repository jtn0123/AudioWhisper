import XCTest
@testable import AudioWhisper

final class WaveformStyleTests: IsolatedXCTestCase {
    // Deferred(D1): WaveformStyle is persisted via UserDefaults.standard. Once
    // the persistence helper accepts an injected UserDefaults, route writes
    // through a UUID-scoped suite and re-enable isolation.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private let testDefaultsKey = "waveformStyle"

    override func setUp() {
        super.setUp()
        // Ensure clean state before each test
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
    }

    override func tearDown() {
        // Clean up UserDefaults after each test
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
        super.tearDown()
    }

    // MARK: - Enum Tests

    func testAllCasesExist() {
        let allCases = WaveformStyle.allCases
        XCTAssertEqual(allCases.count, 8)
        XCTAssertTrue(allCases.contains(.classic))
        XCTAssertTrue(allCases.contains(.neon))
        XCTAssertTrue(allCases.contains(.spectrum))
        XCTAssertTrue(allCases.contains(.stream))
        XCTAssertTrue(allCases.contains(.constellation))
        XCTAssertTrue(allCases.contains(.halo))
        XCTAssertTrue(allCases.contains(.dial))
        XCTAssertTrue(allCases.contains(.heartbeat))
    }

    func testRawValues() {
        XCTAssertEqual(WaveformStyle.classic.rawValue, "Classic")
        XCTAssertEqual(WaveformStyle.neon.rawValue, "Neon")
        XCTAssertEqual(WaveformStyle.spectrum.rawValue, "Spectrum")
        XCTAssertEqual(WaveformStyle.stream.rawValue, "Stream")
        XCTAssertEqual(WaveformStyle.constellation.rawValue, "Constellation")
        XCTAssertEqual(WaveformStyle.halo.rawValue, "Halo")
        XCTAssertEqual(WaveformStyle.dial.rawValue, "Dial")
        XCTAssertEqual(WaveformStyle.heartbeat.rawValue, "Heartbeat")
    }

    func testIdentifiable() {
        XCTAssertEqual(WaveformStyle.classic.id, "Classic")
        XCTAssertEqual(WaveformStyle.neon.id, "Neon")
        XCTAssertEqual(WaveformStyle.spectrum.id, "Spectrum")
        XCTAssertEqual(WaveformStyle.stream.id, "Stream")
        XCTAssertEqual(WaveformStyle.constellation.id, "Constellation")
        XCTAssertEqual(WaveformStyle.halo.id, "Halo")
        XCTAssertEqual(WaveformStyle.dial.id, "Dial")
        XCTAssertEqual(WaveformStyle.heartbeat.id, "Heartbeat")
    }

    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for style in WaveformStyle.allCases {
            let data = try encoder.encode(style)
            let decoded = try decoder.decode(WaveformStyle.self, from: data)
            XCTAssertEqual(decoded, style)
        }
    }

    // MARK: - Description Tests

    func testDescriptions() {
        XCTAssertFalse(WaveformStyle.classic.description.isEmpty)
        XCTAssertFalse(WaveformStyle.neon.description.isEmpty)
        XCTAssertFalse(WaveformStyle.spectrum.description.isEmpty)

        // Each style should have a unique description
        let descriptions = WaveformStyle.allCases.map { $0.description }
        let uniqueDescriptions = Set(descriptions)
        XCTAssertEqual(descriptions.count, uniqueDescriptions.count, "Each style should have a unique description")
    }

    // MARK: - RequiresEnhancedAudio Tests

    func testClassicDoesNotRequireEnhancedAudio() {
        XCTAssertFalse(WaveformStyle.classic.requiresEnhancedAudio)
    }

    func testHeartbeatDoesNotRequireEnhancedAudio() {
        // Heartbeat only needs audioLevel, not FFT data
        XCTAssertFalse(WaveformStyle.heartbeat.requiresEnhancedAudio)
    }

    func testNeonRequiresEnhancedAudio() {
        XCTAssertTrue(WaveformStyle.neon.requiresEnhancedAudio)
    }

    func testSpectrumRequiresEnhancedAudio() {
        XCTAssertTrue(WaveformStyle.spectrum.requiresEnhancedAudio)
    }

    func testStreamRequiresEnhancedAudio() {
        XCTAssertTrue(WaveformStyle.stream.requiresEnhancedAudio)
    }

    func testConstellationRequiresEnhancedAudio() {
        XCTAssertTrue(WaveformStyle.constellation.requiresEnhancedAudio)
    }

    func testHaloRequiresEnhancedAudio() {
        XCTAssertTrue(WaveformStyle.halo.requiresEnhancedAudio)
    }

    func testDialRequiresEnhancedAudio() {
        XCTAssertTrue(WaveformStyle.dial.requiresEnhancedAudio)
    }

    // MARK: - isRadial Tests

    func testIsRadial() {
        XCTAssertTrue(WaveformStyle.halo.isRadial)
        XCTAssertTrue(WaveformStyle.dial.isRadial)
        XCTAssertTrue(WaveformStyle.heartbeat.isRadial)

        XCTAssertFalse(WaveformStyle.classic.isRadial)
        XCTAssertFalse(WaveformStyle.neon.isRadial)
        XCTAssertFalse(WaveformStyle.spectrum.isRadial)
        XCTAssertFalse(WaveformStyle.stream.isRadial)
        XCTAssertFalse(WaveformStyle.constellation.isRadial)
    }

    // MARK: - isNew Tests

    func testIsNew() {
        XCTAssertTrue(WaveformStyle.stream.isNew)
        XCTAssertTrue(WaveformStyle.constellation.isNew)
        XCTAssertTrue(WaveformStyle.halo.isNew)
        XCTAssertTrue(WaveformStyle.dial.isNew)
        XCTAssertTrue(WaveformStyle.heartbeat.isNew)

        XCTAssertFalse(WaveformStyle.classic.isNew)
        XCTAssertFalse(WaveformStyle.neon.isNew)
        XCTAssertFalse(WaveformStyle.spectrum.isNew)
    }

    // MARK: - UserDefaults Extension Tests

    func testDefaultStyleIsClassic() {
        // setUp already clears the value, so no need to remove it again
        let style = UserDefaults.standard.waveformStyle
        XCTAssertEqual(style, .classic, "Default style should be Classic")
    }

    func testSetAndGetStyle() {
        for style in WaveformStyle.allCases {
            UserDefaults.standard.waveformStyle = style
            XCTAssertEqual(UserDefaults.standard.waveformStyle, style)
        }
    }

    func testStyleReadbackConsistency() {
        // Verify that reading the same value multiple times returns consistent results
        // This tests that the getter doesn't have side effects
        let initialStyle = UserDefaults.standard.waveformStyle
        let secondRead = UserDefaults.standard.waveformStyle
        let thirdRead = UserDefaults.standard.waveformStyle

        XCTAssertEqual(initialStyle, secondRead, "Consecutive reads should return same value")
        XCTAssertEqual(secondRead, thirdRead, "Consecutive reads should return same value")
    }

    func testInvalidRawValueDefaultsToClassic() {
        // Manually set an invalid value
        UserDefaults.standard.set("InvalidStyle", forKey: testDefaultsKey)

        let style = UserDefaults.standard.waveformStyle
        XCTAssertEqual(style, .classic, "Invalid raw value should default to Classic")
    }

    func testNilValueDefaultsToClassic() {
        // setUp already clears the value, so we can just read
        let style = UserDefaults.standard.waveformStyle
        XCTAssertEqual(style, .classic, "Nil value should default to Classic")
    }

    // MARK: - Initialization from RawValue Tests

    func testInitFromValidRawValue() {
        XCTAssertEqual(WaveformStyle(rawValue: "Classic"), .classic)
        XCTAssertEqual(WaveformStyle(rawValue: "Neon"), .neon)
        XCTAssertEqual(WaveformStyle(rawValue: "Spectrum"), .spectrum)
        XCTAssertEqual(WaveformStyle(rawValue: "Stream"), .stream)
        XCTAssertEqual(WaveformStyle(rawValue: "Constellation"), .constellation)
        XCTAssertEqual(WaveformStyle(rawValue: "Halo"), .halo)
        XCTAssertEqual(WaveformStyle(rawValue: "Dial"), .dial)
        XCTAssertEqual(WaveformStyle(rawValue: "Heartbeat"), .heartbeat)
    }

    func testInitFromInvalidRawValue() {
        XCTAssertNil(WaveformStyle(rawValue: "Invalid"))
        XCTAssertNil(WaveformStyle(rawValue: ""))
        XCTAssertNil(WaveformStyle(rawValue: "classic")) // Case sensitive
        XCTAssertNil(WaveformStyle(rawValue: "CLASSIC"))
        // Removed legacy styles should no longer resolve.
        XCTAssertNil(WaveformStyle(rawValue: "Circular"))
        XCTAssertNil(WaveformStyle(rawValue: "Pulse Rings"))
        XCTAssertNil(WaveformStyle(rawValue: "Particles"))
    }

    // MARK: - Equality Tests

    func testEquality() {
        XCTAssertEqual(WaveformStyle.classic, WaveformStyle.classic)
        XCTAssertEqual(WaveformStyle.neon, WaveformStyle.neon)
        XCTAssertEqual(WaveformStyle.spectrum, WaveformStyle.spectrum)

        XCTAssertNotEqual(WaveformStyle.classic, WaveformStyle.neon)
        XCTAssertNotEqual(WaveformStyle.neon, WaveformStyle.spectrum)
        XCTAssertNotEqual(WaveformStyle.classic, WaveformStyle.spectrum)
    }

    // MARK: - Hashable Tests

    func testHashable() {
        var set = Set<WaveformStyle>()
        for style in WaveformStyle.allCases {
            set.insert(style)
        }

        XCTAssertEqual(set.count, 8)
        for style in WaveformStyle.allCases {
            XCTAssertTrue(set.contains(style))
        }
    }

    func testHashableNoDuplicates() {
        var set = Set<WaveformStyle>()
        set.insert(.classic)
        set.insert(.classic) // Duplicate

        XCTAssertEqual(set.count, 1)
    }
}
