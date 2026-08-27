import Foundation

/// The JSON-RPC contract between `MLDaemonManager` and `Sources/ml/rpc.py`.
///
/// This protocol used to exist only as string literals typed out twice — once
/// in Swift building `[String: Any]` payloads by hand, once in Python reading
/// `Dict[str, Any]` with `.get()`. `"pcm_path"`, `"repo"`, `"warmup"` and the
/// rest appeared in both languages with nothing relating them, so renaming a
/// key on either side compiled clean and type-checked clean on both, then
/// failed at runtime in a subprocess.
///
/// Collecting the wire form here does not by itself prove the two sides agree —
/// no type system spans a process boundary. That is what
/// `MLRPCContractTests` is for: it runs the real `ml_daemon.py` and asserts
/// against these types. What this file does is give that test, and the app, a
/// single definition to be wrong about.
internal enum MLRPCWire {
    /// Version string sent in every request. rpc.py echoes it back unread; it
    /// is here because the payload claims to be JSON-RPC 2.0.
    static let version = "2.0"
}

/// The methods `ml/rpc.py` implements.
///
/// Exhaustive on purpose: `rpc.py` raises `ValueError(f"Unknown method: ...")`
/// for anything else, so a method that is not in this enum is a runtime error
/// by construction. Keeping it a `CaseIterable` enum lets the contract test
/// walk every case against the live daemon.
internal enum MLRPCMethod: String, Codable, CaseIterable, Sendable {
    case ping
    case transcribe
    case correct
    case warmup
}

/// What `warmup` can pre-load.
///
/// This was a bare `String` parameter with `"parakeet"` and `"mlx"` written as
/// literals at the two call sites, while the daemon raised
/// `ValueError(f"Unknown warmup type: ...")` for anything it did not recognise.
/// Nothing on the Swift side prevented a typo from reaching that raise.
///
/// `rpc.py` also accepts `"correction"` as a synonym for `"mlx"`; the app has
/// never sent it, so it is not represented here. That tolerance stays a
/// property of the daemon, not of this contract.
internal enum MLWarmupKind: String, Codable, CaseIterable, Sendable {
    case parakeet
    case mlx
}

/// Request parameter payloads, one per method.
internal enum MLRPCParams {
    struct Transcribe: Codable, Equatable, Sendable {
        let repo: String
        let pcmPath: String

        enum CodingKeys: String, CodingKey {
            case repo
            // The one wire key that is not simply the property name. Spelling
            // it here rather than at the call site is the entire point.
            case pcmPath = "pcm_path"
        }
    }

    struct Correct: Codable, Equatable, Sendable {
        let repo: String
        let text: String
        /// Omitted from the payload entirely when nil — synthesized `Encodable`
        /// uses `encodeIfPresent` for optionals, matching the hand-built
        /// dictionary this replaced, which only inserted the key when non-nil.
        /// Either form is fine for the daemon: `params.get("prompt")` yields
        /// `None` for an absent key and for an explicit null alike.
        let prompt: String?
    }

    struct Warmup: Codable, Equatable, Sendable {
        let type: MLWarmupKind
        let repo: String
    }

    /// `ping` takes no parameters. rpc.py reads `request.get("params") or {}`,
    /// so the key is simply omitted.
    struct Empty: Codable, Equatable, Sendable {}
}

/// Result payloads, one per method.
internal enum MLRPCResult {
    struct Transcribe: Codable, Equatable, Sendable {
        let success: Bool
        let text: String
        let error: String?
    }

    struct Correct: Codable, Equatable, Sendable {
        let success: Bool
        let text: String
        let error: String?
    }

    /// `warmup` answers `{"success": true}`. Optional because a failure comes
    /// back through the JSON-RPC `error` member instead, leaving no result at
    /// all to decode.
    struct Warmup: Codable, Equatable, Sendable {
        let success: Bool?
    }

    struct Ping: Codable, Equatable, Sendable {
        let pong: Bool
    }
}

/// One line of the daemon's stdout, before the result is routed to the decoder
/// that knows its type.
///
/// Replaces `JSONSerialization.jsonObject(...) as? [String: Any]` plus four
/// `as?` casts. The shape is now stated once and enforced by the decoder.
internal struct MLRPCEnvelope: Decodable, Equatable, Sendable {
    /// Nil for the parse-failure reply rpc.py sends when a request line is not
    /// valid JSON — it has no id to echo back, so it sends `"id": null`.
    let id: Int?
    /// The method's own payload, still opaque here: `handle(line:)` has to find
    /// the waiting caller by `id` before it knows what type to decode into.
    let result: JSONValue?
    let error: ErrorBody?

    struct ErrorBody: Decodable, Equatable, Sendable {
        let message: String?
    }
}

/// A request as it goes onto the wire.
internal struct MLRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc: String = MLRPCWire.version
    let id: Int
    let method: MLRPCMethod
    /// Encoded only when non-nil, so `ping` sends no `params` member.
    let params: Params?
}
