import Foundation
@testable import AudioWhisper

/// Protocol for SourceUsageStore to enable mocking
@MainActor
protocol SourceUsageStoreProtocol {
    var orderedStats: [SourceUsageStats] { get }

    func recordUsage(for info: SourceAppInfo, words: Int, characters: Int)
    func topSources(limit: Int) -> [SourceUsageStats]
    func allSources() -> [SourceUsageStats]
    func reset()
    func rebuild(using records: [TranscriptionRecord])
}

/// Mock implementation for testing source usage tracking
@MainActor
final class MockSourceUsageStore: SourceUsageStoreProtocol {
    // MARK: - State

    var orderedStats: [SourceUsageStats] = []

    // MARK: - Configurable Data

    var topSourcesData: [SourceUsageStats] = []

    // MARK: - Call Tracking

    var recordUsageCallCount = 0
    var recordUsageLastInfo: SourceAppInfo?
    var recordUsageLastWords: Int?
    var recordUsageLastCharacters: Int?

    var topSourcesCallCount = 0
    var topSourcesLastLimit: Int?

    var allSourcesCallCount = 0
    var resetCallCount = 0
    var rebuildCallCount = 0

    // MARK: - Protocol Methods

    func recordUsage(for info: SourceAppInfo, words: Int, characters: Int) {
        recordUsageCallCount += 1
        recordUsageLastInfo = info
        recordUsageLastWords = words
        recordUsageLastCharacters = characters

        // Simulate adding/updating stats
        if let index = orderedStats.firstIndex(where: { $0.bundleIdentifier == info.bundleIdentifier }) {
            var existing = orderedStats[index]
            existing.totalWords += words
            existing.totalCharacters += characters
            existing.sessionCount += 1
            existing.lastUsed = Date()
            orderedStats[index] = existing
        } else {
            let newStat = SourceUsageStats(
                bundleIdentifier: info.bundleIdentifier,
                displayName: info.displayName,
                totalWords: words,
                totalCharacters: characters,
                sessionCount: 1,
                lastUsed: Date(),
                fallbackSymbolName: info.fallbackSymbolName,
                iconData: info.iconData
            )
            orderedStats.append(newStat)
        }

        // Sort by total words descending
        orderedStats.sort { $0.totalWords > $1.totalWords }
    }

    func topSources(limit: Int) -> [SourceUsageStats] {
        topSourcesCallCount += 1
        topSourcesLastLimit = limit

        if !topSourcesData.isEmpty {
            return Array(topSourcesData.prefix(limit))
        }
        return Array(orderedStats.prefix(limit))
    }

    func allSources() -> [SourceUsageStats] {
        allSourcesCallCount += 1
        return orderedStats
    }

    func reset() {
        resetCallCount += 1
        orderedStats = []
    }

    func rebuild(using records: [TranscriptionRecord]) {
        rebuildCallCount += 1
        orderedStats = []

        var statsByBundle: [String: SourceUsageStats] = [:]

        for record in records {
            guard let bundleId = record.sourceAppBundleId, !bundleId.isEmpty else { continue }

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
            if record.date > existing.lastUsed {
                existing.lastUsed = record.date
            }

            statsByBundle[bundleId] = existing
        }

        orderedStats = statsByBundle.values.sorted { $0.totalWords > $1.totalWords }
    }

    // MARK: - Test Helpers

    func resetMock() {
        orderedStats = []
        topSourcesData = []

        recordUsageCallCount = 0
        recordUsageLastInfo = nil
        recordUsageLastWords = nil
        recordUsageLastCharacters = nil
        topSourcesCallCount = 0
        topSourcesLastLimit = nil
        allSourcesCallCount = 0
        resetCallCount = 0
        rebuildCallCount = 0
    }

    func setTopSources(_ sources: [SourceUsageStats]) {
        topSourcesData = sources
        orderedStats = sources
    }

    func addSource(bundleId: String, name: String, words: Int, characters: Int = 0, sessions: Int = 1) {
        let stat = SourceUsageStats(
            bundleIdentifier: bundleId,
            displayName: name,
            totalWords: words,
            totalCharacters: characters > 0 ? characters : words * 5,
            sessionCount: sessions,
            lastUsed: Date(),
            fallbackSymbolName: nil,
            iconData: nil
        )
        orderedStats.append(stat)
        orderedStats.sort { $0.totalWords > $1.totalWords }
    }
}
