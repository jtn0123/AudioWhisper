import Foundation

enum RebuildDeepLink {
    /// Navigation only. A URL cannot silently record, install models, change
    /// context consent, read a file, switch a mode, or paste into another app.
    static func page(_ url: URL) -> RebuildPage? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "audiowhisper", components.host == "open",
              components.path.isEmpty, components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let items = components.queryItems, items.count == 1, items[0].name == "page",
              let raw = items[0].value else { return nil }
        return RebuildPage(rawValue: raw)
    }
}
