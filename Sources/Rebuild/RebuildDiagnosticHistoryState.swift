import AppKit
import Observation
import UniformTypeIdentifiers

/// Owns support actions separately from presentation so export and recovery
/// can be exercised without opening a system file panel or touching user data.
@MainActor
@Observable
final class RebuildDiagnosticHistoryState {
    private(set) var archive = DiagnosticArchive()
    private(set) var message: String?
    private(set) var storageFailed = false
    private let controller: DiagnosticController
    private let destination: () async -> URL?

    init(controller: DiagnosticController? = nil, destination: (() async -> URL?)? = nil) {
        self.controller = controller ?? .shared
        self.destination = destination ?? Self.chooseDestination
    }

    func refresh() async {
        archive = await controller.snapshot()
        storageFailed = await controller.store.storageFailed
    }

    func clear() async {
        do {
            try await controller.clear()
            message = "Diagnostic history cleared."
        } catch { message = "Could not clear diagnostic history." }
        await refresh()
    }

    func export() async {
        do {
            let data = try await controller.export()
            guard let url = await destination() else { return }
            try data.write(to: url, options: .atomic)
            message = "Diagnostics exported. Review the file before sharing it."
        } catch { message = "Could not export diagnostics." }
    }

    static func chooseDestination() async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AudioWhisper-diagnostics.json"
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }
}
