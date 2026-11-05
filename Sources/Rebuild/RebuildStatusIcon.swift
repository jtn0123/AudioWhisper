/// What the menu bar item shows. A microphone app must make capture visible
/// even when the recorder HUD is hidden (Express Mode), so the icon follows
/// the dictation phase and any meeting capture.
struct RebuildStatusIcon: Equatable {
    let symbol: String
    let label: String
    /// Whether the icon should draw in the system's attention colour.
    let isAlert: Bool

    /// `failureVisible` limits the failed icon to while the recorder explains
    /// the failure; the phase itself stays `.failed` until the next dictation.
    static func resolve(
        phase: RebuildPhase, meeting: RebuildMeetingSession.Activity, failureVisible: Bool
    ) -> RebuildStatusIcon {
        switch (phase, meeting) {
        case (.recording, _), (_, .capturing):
            return .init(symbol: "record.circle.fill", label: "AudioWhisper: recording", isAlert: true)
        case (.starting, _), (_, .starting):
            return .init(symbol: "mic.circle", label: "AudioWhisper: starting microphone", isAlert: false)
        case (.transcribing, _), (_, .stopping), (_, .processing):
            return .init(symbol: "ellipsis.circle", label: "AudioWhisper: transcribing", isAlert: false)
        case (.failed, .idle) where failureVisible:
            return .init(symbol: "exclamationmark.circle", label: "AudioWhisper: dictation failed", isAlert: false)
        case (.idle, .idle), (.completed, .idle), (.failed, .idle):
            return .idle
        }
    }

    static let idle = RebuildStatusIcon(symbol: "waveform.circle", label: "AudioWhisper", isAlert: false)
}
