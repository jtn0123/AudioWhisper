/// Runs the quit-time cleanup, but never lets it hold the app open: a wedged
/// daemon or history write must not turn ⌘Q into a hang.
@MainActor
enum RebuildTermination {
    nonisolated static let deadline: Duration = .seconds(3)

    /// Calls `reply` exactly once: when `work` finishes or at `deadline`,
    /// whichever comes first.
    static func run(
        deadline: Duration = deadline, work: @escaping @MainActor () async -> Void,
        reply: @escaping @MainActor () -> Void
    ) {
        var replied = false
        let finish: @MainActor () -> Void = {
            guard !replied else { return }
            replied = true
            reply()
        }
        Task { @MainActor in
            await work()
            finish()
        }
        Task { @MainActor in
            try? await Task.sleep(for: deadline)
            finish()
        }
    }
}
