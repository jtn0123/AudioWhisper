import CAWCore

/// The user's words: spellings to enforce and phrases to rewrite.
///
/// Edited as plain text, one entry per line:
///
///     Kubernetes
///     AudioWhisper
///     post gress -> Postgres
///
/// A bare line is a *term*: any case-insensitive whole-word match is rewritten
/// to that exact spelling, and a CamelCase term also matches its spoken split
/// ("audio whisper" → "AudioWhisper"). Terms also bias WhisperKit through its
/// decoder prompt. A `heard -> written` (or `=>`) line is a *replacement*.
/// Blank lines and lines starting with `#` are ignored.
///
/// The rules run in Rust (`transcript::vocabulary`, through `TranscriptCore`);
/// this type is the plain value the app stores and compares.
struct CustomVocabulary: Equatable, Sendable {
    struct Replacement: Equatable, Sendable {
        let heard: String
        let written: String
    }

    /// Whisper's prompt window is 224 tokens and is shared with the decoder
    /// context, so the prompt stays well under it. Rust's
    /// `MAX_PROMPT_CHARACTERS` is what applies; this states it for callers.
    static let maxPromptCharacters = 400

    private(set) var terms: [String] = []
    private(set) var replacements: [Replacement] = []

    static let empty = Self()

    var isEmpty: Bool { terms.isEmpty && replacements.isEmpty }

    init(terms: [String] = [], replacements: [Replacement] = []) {
        self.terms = terms
        self.replacements = replacements
    }

    init(parsing text: String) {
        let handle = TranscriptCore.withBytes(text) { aw_vocabulary_parse($0, $1) }
        defer { aw_vocabulary_free(handle) }
        self = TranscriptCore.vocabulary(of: handle)
    }

    /// Spellings WhisperKit should lean toward, as a natural comma list. Only
    /// the leading entries that fit `maxPromptCharacters` are used.
    var promptText: String? {
        TranscriptCore.withVocabulary(self) { TranscriptCore.take(aw_vocabulary_prompt_text($0)) }
    }

    /// Replacements first, so a rewrite can produce a term's spelling; terms
    /// then normalise case and spoken CamelCase splits.
    func apply(to text: String) -> String {
        TranscriptCore.withVocabulary(self) { handle in
            TranscriptCore.transform(text) { aw_vocabulary_apply(handle, $0, $1) }
        }
    }

    /// "AudioWhisper" → ["Audio", "Whisper"]; "PostgreSQL" → ["Postgre", "SQL"].
    /// A lowercase→uppercase step starts a new part; acronym runs stay whole.
    static func camelCaseParts(of term: String) -> [String] {
        TranscriptCore.strings(TranscriptCore.withBytes(term) { aw_camel_case_parts($0, $1) })
    }
}
