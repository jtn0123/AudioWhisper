import XCTest
import SwiftUI
import SwiftData
@testable import AudioWhisper

@MainActor
final class UISnapshotTests: SnapshotTestCase {
    let defaults = AppDefaults.defaults

    override func setUp() async throws {
        try await super.setUp()
        resetAppStorage()
    }

    override func tearDown() async throws {
        UsageMetricsStore.shared.reset()
        SourceUsageStore.shared.resetForTesting()
        try await super.tearDown()
    }

    func testWelcomeViewSnapshot() {
        defaults.set(TranscriptionProvider.local.rawValue, forKey: "transcriptionProvider")
        defaults.set(WhisperModel.base.rawValue, forKey: "selectedWhisperModel")

        let view = WelcomeView()
        assertSnapshot(
            view,
            named: "WelcomeView-light",
            size: LayoutMetrics.Welcome.windowSize,
            colorScheme: .light
        )
    }

    func testDashboardViewSnapshot() {
        seedUsageMetrics()
        seedSourceUsage()

        let view = DashboardView()
        assertSnapshot(
            view,
            named: "DashboardView-light",
            size: LayoutMetrics.DashboardWindow.previewSize,
            colorScheme: .light
        )

        UsageMetricsStore.shared.reset()
        SourceUsageStore.shared.resetForTesting()
    }

    // Was Deferred(G1), now fixed. The G1 refactor moved this view from @Query
    // (synchronous on appear) to an async paged fetch, so the snapshot captured
    // the loading state instead of the records. The seam it wanted already
    // existed: TranscriptionHistoryViewModel takes an injectable
    // DataManagerProtocol, so the load can be awaited BEFORE rendering rather
    // than raced against ImageRenderer.
    func testTranscriptionHistoryViewSnapshot() async {
        let viewModel = await makeLoadedHistoryViewModel()

        assertSnapshot(
            TranscriptionHistoryView(viewModel: viewModel),
            named: "TranscriptionHistoryView-dark",
            size: CGSize(width: 750, height: 600),
            colorScheme: .dark
        )
    }

    // MARK: - Provider View Snapshots

    func testDashboardProvidersViewLocalSnapshot() {
        defaults.set(TranscriptionProvider.local.rawValue, forKey: "transcriptionProvider")
        defaults.set(WhisperModel.base.rawValue, forKey: "selectedWhisperModel")

        let view = DashboardProvidersView()
        assertSnapshot(
            view,
            named: "DashboardProvidersView-local-selected",
            size: CGSize(width: 750, height: 800),
            colorScheme: .light
        )
    }

    func testDashboardProvidersViewParakeetSnapshot() {
        defaults.set(TranscriptionProvider.parakeet.rawValue, forKey: "transcriptionProvider")

        let view = DashboardProvidersView()
        assertSnapshot(
            view,
            named: "DashboardProvidersView-parakeet-selected",
            size: CGSize(width: 750, height: 800),
            colorScheme: .light
        )
    }

    // MARK: - Correction View Snapshots

    func testDashboardCorrectionViewModeOffSnapshot() {
        defaults.set(SemanticCorrectionMode.off.rawValue, forKey: "semanticCorrectionMode")

        let view = DashboardCorrectionView()
        assertSnapshot(
            view,
            named: "DashboardCorrectionView-mode-off",
            size: CGSize(width: 750, height: 600),
            colorScheme: .light
        )
    }

    func testDashboardCorrectionViewModeLocalMLXSnapshot() {
        defaults.set(SemanticCorrectionMode.localMLX.rawValue, forKey: "semanticCorrectionMode")

        let view = DashboardCorrectionView()
        assertSnapshot(
            view,
            named: "DashboardCorrectionView-mode-localMLX",
            size: CGSize(width: 750, height: 700),
            colorScheme: .light
        )
    }

    // MARK: - Categories View Snapshots

    func testDashboardCategoriesViewEmptySnapshot() {
        // Categories view with default state
        let view = DashboardCategoriesView()
        assertSnapshot(
            view,
            named: "DashboardCategoriesView-default",
            size: CGSize(width: 750, height: 600),
            colorScheme: .light
        )
    }

