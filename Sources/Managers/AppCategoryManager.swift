import Foundation
import Observation
import os.log

@MainActor
@Observable
internal final class AppCategoryManager {
    static let shared = AppCategoryManager()

    private let userDefaultsKey = "appCategoryMappings"
    private let defaults: UserDefaults
    private let categoryStore: CategoryStore

    /// Soft cap on the number of user-override mappings persisted to
    /// `UserDefaults`. Without it, every distinct app the user ever
    /// categorizes accumulates indefinitely (bug L3). 200 is generous for
    /// real-world use — most users categorize fewer than 30 apps.
    private static let maxUserMappings = 200

    // Built-in mappings (can be overridden by user)
    private static let builtInMappings: [String: String] = [
        // Terminal
        "com.mitchellh.ghostty": "terminal",
        "com.apple.Terminal": "terminal",
        "com.googlecode.iterm2": "terminal",
        "net.kovidgoyal.kitty": "terminal",
        "co.zeit.hyper": "terminal",
        "com.github.wez.wezterm": "terminal",

        // Coding
        "com.microsoft.VSCode": "coding",
        "com.todesktop.230313mzl4w4u92": "coding", // Cursor
        "dev.zed.Zed": "coding",
        "com.apple.dt.Xcode": "coding",
        "com.sublimetext.4": "coding",
        "com.jetbrains.intellij": "coding",
        "com.jetbrains.pycharm": "coding",
        "com.jetbrains.WebStorm": "coding",
        "com.jetbrains.goland": "coding",
        "abnerworks.Typora": "coding",

        // Chat
        "com.tinyspeck.slackmacgap": "chat",
        "com.hnc.Discord": "chat",
        "us.zoom.xos": "chat",
        "com.apple.MobileSMS": "chat",
        "ru.keepcoder.Telegram": "chat",
        "net.whatsapp.WhatsApp": "chat",
        "com.microsoft.teams2": "chat",

        // Email
        "com.apple.mail": "email",
        "com.microsoft.Outlook": "email",
        "com.readdle.smartemail-Mac": "email", // Spark
        "com.superhuman.electron": "email",
        "com.google.Gmail": "email",
        "com.freron.MailMate": "email",

        // Writing
        "com.apple.Notes": "writing",
        "md.obsidian": "writing",
        "notion.id": "writing",
        "com.notion.id": "writing",
        "com.apple.iWork.Pages": "writing",
        "com.microsoft.Word": "writing",

        // Browsers default to general
        "com.google.Chrome": "general",
        "com.apple.Safari": "general",
        "company.thebrowser.Browser": "general", // Arc
        "org.mozilla.firefox": "general"
    ]

    private(set) var userMappings: [String: String] = [:]

    init(defaults: UserDefaults = AppDefaults.defaults, categoryStore: CategoryStore? = nil) {
        // A5: resolved in the body rather than as a default argument.
        // Default-argument expressions are evaluated in the CALLER's
        // isolation, so referencing a @MainActor `.shared` there warns
        // ("error in the Swift 6 language mode") even though this type is
        // itself @MainActor. Same pattern DashboardHomeView already uses.
        self.defaults = defaults
        self.categoryStore = categoryStore ?? .shared
        loadUserMappings()
    }

    // MARK: - Public API

    var availableCategories: [CategoryDefinition] {
        categoryStore.categories
    }

    func category(for bundleId: String) -> CategoryDefinition {
        let categoryId = categoryId(for: bundleId)
        return categoryStore.category(withId: categoryId)
    }

    func categoryId(for bundleId: String) -> String {
        if let userRaw = userMappings[bundleId], categoryStore.containsCategory(withId: userRaw) {
            return userRaw
        }
        return Self.builtInMappings[bundleId] ?? CategoryDefinition.fallback.id
    }

    func setCategory(_ category: CategoryDefinition, for bundleId: String) {
        setCategory(id: category.id, for: bundleId)
    }

    func setCategory(id categoryId: String, for bundleId: String) {
        guard categoryStore.containsCategory(withId: categoryId) else { return }
        userMappings[bundleId] = categoryId
        evictExcessUserMappings()
        saveUserMappings()
    }

    /// Enforces the `maxUserMappings` soft cap by dropping deterministic
    /// entries (alphabetically lowest bundle IDs) when over the cap.
    /// Dictionary iteration order is undefined, so we sort to pick a
    /// reproducible victim. Logs each eviction so users hitting the cap can
    /// see what was removed. See bug L3.
    private func evictExcessUserMappings() {
        while userMappings.count > Self.maxUserMappings,
              let evictKey = userMappings.keys.sorted().first {
            userMappings.removeValue(forKey: evictKey)
            Logger.app.notice(
                "AppCategoryManager: evicted user mapping for \(evictKey, privacy: .public) (cap \(Self.maxUserMappings))"
            )
        }
    }

    func resetToDefault(for bundleId: String) {
        userMappings.removeValue(forKey: bundleId)
        saveUserMappings()
    }

    func isUserOverridden(_ bundleId: String) -> Bool {
        return userMappings[bundleId] != nil
    }

    // MARK: - Persistence

    private func loadUserMappings() {
        if let data = defaults.dictionary(forKey: userDefaultsKey) as? [String: String] {
            userMappings = data
            // Apply the cap on load so a pre-existing oversized mapping
            // (from before this fix) gets trimmed (bug L3). Persist the
            // trimmed result if anything was evicted.
            let originalCount = userMappings.count
            evictExcessUserMappings()
            if userMappings.count != originalCount {
                saveUserMappings()
            }
        }
    }

    private func saveUserMappings() {
        defaults.set(userMappings, forKey: userDefaultsKey)
    }
}
