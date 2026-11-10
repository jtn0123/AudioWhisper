import CAWCore

/// The bridge to the transcript rules in Rust (`Vendor/AudioWhisper-Core`,
/// linked as `libawcore.a`; see `scripts/build-core.sh`).
///
/// Text crosses as UTF-8 with a length. Every string and handle Rust returns is
/// freed here, before the call that received it returns, so nothing from Rust
/// outlives a call and the Swift types stay plain values.
enum TranscriptCore {
    /// Calls `body` with `text`'s UTF-8 bytes.
    static func withBytes<R>(_ text: String, _ body: (UnsafePointer<UInt8>?, Int) -> R) -> R {
        var text = text
        return text.withUTF8 { body($0.baseAddress, $0.count) }
    }

    /// The string Rust returned, freed; `nil` for Rust's "no string".
    static func take(_ string: AwString) -> String? {
        guard let pointer = string.ptr else { return nil }
        defer { aw_string_free(string) }
        // Rust strings are always valid UTF-8, so the bytes are copied as they are.
        return String(unsafeUninitializedCapacity: string.len) { buffer in
            buffer.initialize(from: UnsafeBufferPointer(start: pointer, count: string.len)).index
        }
    }

    /// A string Rust always returns, such as a rewritten transcript.
    static func text(_ string: AwString) -> String {
        take(string) ?? ""
    }

    /// `text` through a Rust function that takes and returns one string.
    static func transform(
        _ text: String, _ function: (UnsafePointer<UInt8>?, Int) -> AwString
    ) -> String {
        Self.text(withBytes(text, function))
    }

    /// Calls `body` with a Rust copy of `vocabulary`, freed afterwards.
    static func withVocabulary<R>(_ vocabulary: CustomVocabulary, _ body: (OpaquePointer?) -> R) -> R {
        let handle = aw_vocabulary_new()
        defer { aw_vocabulary_free(handle) }
        for term in vocabulary.terms {
            withBytes(term) { aw_vocabulary_add_term(handle, $0, $1) }
        }
        for replacement in vocabulary.replacements {
            withBytes(replacement.heard) { heard, heardLength in
                withBytes(replacement.written) { written, writtenLength in
                    aw_vocabulary_add_replacement(handle, heard, heardLength, written, writtenLength)
                }
            }
        }
        return body(handle)
    }

    /// The vocabulary a Rust handle holds.
    static func vocabulary(of handle: OpaquePointer?) -> CustomVocabulary {
        let terms = (0..<aw_vocabulary_term_count(handle)).map { text(aw_vocabulary_term(handle, $0)) }
        let replacements = (0..<aw_vocabulary_replacement_count(handle)).map {
            CustomVocabulary.Replacement(
                heard: text(aw_vocabulary_replacement(handle, $0, false)),
                written: text(aw_vocabulary_replacement(handle, $0, true)))
        }
        return CustomVocabulary(terms: terms, replacements: replacements)
    }

    /// A list of strings Rust returned, freed.
    static func strings(_ list: OpaquePointer?) -> [String] {
        defer { aw_strings_free(list) }
        return (0..<aw_strings_count(list)).map { text(aw_strings_get(list, $0)) }
    }
}
