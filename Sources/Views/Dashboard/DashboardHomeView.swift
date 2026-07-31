import SwiftUI
import SwiftData
import AppKit

// MARK: - DashboardHomeView (refined)
//
// What changed vs the previous version:
// 1. Stats card: one hero metric ("Words this month" 52pt serif + sparkline +
//    delta), two supporting sub-stats. Replaces three equally-weighted numbers.
// 2. Activity: 28-day continuous waveform-shaped histogram. Replaces the
//    4×7 GitHub-style heatmap grid. Best day / Daily average summary below.
// 3. Sources: no rank column; usage bar painted behind each row. App icon
//    upgraded to 28pt.
// 4. Card cornerRadius: 10pt (was 2). Real serif (`.serif`) for headings.
// 5. All data helpers (calculateDailyActivity, calculateStreak, etc.) kept
//    intact — only the visual rendering changed.

// MARK: - ProviderStat

/// Aggregated transcription usage for a single provider. Replaces what was
/// previously a 3-member tuple so it satisfies the `large_tuple` lint rule.
internal struct ProviderStat {
    let provider: String
    let words: Int
    let icon: String
}

internal struct DashboardHomeView: View {
    @Binding var selectedNav: DashboardNavItem
    @State private var metricsStore: UsageMetricsStore
    @State var sourceUsageStore: SourceUsageStore
    @State var recentRecords: [TranscriptionRecord] = []
    @State private var dailyActivity: [Date: Int] = [:]
    @State var providerStats: [ProviderStat] = []
    @State private var isLoaded = false

    private let dataManager: DataManagerProtocol

    init(
        selectedNav: Binding<DashboardNavItem>,
        metricsStore: UsageMetricsStore? = nil,
        sourceUsageStore: SourceUsageStore? = nil,
        dataManager: DataManagerProtocol? = nil
    ) {
        self._selectedNav = selectedNav
        self._metricsStore = State(initialValue: metricsStore ?? .shared)
        self._sourceUsageStore = State(initialValue: sourceUsageStore ?? .shared)
        self.dataManager = dataManager ?? DataManager.shared
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                    statsSection
                        .opacity(isLoaded ? 1 : 0)
                        .offset(y: isLoaded ? 0 : 12)
                        .animation(.easeOut(duration: 0.35).delay(0.05), value: isLoaded)

                    HStack(alignment: .top, spacing: DashboardTheme.Spacing.lg) {
                        activitySection
                            .frame(maxWidth: .infinity)
                            .opacity(isLoaded ? 1 : 0)
                            .offset(y: isLoaded ? 0 : 12)
                            .animation(.easeOut(duration: 0.35).delay(0.1), value: isLoaded)

                        sourcesSection
                            .frame(maxWidth: .infinity)
                            .opacity(isLoaded ? 1 : 0)
                            .offset(y: isLoaded ? 0 : 12)
                            .animation(.easeOut(duration: 0.35).delay(0.15), value: isLoaded)
                    }

                    recentSection
                        .opacity(isLoaded ? 1 : 0)
                        .offset(y: isLoaded ? 0 : 12)
                        .animation(.easeOut(duration: 0.35).delay(0.2), value: isLoaded)
                }
                .padding(.horizontal, DashboardTheme.Spacing.xl)
                .padding(.bottom, DashboardTheme.Spacing.xxl)
            }
        }
        .background(DashboardTheme.pageBg)
        .onAppear { loadDashboardData() }
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation { isLoaded = true }
        }
    }
}

// MARK: - Page Header
extension DashboardHomeView {
    var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Overview")
                .font(DashboardTheme.Fonts.serif(32, weight: .medium))
                .foregroundStyle(DashboardTheme.ink)
                .tracking(-0.5)

