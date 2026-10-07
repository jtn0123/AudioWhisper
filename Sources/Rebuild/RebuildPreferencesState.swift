import AppKit
import Observation
import ServiceManagement

@MainActor
struct RebuildPreferencesEffects {
    var checkAccess: () -> Bool
    var openAccessSettings: () -> Void
    var changeLogin: (Bool) throws -> Void
    var loginEnabled: () -> Bool
    var cleanupRetention: () async throws -> Void
    var diagnostics: () async -> String?
    var copy: (String) -> Void
    var recalculate: () async throws -> Void
    var resetUsage: () -> Void

    static var live: Self {
        Self(checkAccess: { AccessibilityPermissionManager().checkPermission() }, openAccessSettings: {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }, changeLogin: { enabled in
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        }, loginEnabled: { SMAppService.mainApp.status == .enabled },
             cleanupRetention: { try await DataManager.shared.cleanupExpiredRecords() }, diagnostics: {
            let report = await RebuildDiagnostics.snapshot(context: "application")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(report) else { return nil }
            return String(data: data, encoding: .utf8)
        }, copy: PasteManager.copyToClipboard,
             recalculate: { try await UsageMetricsStore.shared.rebuildFromHistory() },
             resetUsage: { UsageMetricsStore.shared.reset() })
    }
}

@MainActor
@Observable
final class RebuildPreferencesState {
    let effects: RebuildPreferencesEffects
    var message: String?
    var accessibilityAllowed: Bool
    var showAdvanced = false
    var resetUsage = false

    init(effects: RebuildPreferencesEffects? = nil) {
        self.effects = effects ?? .live
        accessibilityAllowed = self.effects.checkAccess()
    }

    func refreshAccess() -> Bool {
        let allowed = effects.checkAccess()
        guard allowed != accessibilityAllowed else { return false }
        accessibilityAllowed = allowed
        return true
    }
}
