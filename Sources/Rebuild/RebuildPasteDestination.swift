import AppKit

/// Captures one destination for the entire session, including its activation state.
@MainActor
struct RebuildPasteDestination {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    var activate: () -> Bool
    var isTerminated: () -> Bool
    var foregroundPID: () -> pid_t?

    func activateAndWait(isSessionValid: () -> Bool) async -> Bool {
        guard !Task.isCancelled, isSessionValid(), !isTerminated(), activate() else { return false }
        // A successful activation request can still be waiting for a Space switch.
        let deadline = ContinuousClock.now + .milliseconds(500)
        while foregroundPID() != processIdentifier {
            guard !Task.isCancelled, isSessionValid(), !isTerminated(), ContinuousClock.now < deadline else {
                return false
            }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
        }
        return !Task.isCancelled && isSessionValid() && !isTerminated()
    }

    static func capture() -> Self? {
        guard let target = NSWorkspace.shared.frontmostApplication,
              target.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return Self(
            processIdentifier: target.processIdentifier, bundleIdentifier: target.bundleIdentifier,
            activate: { target.activate() }, isTerminated: { target.isTerminated },
            foregroundPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier })
    }
}
