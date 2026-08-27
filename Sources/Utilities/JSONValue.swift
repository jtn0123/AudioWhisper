import Foundation

/// A fully-typed JSON value.
///
/// Exists for one job: carrying a JSON subtree whose shape is not known at the
/// point it is handled. The ML daemon's JSON-RPC envelope is the motivating
/// case — `handle(line:)` must read `id` and `error` to find the waiting caller
/// *before* anything knows what type `result` should decode to.
///
/// The alternative was `JSONSerialization.jsonObject(...) as? [String: Any]`
/// followed by `as?` casts on every field, which is how this code used to read.
/// That form has no compile-time story at all: a mistyped key or a changed
/// shape is a silent `nil` that turns into "Malformed JSON-RPC response" in the
/// log and a 60-second timeout for the user.
///
/// `int` and `double` are separate cases on purpose. Collapsing them onto
/// `Double` — the usual shortcut — makes the type lossy in a way that matters
/// here, because this value gets **re-encoded** and handed to a second decoder:
/// a request `id` of `7` would come back out as `7.0`, and any integer field
/// added to a result later would decode differently after a round trip than it
/// did on the wire.
internal enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            // Int before Double: `7` must survive a decode/encode round trip as
            // `7`, not `7.0`.
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value is not valid JSON"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Accessors

internal extension JSONValue {
    /// Member lookup on an object, `nil` for every other case.
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var isNull: Bool { self == .null }
}

// MARK: - Literals
//
// These keep call sites — test fixtures especially — reading like the JSON they
// stand for: `["success": true, "text": "done", "error": nil]` builds a
// `JSONValue` directly, with no `NSNull()` and no `Any`.

extension JSONValue: ExpressibleByNilLiteral {
    init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}

// Deliberately NOT ExpressibleByStringInterpolation. Conforming means either
// calling `String.init(stringInterpolation:)` directly — a compiler-protocol
// init, which SwiftLint rejects and which is the kind of call that rule exists
// to catch — or declaring a bespoke interpolation type whose
// `appendInterpolation` overloads quietly diverge from Swift's own. Write
// `.string("attempt \(n)")` for an interpolated value instead.

extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    /// `uniquingKeysWith` rather than `Dictionary(uniqueKeysWithValues:)`: a
    /// repeated key keeps the last value instead of trapping. A duplicate key
    /// in a literal is a mistake either way, but a crash is the worse of the
    /// two outcomes for something that only ever carries a subprocess reply.
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
