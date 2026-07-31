import Foundation
import AppKit
import Observation

internal struct SourceAppInfo: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let iconData: Data?
    let fallbackSymbolName: String?
    
    static var unknown: SourceAppInfo {
        SourceAppInfo(
            bundleIdentifier: "unknown",
            displayName: "Background trigger",
            iconData: nil,
            fallbackSymbolName: "questionmark.app"
        )
    }
    
    static func from(app: NSRunningApplication) -> SourceAppInfo? {
        guard let bundleId = app.bundleIdentifier else {
            return nil
        }
        let name = app.localizedName ?? bundleId
        let iconData = SourceAppInfo.pngData(from: app.icon)
        return SourceAppInfo(
            bundleIdentifier: bundleId,
            displayName: name,
            iconData: iconData,
            fallbackSymbolName: nil
        )
    }
    
    private static func pngData(from image: NSImage?) -> Data? {
        guard let tiffData = image?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

internal struct SourceUsageStats: Codable, Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    var displayName: String
    var totalWords: Int
    var totalCharacters: Int
    var sessionCount: Int
    var lastUsed: Date
    var fallbackSymbolName: String?

    // iconData is NOT stored in UserDefaults (excluded from Codable) to avoid 4MB+ storage limit
    // Icons are loaded dynamically from bundle when needed
    var iconData: Data?

    // Exclude iconData from encoding to prevent UserDefaults overflow
    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, displayName, totalWords, totalCharacters
        case sessionCount, lastUsed, fallbackSymbolName
    }

    var initials: String {
        let components = displayName.split(separator: " ")
        let chars: [Character] = components.prefix(2).compactMap { $0.first }
        if chars.isEmpty, let first = displayName.first {
            return String(first)
        }
        return String(chars)
    }

    func nsImage() -> NSImage? {
        // First try cached iconData
        if let iconData = iconData {
            return NSImage(data: iconData)
        }
        // Fallback: load from bundle
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

@Observable
@MainActor
internal final class SourceUsageStore {
    static let shared = SourceUsageStore()
    
    private let defaults: UserDefaults
    private let storageKey = "sourceUsage.stats"
    private let maxSources = 50
    
    private(set) var orderedStats: [SourceUsageStats] = []
    private var statsByBundle: [String: SourceUsageStats] = [:]
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([String: SourceUsageStats].self, from: data) {
                statsByBundle = decoded
                orderedStats = decoded.values.sorted(by: defaultSort)
                // Re-persist immediately to strip out any legacy iconData from old format
                // This is a one-time migration that reduces UserDefaults size
                persist()
                return
            }
        }
        statsByBundle = [:]
        orderedStats = []
    }
    
    func recordUsage(for info: SourceAppInfo, words: Int, characters: Int) {
        // Record the session even when `words == 0`: `sessionCount`, `lastUsed`
        // and characters must still be tracked so this store agrees with
        // `UsageMetricsStore` on session totals (bug #47).
        var existing = statsByBundle[info.bundleIdentifier] ?? SourceUsageStats(
            bundleIdentifier: info.bundleIdentifier,
            displayName: info.displayName,
            totalWords: 0,
            totalCharacters: 0,
            sessionCount: 0,
            lastUsed: Date(),
            fallbackSymbolName: info.fallbackSymbolName,
            iconData: info.iconData
        )
        existing.totalWords += words
        existing.totalCharacters += characters
        existing.sessionCount += 1
        existing.lastUsed = Date()
        if existing.displayName != info.displayName {
            existing.displayName = info.displayName
        }
        if existing.iconData == nil {
            existing.iconData = info.iconData
        }
        if existing.fallbackSymbolName == nil {
            existing.fallbackSymbolName = info.fallbackSymbolName
        }
        statsByBundle[existing.bundleIdentifier] = existing
        // Refresh ordered stats BEFORE trimming so we trim based on current data
        refreshOrderedStats()
        trimIfNeeded()
        persist()
    }
    
    func topSources(limit: Int) -> [SourceUsageStats] {
        Array(orderedStats.prefix(limit))
    }
    
    func allSources() -> [SourceUsageStats] {
        orderedStats
    }
    
    private func trimIfNeeded() {
        guard statsByBundle.count > maxSources else { return }
        let surplus = statsByBundle.count - maxSources
        // Evict the least-recently-used apps. Trimming by lowest `totalWords`
        // would evict a brand-new recently-active app first (it has the fewest
        // words), which is exactly the data we want to keep (bug #46).
        let leastRecentlyUsed = statsByBundle.values
            .sorted { $0.lastUsed < $1.lastUsed }
            .prefix(surplus)
        for stat in leastRecentlyUsed {
            statsByBundle[stat.bundleIdentifier] = nil
        }
        refreshOrderedStats()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(statsByBundle) {
            defaults.set(data, forKey: storageKey)
        }
    }
    
    private func refreshOrderedStats() {
        orderedStats = statsByBundle.values.sorted(by: defaultSort)
    }
    
    private var defaultSort: (SourceUsageStats, SourceUsageStats) -> Bool {
        { lhs, rhs in
            if lhs.totalWords == rhs.totalWords {
                return lhs.lastUsed > rhs.lastUsed
            }
            return lhs.totalWords > rhs.totalWords
        }
    }

    /// Clears all persisted source usage stats.
    func reset() {
        statsByBundle = [:]
        orderedStats = []
        defaults.removeObject(forKey: storageKey)
    }

    /// Rebuilds source usage stats from the given transcription records.
    /// This is used when records are deleted to ensure stats stay in sync.
    func rebuild(using records: [TranscriptionRecord]) {
        statsByBundle = [:]

        for record in records {
            guard let bundleId = record.sourceAppBundleId, !bundleId.isEmpty else {
                continue
            }

            var existing = statsByBundle[bundleId] ?? SourceUsageStats(
                bundleIdentifier: bundleId,
                displayName: record.sourceAppName ?? bundleId,
                totalWords: 0,
                totalCharacters: 0,
                sessionCount: 0,
                lastUsed: record.date,
                fallbackSymbolName: nil,
                iconData: record.sourceAppIconData
            )

            existing.totalWords += record.wordCount
            existing.totalCharacters += record.characterCount
            existing.sessionCount += 1

            // Track the most recent usage date
            if record.date > existing.lastUsed {
                existing.lastUsed = record.date
            }

            // Update display name if we have a newer one
            if let name = record.sourceAppName, !name.isEmpty {
                existing.displayName = name
            }

            // Keep icon data from records
            if existing.iconData == nil, let iconData = record.sourceAppIconData {
                existing.iconData = iconData
            }

            statsByBundle[bundleId] = existing
        }

        refreshOrderedStats()
        trimIfNeeded()
        persist()
    }

    /// Subtracts a single record's contribution from its source app's stats.
    ///
    /// B5/G2: avoids the full-table fetch `DataManager.deleteRecord` previously
    /// needed to call `rebuild(using:)`.
    ///
    /// `totalWords`, `totalCharacters` and `sessionCount` are plain sums, so this
    /// is exact. `lastUsed` is NOT: `rebuild` derives it as the maximum record
    /// date for the app, and recovering the next-most-recent date after removing
    /// the newest would require the very fetch this avoids. It is therefore left
    /// untouched, which can leave it slightly too recent until the app is used
    /// again or an explicit rebuild runs. `lastUsed` only affects dashboard sort
    /// order, so a stale value is cosmetic — unlike a full-table load on every
    /// delete.
    ///
    /// The app's entry is dropped entirely once its session count reaches zero.
    func remove(record: TranscriptionRecord) {
        guard let bundleId = record.sourceAppBundleId, !bundleId.isEmpty,
              var existing = statsByBundle[bundleId] else {
            return
        }

        existing.totalWords = max(0, existing.totalWords - record.wordCount)
        existing.totalCharacters = max(0, existing.totalCharacters - record.characterCount)
        existing.sessionCount = max(0, existing.sessionCount - 1)

        if existing.sessionCount == 0 {
            statsByBundle.removeValue(forKey: bundleId)
        } else {
            statsByBundle[bundleId] = existing
        }

        refreshOrderedStats()
        persist()
    }

    func resetForTesting() {
        reset()
    }
}
