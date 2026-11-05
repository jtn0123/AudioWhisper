import Foundation

struct AppDictationRule: Codable, Equatable, Identifiable, Sendable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    var appName: String
    var modeID: UUID
    var enabled = true
}

struct ResolvedDictationMode: Equatable, Sendable {
    enum Origin: String, Sendable { case custom, manual, appRule }
    let id: UUID?
    let name: String?
    let origin: Origin
    let settings: DictationModeSettings

    var selection: RebuildModelSelection {
        RebuildModelSelection(provider: settings.provider, whisper: settings.whisper, parakeet: settings.parakeet)
    }

    static func resolve(
        app: String?, selection: (automatic: Bool, selectedID: UUID?), modes: [SavedDictationMode],
        rules: [AppDictationRule], fallback: DictationModeSettings
    ) -> Self {
        if selection.automatic, let rule = rules.first(where: { $0.enabled && $0.bundleIdentifier == app }),
           let mode = modes.first(where: { $0.id == rule.modeID }) {
            return Self(id: mode.id, name: mode.name, origin: .appRule, settings: mode.settings)
        }
        if let mode = modes.first(where: { $0.id == selection.selectedID && $0.settings == fallback }) {
            return Self(id: mode.id, name: mode.name, origin: .manual, settings: mode.settings)
        }
        return Self(id: nil, name: nil, origin: .custom, settings: fallback)
    }
}

extension AppDefaults {
    static var automaticDictationModes: Bool {
        get { defaults.bool(forKey: Key.automaticDictationModes.rawValue) }
        set { defaults.set(newValue, forKey: Key.automaticDictationModes.rawValue) }
    }

    static var appDictationRules: [AppDictationRule] {
        get {
            guard let data = defaults.data(forKey: Key.appDictationRules.rawValue) else { return [] }
            return (try? JSONDecoder().decode([AppDictationRule].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.appDictationRules.rawValue)
        }
    }

    static func resolveDictationMode(app: String?, allowAppRule: Bool) -> ResolvedDictationMode {
        ResolvedDictationMode.resolve(app: app,
            selection: (automatic: allowAppRule && automaticDictationModes, selectedID: selectedDictationModeID),
            modes: savedDictationModes,
            rules: appDictationRules, fallback: currentDictationSettings)
    }
}