            Text(headerSubtitle)
                .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                .foregroundStyle(DashboardTheme.inkLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DashboardTheme.Spacing.xl)
        .padding(.top, DashboardTheme.Spacing.xl)
        .padding(.bottom, DashboardTheme.Spacing.lg)
    }

    var headerSubtitle: String {
        let activeDays = calculateActiveDays()
        let streak = calculateStreak()
        if activeDays == 0 { return "Start recording to see your stats" }
        var parts: [String] = ["Active for \(activeDays) day\(activeDays == 1 ? "" : "s") this month"]
        if streak > 0 { parts.append("\(streak)-day streak") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Stats — hero + supporting
extension DashboardHomeView {
    var statsSection: some View {
        HStack(spacing: 1) {
            // Hero — words this month + sparkline + delta
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
                statLabel("Words this month")

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(formatNumber(metricsStore.snapshot.totalWords))
                        .font(DashboardTheme.Fonts.serif(48, weight: .medium))
                        .monospacedDigit()
                        .tracking(-1.5)
                        .foregroundStyle(DashboardTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    deltaPill
                }

                MiniSparkline(
                    values: lastNDailyValues(14),
                    color: DashboardTheme.accent
                )
                .frame(height: 32)
                .frame(maxWidth: 280, alignment: .leading)
                // The sparkline is decorative; its data is already announced by
                // the number above it.
                .accessibilityHidden(true)
            }
            .padding(DashboardTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardTheme.cardBg)
            // C1: hero stat reads as one element rather than a number, a pill
            // and a chart announced separately.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Words this month")
            .accessibilityValue(formatNumber(metricsStore.snapshot.totalWords))

            // Sub-stat: time saved
            subStat(
                label: "Time saved",
                value: formatDuration(metricsStore.snapshot.estimatedTimeSaved),
                sub: "vs typing at 40 WPM"
            )

            // Sub-stat: avg WPM
            subStat(
                label: "Avg. speaking rate",
                value: formatDecimal(metricsStore.snapshot.wordsPerMinute),
                sub: "words per minute"
            )
        }
        .background(DashboardTheme.rule)
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                .stroke(DashboardTheme.rule, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
    }

    func subStat(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statLabel(label)
            Text(value)
                .font(DashboardTheme.Fonts.serif(28, weight: .medium))
                .monospacedDigit()
                .tracking(-0.5)
                .foregroundStyle(DashboardTheme.ink)
            Text(sub)
                .font(DashboardTheme.Fonts.sans(11, weight: .regular))
                .foregroundStyle(DashboardTheme.inkMuted)
        }
        .padding(DashboardTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardTheme.cardBg)
        // C1: read as one stat ("Time saved: 2 hours, vs typing at 40 WPM")
        // instead of three disconnected text fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value), \(sub)")
    }

    func statLabel(_ text: String) -> some View {
        Text(text)
            .font(DashboardTheme.Fonts.sans(10.5, weight: .semibold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(DashboardTheme.inkLight)
    }

    @ViewBuilder
    var deltaPill: some View {
        let pct = computeMonthDeltaPercent()
        if let pct = pct, abs(pct) >= 1 {
            HStack(spacing: 3) {
                Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(pct >= 0 ? "+" : "")\(pct)% vs last month")
                    .font(DashboardTheme.Fonts.sans(11, weight: .medium))
            }
            .foregroundStyle(pct >= 0 ? DashboardTheme.success : DashboardTheme.accentDeep)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Data loading
extension DashboardHomeView {
    func loadDashboardData() {
        Task {
            await metricsStore.bootstrapIfNeeded(dataManager: dataManager)
            let records = await dataManager.fetchAllRecordsQuietly()
            await MainActor.run {
                recentRecords = records
                providerStats = Self.computeProviderStats(from: records)
                dailyActivity = Self.mergeDailyActivity(
                    base: metricsStore.getDailyActivity(days: 28),
                    records: records
                )
            }
        }
    }

    /// Returns the last 28 daily word counts, oldest → newest. Missing days = 0.
    func last28DailyValues() -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var out: [Int] = []
        for offset in (0..<28).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                out.append(0); continue
            }
            out.append(dailyActivity[calendar.startOfDay(for: date)] ?? 0)
        }
        return out
    }

    func lastNDailyValues(_ count: Int) -> [Int] {
        Array(last28DailyValues().suffix(count))
    }

    func dailyAverageWords() -> Int {
        let vals = last28DailyValues()
        let active = vals.filter { $0 > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0, +) / active.count
    }

    func bestDay() -> (dateString: String, words: Int)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var best: (Date, Int)?
        for offset in 0..<28 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let words = dailyActivity[calendar.startOfDay(for: date)] ?? 0
            if best == nil || words > best!.1 { best = (date, words) }
        }
        guard let (date, words) = best, words > 0 else { return nil }
        return (Self.bestDayFormatter.string(from: date), words)
    }

    /// 4 axis labels evenly spaced across the 28-day window.
    func timelineAxisLabels() -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = Self.axisFormatter
        return [21, 14, 7].map { offset -> String in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return "" }
            return formatter.string(from: date)
        } + [formatter.string(from: today)]
    }

    func calculateStreak() -> Int { Self.computeStreak(from: dailyActivity) }

    func calculateActiveDays() -> Int { Self.computeActiveDays(from: dailyActivity) }

    /// % change vs the previous 28-day window. Nil if not enough data.
    func computeMonthDeltaPercent() -> Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var thisMonth = 0
        var lastMonth = 0
        for offset in 0..<28 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            thisMonth += dailyActivity[calendar.startOfDay(for: date)] ?? 0
        }
        for offset in 28..<56 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            lastMonth += dailyActivity[calendar.startOfDay(for: date)] ?? 0
        }
        guard lastMonth > 50 else { return nil }
        let delta = Double(thisMonth - lastMonth) / Double(lastMonth) * 100
        return Int(delta.rounded())
    }

    // NOTE (A4): the "openai" / "gemini" cases below are NOT dead code, despite
    // those providers having been removed from `TranscriptionProvider`.
    // `TranscriptionRecord.provider` is persisted as a raw String, so history
    // written by a pre-2.0 build still contains "openai" and "gemini". Dropping
    // these cases would render that history as "Openai" with a generic icon.
    // Keep them until a store migration rewrites or drops those records.
    func providerColor(for provider: String) -> Color {
        switch provider.lowercased() {
        case "openai":   return DashboardTheme.providerOpenAI
        case "gemini":   return DashboardTheme.providerGemini
        case "local":    return DashboardTheme.providerLocal
        case "parakeet": return DashboardTheme.providerParakeet
        default:         return DashboardTheme.inkMuted
        }
    }

    func providerDisplayName(for provider: String) -> String {
        switch provider.lowercased() {
        case "openai":   return "OpenAI"
        case "gemini":   return "Gemini"
        case "local":    return "Local Whisper"
        case "parakeet": return "Parakeet"
        default:         return provider.capitalized
        }
    }

    func formatNumber(_ value: Int) -> String { Self.numberString(value) }

    func formatDecimal(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    func formatDuration(_ interval: TimeInterval) -> String { Self.durationString(interval) }

    func formatTime(_ date: Date) -> String { Self.timeFormatter.string(from: date) }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "h:mm a"; return formatter
    }()

    static let axisFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "MMM d"; return formatter
    }()

    static let bestDayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "MMM d"; return formatter
    }()
}

