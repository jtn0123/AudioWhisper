import CAWCore

/// Fits a transcript to the text it is inserted after: a space so words do not
/// run together, and the first word's case matched to whether the insertion
/// starts or continues a sentence.
///
/// Both engines capitalise the first word of every transcript, which is wrong
/// mid-sentence. Lowercasing is limited to common function words, so a name
/// ("Paris", "Justin") or anything outside English keeps its capital.
///
/// The rules run in Rust (`transcript::cursor`, through `TranscriptCore`).
enum CursorContextFormatter {
    static func fit(_ text: String, after preceding: String?) -> String {
        TranscriptCore.withBytes(text) { textBytes, textLength in
            TranscriptCore.withBytes(preceding ?? "") { precedingBytes, precedingLength in
                TranscriptCore.text(
                    aw_fit(textBytes, textLength, preceding != nil, precedingBytes, precedingLength))
            }
        }
    }
}
