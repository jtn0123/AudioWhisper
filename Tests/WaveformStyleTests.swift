import XCTest
@testable import AudioWhisper

final class WaveformStyleTests: XCTestCase {
    private let testDefaultsKey = "waveformStyle"

    override func tearDown() {
        // Clean up UserDefaults after each test
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)
        super.tearDown()
    }

    // MARK: - Enum Tests

    func testAllCasesExist() {
        let allCases = WaveformStyle.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.classic))
        XCTAssertTrue(allCases.contains(.neon))
        XCTAssertTrue(allCases.contains(.spectrum))
    }

    func testRawValues() {
        XCTAssertEqual(WaveformStyle.classic.rawValue, "Classic")
        XCTAssertEqual(WaveformStyle.neon.rawValue, "Neon")
        XCTAssertEqual(WaveformStyle.spectrum.rawValue, "Spectrum")
    }

    func testIdentifiable() {
        XCTAssertEqual(WaveformStyle.classic.id, "Classic")
        XCTAssertEqual(WaveformStyle.neon.id, "Neon")
        XCTAssertEqual(WaveformStyle.spectrum.id, "Spectrum")
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

    func testNeonRequiresEnhancedAudio() {
        XCTAssertTrue(WaveformStyle.neon.requiresEnhancedAudio)
    }

    func testSpectrumRequiresEnhancedAudio() {
        XCTAssertTrue(WaveformStyle.spectrum.requiresEnhancedAudio)
    }

    // MARK: - UserDefaults Extension Tests

    func testDefaultStyleIsClassic() {
        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)

        let style = UserDefaults.standard.waveformStyle
        XCTAssertEqual(style, .classic, "Default style should be Classic")
    }

    func testSetAndGetStyle() {
        for style in WaveformStyle.allCases {
            UserDefaults.standard.waveformStyle = style
            XCTAssertEqual(UserDefaults.standard.waveformStyle, style)
        }
    }

    func testStylePersistsAcrossAccess() {
        UserDefaults.standard.waveformStyle = .neon

        // Access multiple times
        let style1 = UserDefaults.standard.waveformStyle
        let style2 = UserDefaults.standard.waveformStyle

        XCTAssertEqual(style1, .neon)
        XCTAssertEqual(style2, .neon)
    }

    func testInvalidRawValueDefaultsToClassic() {
        // Manually set an invalid value
        UserDefaults.standard.set("InvalidStyle", forKey: testDefaultsKey)

        let style = UserDefaults.standard.waveformStyle
        XCTAssertEqual(style, .classic, "Invalid raw value should default to Classic")
    }

    func testNilValueDefaultsToClassic() {
        UserDefaults.standard.removeObject(forKey: testDefaultsKey)

        let style = UserDefaults.standard.waveformStyle
        XCTAssertEqual(style, .classic, "Nil value should default to Classic")
    }

    // MARK: - Initialization from RawValue Tests

    func testInitFromValidRawValue() {
        XCTAssertEqual(WaveformStyle(rawValue: "Classic"), .classic)
        XCTAssertEqual(WaveformStyle(rawValue: "Neon"), .neon)
        XCTAssertEqual(WaveformStyle(rawValue: "Spectrum"), .spectrum)
    }

    func testInitFromInvalidRawValue() {
        XCTAssertNil(WaveformStyle(rawValue: "Invalid"))
        XCTAssertNil(WaveformStyle(rawValue: ""))
        XCTAssertNil(WaveformStyle(rawValue: "classic")) // Case sensitive
        XCTAssertNil(WaveformStyle(rawValue: "CLASSIC"))
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
        set.insert(.classic)
        set.insert(.neon)
        set.insert(.spectrum)

        XCTAssertEqual(set.count, 3)
        XCTAssertTrue(set.contains(.classic))
        XCTAssertTrue(set.contains(.neon))
        XCTAssertTrue(set.contains(.spectrum))
    }

    func testHashableNoDuplicates() {
        var set = Set<WaveformStyle>()
        set.insert(.classic)
        set.insert(.classic) // Duplicate

        XCTAssertEqual(set.count, 1)
    }
}
