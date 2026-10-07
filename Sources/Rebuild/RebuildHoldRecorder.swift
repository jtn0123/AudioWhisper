import Foundation

/// Owns only the recording started by this hold gesture. Native key monitoring
/// stays in the delegate; admission, early release and ownership are testable.
@MainActor
final class RebuildHoldRecorder {
    private let session: RebuildSession
    private var ownedCapture: UUID?
    init(session: RebuildSession) { self.session = session }
    func reset() { ownedCapture = nil }

    func keyDown(mode: PressAndHoldMode) {
        if mode == .hold {
            guard !session.phase.isBusy else { return }
            session.toggleRecording()
            if session.phase == .starting || session.phase == .recording { ownedCapture = session.captureIdentity }
        } else {
            session.toggleRecording()
        }
    }

    func keyUp(mode: PressAndHoldMode) {
        guard mode == .hold, let ownedCapture else { return }
        self.ownedCapture = nil
        guard session.captureIdentity == ownedCapture else { return }
        if session.phase == .starting { session.cancel() }
        if session.phase == .recording { session.finishRecording() }
    }
}
