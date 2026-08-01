import Foundation
import Observation
import os.log

@MainActor
@Observable
internal final class CategoryStore {
    static let shared = CategoryStore()

    private(set) var categories: [CategoryDefinition]
    private var categoriesById: [String: CategoryDefinition]

    private let fileManager: FileManager
    private let storageURL: URL?

    init(fileManager: FileManager = .default, storageURL: URL? = nil) {
        self.fileManager = fileManager
        if let storageURL {
            self.storageURL = storageURL
        } else {
            self.storageURL = try? fileManager
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("AudioWhisper/categories.json", isDirectory: false)
        }

        let defaults = CategoryDefinition.defaults
        categories = defaults
        categoriesById = Dictionary(defaults.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        loadFromDiskIfNeeded()
    }

    func category(withId id: String) -> CategoryDefinition {
        categoriesById[id] ?? CategoryDefinition.fallback
    }

    func containsCategory(withId id: String) -> Bool {
        categoriesById[id] != nil
    }

    func upsert(_ category: CategoryDefinition) {
        if let existingIndex = categories.firstIndex(where: { $0.id == category.id }) {
            categories[existingIndex] = category
        } else {
            categories.append(category)
        }
        rebuildIndex()
        persist()
    }

    func delete(_ category: CategoryDefinition) {
        guard !category.isSystem else { return }
        categories.removeAll { $0.id == category.id }
        rebuildIndex()
        persist()
    }

    func resetToDefaults() {
        categories = CategoryDefinition.defaults
        rebuildIndex()
        persist()
    }

    // MARK: - Persistence

    private func loadFromDiskIfNeeded() {
        guard let storageURL,
              fileManager.fileExists(atPath: storageURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([CategoryDefinition].self, from: data)
            if !decoded.isEmpty {
                categories = decoded
                // H19: dedupe any duplicate ids before they reach rebuildIndex —
                // and heal the on-disk state if we detected duplicates.
                let originalCount = categories.count
                dedupeCategoriesInPlace()
                rebuildIndex()
                if categories.count != originalCount {
                    Logger.app.warning("CategoryStore: removed \(originalCount - self.categories.count) duplicate id(s) from categories.json")
                    persist()
                }
            }
        } catch {
            // Log load failure but keep defaults - file may be corrupted
            Logger.app.warning("CategoryStore: Failed to load categories from disk: \(error.localizedDescription)")
        }
    }

    private func persist() {
        guard let storageURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(categories)
            let dir = storageURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            // Log persistence failures so they can be diagnosed
            Logger.app.error("CategoryStore: Failed to persist categories: \(error.localizedDescription)")
        }
    }

    private func rebuildIndex() {
        // H19: tolerate duplicate ids defensively — keep the last occurrence
        // rather than trapping (Dictionary(uniqueKeysWithValues:) crashes on dup).
        categoriesById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    }

    /// Removes duplicate ids in `categories`, keeping the last occurrence per id.
    /// Order is preserved for unique entries.
    private func dedupeCategoriesInPlace() {
        var seen: Set<String> = []
        var result: [CategoryDefinition] = []
        // Iterate in reverse so the last occurrence wins, matching `rebuildIndex`.
        for category in categories.reversed() where seen.insert(category.id).inserted {
            result.append(category)
        }
        categories = Array(result.reversed())
    }
}

extension CategoryStore {
    func reloadForPreviews() {
        categories = CategoryDefinition.defaults
        rebuildIndex()
    }
}
