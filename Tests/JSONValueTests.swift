import XCTest
@testable import AudioWhisper

/// Tests for the typed JSON carrier that replaced `as? [String: Any]` casts.
///
/// The behaviour worth pinning is the round trip. `JSONValue` is not decoded
/// and then read — it is decoded, held while the caller works out *which* type
/// the payload should become, and then **re-encoded** so a second decoder can
/// take it. Anything the round trip loses is lost silently, in a subprocess
/// reply, at runtime.
final class JSONValueTests: XCTestCase {

    private func roundTrip(_ json: String) throws -> String {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(String(bytes: try JSONEncoder().encode(value), encoding: .utf8))
    }

    // MARK: - Round trip

    /// The motivating case for separating `.int` from `.double`. Collapsing
    /// both onto `Double` — the usual shortcut — turns a request id of `7` into
    /// `7.0` on the way back out, and `MLDaemonManager` keys `pending` by `Int`.
    func testIntegersDoNotBecomeFloatsOnRoundTrip() throws {
        XCTAssertEqual(try roundTrip("7"), "7")
        XCTAssertEqual(try roundTrip("0"), "0")
        XCTAssertEqual(try roundTrip("-42"), "-42")
    }

    func testDoublesSurviveRoundTrip() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data("1.5".utf8))
        XCTAssertEqual(value, .double(1.5))
    }

    func testBoolsAreNotDecodedAsNumbers() throws {
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data("true".utf8)), .bool(true))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data("false".utf8)), .bool(false))
    }

    func testNullRoundTrips() throws {
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data("null".utf8)), .null)
        XCTAssertEqual(try roundTrip("null"), "null")
    }

    func testNestedStructureRoundTrips() throws {
        let json = #"{"a":{"b":[1,2.5,"three",true,null]}}"#

        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))

        XCTAssertEqual(value["a"]?["b"], .array([.int(1), .double(2.5), .string("three"), .bool(true), .null]))
    }

    func testEmptyObjectAndArrayRoundTrip() throws {
        XCTAssertEqual(try roundTrip("{}"), "{}")
        XCTAssertEqual(try roundTrip("[]"), "[]")
    }

    // MARK: - Accessors

    func testSubscriptReturnsNilForNonObjects() throws {
        let array = try JSONDecoder().decode(JSONValue.self, from: Data("[1,2]".utf8))

        XCTAssertNil(array["anything"], "subscripting a non-object must be nil, not a crash")
        XCTAssertNil(JSONValue.string("x")["key"])
        XCTAssertNil(JSONValue.null["key"])
    }

    func testMissingKeyIsNil() {
        let object: JSONValue = ["present": "yes"]

        XCTAssertEqual(object["present"]?.stringValue, "yes")
        XCTAssertNil(object["absent"])
    }

    /// Typed accessors return nil on a mismatch rather than coercing — this is
    /// what preserves the semantics of the `as? String` casts they replaced.
    func testTypedAccessorsDoNotCoerce() {
        XCTAssertNil(JSONValue.int(1).stringValue)
        XCTAssertNil(JSONValue.string("1").intValue)
        XCTAssertNil(JSONValue.string("true").boolValue)
        XCTAssertNil(JSONValue.bool(true).stringValue)
        XCTAssertEqual(JSONValue.string("x").stringValue, "x")
        XCTAssertEqual(JSONValue.int(3).intValue, 3)
        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
    }

    func testIsNullOnlyForNull() {
        XCTAssertTrue(JSONValue.null.isNull)
        XCTAssertFalse(JSONValue.bool(false).isNull)
        XCTAssertFalse(JSONValue.string("").isNull)
        XCTAssertFalse(JSONValue.object([:]).isNull)
    }

    // MARK: - Literals

    func testLiteralsBuildTheExpectedCases() {
        let value: JSONValue = [
            "text": "hello",
            "count": 3,
            "ratio": 0.5,
            "ok": true,
            "missing": nil,
            "list": [1, "two"]
        ]

        XCTAssertEqual(value["text"], .string("hello"))
        XCTAssertEqual(value["count"], .int(3))
        XCTAssertEqual(value["ratio"], .double(0.5))
        XCTAssertEqual(value["ok"], .bool(true))
        XCTAssertEqual(value["missing"], .null)
        XCTAssertEqual(value["list"], .array([.int(1), .string("two")]))
    }

    // MARK: - Rejection

    func testInvalidJSONFailsToDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(JSONValue.self, from: Data("{oops}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(JSONValue.self, from: Data("".utf8)))
    }
}