    // MARK: - Category Editor Snapshots

    func testCategoryEditorSheetCreateSnapshot() {
        let view = CategoryEditorSheet(
            category: nil,
            onSave: { _ in },
            onDelete: nil
        )
        assertSnapshot(
            view,
            named: "CategoryEditorSheet-create",
            size: CGSize(width: 560, height: 680),
            colorScheme: .light
        )
    }

    func testCategoryEditorSheetEditSnapshot() {
        let category = CategoryDefinition(
            id: "test-category",
            displayName: "Test Category",
            icon: "star.fill",
            colorHex: "#FF5500",
            promptDescription: "A test category for editing",
            promptTemplate: "Correct the following text:\n{text}",
            isSystem: false
        )
        let view = CategoryEditorSheet(
            category: category,
            onSave: { _ in },
            onDelete: { }
        )
        assertSnapshot(
            view,
            named: "CategoryEditorSheet-edit",
            size: CGSize(width: 560, height: 680),
            colorScheme: .light
        )
    }

    // MARK: - Dark Mode Snapshots

    func testWelcomeViewDarkSnapshot() {
        defaults.set(TranscriptionProvider.local.rawValue, forKey: "transcriptionProvider")
        defaults.set(WhisperModel.base.rawValue, forKey: "selectedWhisperModel")

        let view = WelcomeView()
        assertSnapshot(
            view,
            named: "WelcomeView-dark",
            size: LayoutMetrics.Welcome.windowSize,
            colorScheme: .dark
        )
    }

    func testDashboardViewDarkSnapshot() {
        seedUsageMetrics()
        seedSourceUsage()

        let view = DashboardView()
        assertSnapshot(
            view,
            named: "DashboardView-dark",
            size: LayoutMetrics.DashboardWindow.previewSize,
            colorScheme: .dark
        )

        UsageMetricsStore.shared.reset()
        SourceUsageStore.shared.resetForTesting()
    }

    func testTranscriptionHistoryViewLightSnapshot() async {
        let viewModel = await makeLoadedHistoryViewModel()

        assertSnapshot(
            TranscriptionHistoryView(viewModel: viewModel),
            named: "TranscriptionHistoryView-light",
            size: CGSize(width: 750, height: 600),
            colorScheme: .light
        )
    }

    // MARK: - Additional Provider View Snapshots (D3)

    func testDashboardProvidersViewLocalDarkSnapshot() {
        defaults.set(TranscriptionProvider.local.rawValue, forKey: "transcriptionProvider")
        defaults.set(WhisperModel.base.rawValue, forKey: "selectedWhisperModel")

        let view = DashboardProvidersView()
        assertSnapshot(
            view,
            named: "DashboardProvidersView-local-dark",
            size: CGSize(width: 750, height: 800),
            colorScheme: .dark
        )
    }
}