// MARK: - Pure computations (shared by the view and its tests)
extension DashboardHomeView {
    static func providerIcon(for provider: String) -> String {
        switch provider.lowercased() {
        case "openai":   return "cloud"
        case "gemini":   return "sparkles"
        case "local":    return "laptopcomputer"
        case "parakeet": return "bird"
        default:         return "waveform"
        }
    }

    static func computeProviderStats(
        from records: [TranscriptionRecord]
    ) -> [ProviderStat] {
        var stats: [String: Int] = [:]
        for record in records { stats[record.provider, default: 0] += record.wordCount }
        return stats
            .map { ProviderStat(provider: $0.key, words: $0.value, icon: providerIcon(for: $0.key)) }
            .sorted { $0.words > $1.words }
    }

    static func mergeDailyActivity(
        base: [Date: Int],
        records: [TranscriptionRecord]
    ) -> [Date: Int] {
        var activity = base
        let calendar = Calendar.current
        for record in records {
            let day = calendar.startOfDay(for: record.date)
            if activity[day] == nil || activity[day] == 0 {
                activity[day, default: 0] += record.wordCount
            }
        }
        return activity
    }

    /// Consecutive days (ending today) with non-zero word counts.
    static func computeStreak(from activity: [Date: Int]) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var currentDate = Date()
        while true {
            let day = calendar.startOfDay(for: currentDate)
            if let words = activity[day], words > 0 {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
                currentDate = prev
            } else { break }
        }
        return streak
    }

    static func computeActiveDays(from activity: [Date: Int]) -> Int {
        activity.filter { $0.value > 0 }.count
    }

    static func numberString(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func durationString(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" } else { return "\(minutes)m" }
    }
}

// MARK: - Testable Helpers
extension DashboardHomeView {
    static func testableCalculateStreak(from activity: [Date: Int]) -> Int {
        computeStreak(from: activity)
    }

    static func testableCalculateActiveDays(from activity: [Date: Int]) -> Int {
        computeActiveDays(from: activity)
    }

    static func testableCalculateProviderStats(
        from records: [TranscriptionRecord]
    ) -> [ProviderStat] {
        computeProviderStats(from: records)
    }

    static func testableFormatDuration(_ interval: TimeInterval) -> String {
        durationString(interval)
    }
}

#Preview("Dashboard Home") {
    DashboardHomeView(selectedNav: .constant(.dashboard))
        .frame(width: 900, height: 700)
}
