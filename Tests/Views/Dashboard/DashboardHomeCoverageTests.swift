import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

/// Renders DashboardHomeView and its section extensions to exercise view bodies.
@MainActor
final class DashboardHomeCoverageTests: XCTestCase {

    private func makeMetricsStore() -> UsageMetricsStore {
        let suite = "DashboardHomeCoverage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return UsageMetricsStore(defaults: defaults)
    }

    private func makeSourceStore() -> SourceUsageStore {
        let suite = "DashboardHomeCoverageSrc-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return SourceUsageStore(defaults: defaults)
    }

    private func makeRecord(
        provider: TranscriptionProvider = .local,
        wordCount: Int = 25,
        appName: String? = "Notes"
    ) -> TranscriptionRecord {
        TranscriptionRecord(
            text: String(repeating: "word ", count: wordCount),
            provider: provider,
            duration: 5.0,
            wordCount: wordCount,
            characterCount: wordCount * 5,
            sourceAppBundleId: appName == nil ? nil : "com.apple.Notes",
            sourceAppName: appName,
            sourceAppIconData: nil
        )
    }

    private func render<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        host.layout()
    }

    private func sourceInfo(_ bundle: String, _ name: String) -> SourceAppInfo {
        SourceAppInfo(
            bundleIdentifier: bundle,
            displayName: name,
            iconData: nil,
            fallbackSymbolName: nil
        )
    }

    // MARK: - Empty data path

    func testRendersWithEmptyData() {
        let dm = MockDataManager()
        let view = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: makeMetricsStore(),
            sourceUsageStore: makeSourceStore(),
            dataManager: dm
        )
        render(view)
    }

    func testHeaderSubtitleEmpty() {
        let view = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: makeMetricsStore(),
            sourceUsageStore: makeSourceStore(),
            dataManager: MockDataManager()
        )
        XCTAssertEqual(view.headerSubtitle, "Start recording to see your stats")
    }

    // MARK: - Populated data path

    func testRendersWithPopulatedData() async {
        let metrics = makeMetricsStore()
        metrics.recordSession(duration: 120, wordCount: 200, characterCount: 1000)
        metrics.recordSession(duration: 60, wordCount: 80, characterCount: 400)

        let source = makeSourceStore()
        source.recordUsage(
            for: sourceInfo("com.apple.Notes", "Notes"),
            words: 150,
            characters: 800
        )

        let dm = MockDataManager()
        dm.addRecords([
            makeRecord(provider: .local, wordCount: 100),
            makeRecord(provider: .parakeet, wordCount: 200, appName: nil),
            makeRecord(provider: .local, wordCount: 50)
        ])

        let view = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: metrics,
            sourceUsageStore: source,
            dataManager: dm
        )
        view.loadDashboardData()
        // Allow async loadDashboardData task to settle.
        try? await Task.sleep(for: .milliseconds(150))
        render(view)
    }

    // MARK: - Section bodies directly

    func testRenderStatsAndHeaderSections() {
        let metrics = makeMetricsStore()
        metrics.recordSession(duration: 7200, wordCount: 500, characterCount: 2500)
        let view = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: metrics,
            sourceUsageStore: makeSourceStore(),
            dataManager: MockDataManager()
        )
        render(view.statsSection)
        render(view.pageHeader)
        XCTAssertFalse(view.headerSubtitle.isEmpty)
    }

    func testRenderActivitySection() {
        let metrics = makeMetricsStore()
        metrics.recordSession(duration: 60, wordCount: 120, characterCount: 600)
        let view = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: metrics,
            sourceUsageStore: makeSourceStore(),
            dataManager: MockDataManager()
        )
        view.calculateDailyActivity(from: [makeRecord(wordCount: 120)])
        render(view.activitySection)
        render(view.activityGrid)
    }

    func testRenderRecentSectionEmptyAndPopulated() {
        let view = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: makeMetricsStore(),
            sourceUsageStore: makeSourceStore(),
            dataManager: MockDataManager()
        )
        render(view.recentSection)
        render(view.emptyRecentView)

        // transcriptRow is a pure function of its record argument; render it
        // directly rather than relying on @State mutation outside a view tree.
        let localRecord = makeRecord(provider: .local, wordCount: 30)
        let parakeetRecord = makeRecord(provider: .parakeet, wordCount: 60, appName: nil)
        render(view.transcriptRow(localRecord))
        render(view.transcriptRow(parakeetRecord))
    }

    func testRenderSourcesSectionEmptyProvidersAndSources() {
        // Empty everything -> emptySourcesView branch.
        let emptyView = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: makeMetricsStore(),
            sourceUsageStore: makeSourceStore(),
            dataManager: MockDataManager()
        )
        render(emptyView.sourcesSection)
        render(emptyView.emptySourcesView)

        // providerRow is a pure function of its arguments; render it directly.
        render(emptyView.providerRow(
            ProviderStat(provider: "local", words: 200, icon: "laptopcomputer"),
            index: 1
        ))
        render(emptyView.providerRow(
            ProviderStat(provider: "parakeet", words: 100, icon: "bird"),
            index: 2
        ))

        // Sources branch.
        let source = makeSourceStore()
        source.recordUsage(
            for: sourceInfo("com.apple.Notes", "Notes"),
            words: 100,
            characters: 500
        )
        let sourcesView = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: makeMetricsStore(),
            sourceUsageStore: source,
            dataManager: MockDataManager()
        )
        render(sourcesView.sourcesSection)
        if let stat = source.topSources(limit: 5).first {
            render(sourcesView.sourceRow(stat, index: 1))
        }
    }

    // MARK: - Helper coverage

    func testProviderHelpers() {
        let view = DashboardHomeView(
            selectedNav: .constant(.dashboard),
            metricsStore: makeMetricsStore(),
            sourceUsageStore: makeSourceStore(),
            dataManager: MockDataManager()
        )
        for provider in ["openai", "gemini", "local", "parakeet", "unknown"] {
            _ = view.providerColor(for: provider)
            _ = view.providerIcon(for: provider)
            XCTAssertFalse(view.providerDisplayName(for: provider).isEmpty)
        }
        XCTAssertEqual(view.formatNumber(12345), "12,345")
        XCTAssertEqual(view.formatDecimal(-1), "0")
        XCTAssertEqual(view.formatDecimal(42.6), "43")
        XCTAssertEqual(view.formatDuration(0), "0m")
        XCTAssertFalse(view.formatTime(Date()).isEmpty)
        XCTAssertFalse(view.heatmapTooltip(date: Date(), words: 5).isEmpty)
        _ = view.heatmapColor(for: 0)
        _ = view.heatmapColor(for: 200)
        _ = view.generateActivityWeeks()
    }
}