// MARK: - Helpers
extension UISnapshotTests {
    func resetAppStorage() {
        let keys = [
            "transcriptionProvider",
            "selectedWhisperModel",
            "selectedParakeetModel",
            "hasSetupParakeet",
            "hasSetupLocalLLM",
            "openAIBaseURL",
            "geminiBaseURL",
            "maxModelStorageGB",
            "globalHotkey",
            "pressAndHoldEnabled",
            "pressAndHoldKeyIdentifier",
            "pressAndHoldMode",
            "selectedMicrophone",
            "transcriptionHistoryEnabled",
            // Waveform-related keys, cleared so each test starts from a
            // known baseline regardless of earlier tests' AppStorage writes.
            "waveformStyle",
            "visualIntensity",
            "semanticCorrectionMode"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
    
    func seedUsageMetrics() {
        let snapshot = UsageSnapshot(
            totalSessions: 8,
            totalDuration: 540,
            totalWords: 2750,
            totalCharacters: 13800,
            lastUpdated: ISO8601DateFormatter().date(from: "2025-12-10T12:00:00Z"),
            dailyActivity: [
                "2025-12-10": 500,
                "2025-12-09": 450,
                "2025-12-08": 600,
                "2025-12-07": 400,
                "2025-12-06": 300,
                "2025-12-05": 500
            ]
        )
        UsageMetricsStore.shared.setSnapshotForTesting(snapshot)
    }
    
    func seedSourceUsage() {
        let store = SourceUsageStore.shared
        store.resetForTesting()
        
        let sources = [
            SourceAppInfo(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit",
                          iconData: nil, fallbackSymbolName: "doc.text"),
            SourceAppInfo(bundleIdentifier: "com.apple.Safari", displayName: "Safari",
                          iconData: nil, fallbackSymbolName: "safari.fill"),
            SourceAppInfo(bundleIdentifier: "com.slack.slackmacgap", displayName: "Slack",
                          iconData: nil, fallbackSymbolName: "bubble.left.and.bubble.right.fill")
        ]
        
        store.recordUsage(for: sources[0], words: 1200, characters: 6000)
        store.recordUsage(for: sources[1], words: 800, characters: 4100)
        store.recordUsage(for: sources[2], words: 650, characters: 3400)
    }
    
    /// A history view model already holding `sampleHistoryRecords`, with the
    /// first page load completed.
    ///
    /// Awaiting the load here is the whole point: the view renders
    /// `TranscriptionHistoryLoadingView` until `records` is populated, and
    /// ImageRenderer captures immediately, so a view model that loads during
    /// render snapshots the spinner.
    func makeLoadedHistoryViewModel() async -> TranscriptionHistoryViewModel {
        let dataManager = MockDataManager()
        dataManager.recordsToReturn = Self.sampleHistoryRecords()

        let viewModel = TranscriptionHistoryViewModel(dataManager: dataManager, pageSize: 50)
        await viewModel.loadRecords(reset: true)
        return viewModel
    }

    /// Records with FIXED dates.
    ///
    /// `TranscriptionRecord.init` always stamps `Date()`, and the row renders it
    /// through an absolute medium/short `DateFormatter`. Left alone, every
    /// recording run would produce a different image. Pinning the dates makes
    /// the render stable indefinitely — an absolute format does not drift the
    /// way a relative one ("2 minutes ago") would.
    static func sampleHistoryRecords() -> [TranscriptionRecord] {
        let anchor = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01 00:00 UTC

        let records = [
            TranscriptionRecord(
                text: "This is a sample transcription from Parakeet service. "
                    + "It demonstrates how the history view will look with longer text content.",
                provider: .parakeet,
                duration: 12.5,
                modelUsed: "parakeet-tdt-0.6b-v3"
            ),
            TranscriptionRecord(
                text: "Meeting notes about upcoming launch. Includes key dates and action items.",
                provider: .local,
                duration: 8.3,
                modelUsed: "base"
            ),
            TranscriptionRecord(
                text: "Quick local test recording to verify offline pipeline works correctly.",
                provider: .local,
                duration: 4.2,
                modelUsed: "tiny"
            )
        ]

        for (index, record) in records.enumerated() {
            record.date = anchor.addingTimeInterval(Double(-index) * 3600)
        }
        return records
    }

    func makePreviewContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        
        let sampleRecords = [
            TranscriptionRecord(
                text: "This is a sample transcription from Parakeet service. "
                    + "It demonstrates how the history view will look with longer text content.",
                provider: .parakeet,
                duration: 12.5,
                modelUsed: "parakeet-ctc-1.1b"
            ),
            TranscriptionRecord(
                text: "Meeting notes about upcoming launch. Includes key dates and action items.",
                provider: .local,
                duration: 8.3,
                modelUsed: "base"
            ),
            TranscriptionRecord(
                text: "Quick local test recording to verify offline pipeline works correctly.",
                provider: .local,
                duration: 4.2,
                modelUsed: "tiny"
            )
        ]
        
        for record in sampleRecords {
            context.insert(record)
        }
        try context.save()
        return container
    }
}
