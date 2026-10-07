/// One grammar-cleanup policy, independent of the destination application.
internal enum CorrectionPrompt {
    static let template = """
        Clean up this speech transcription for general use.
        - Fix clear typos, grammar, capitalization and punctuation
        - Remove filler words only when they add no meaning
        - Preserve the original tone, instructions, names, numbers and technical terms
        - Keep phrasing close to the original; do not turn dictation into an email or command
        - Do not add or invent content
        Output only the corrected text.
        """
}
