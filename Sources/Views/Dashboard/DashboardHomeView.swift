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

internal struct DashboardHomeView: View {
    @Binding var selectedNav: DashboardNavItem
    @State private var metricsStore: UsageMetricsStore
    @State private var sourceUsageStore: SourceUsageStore
    @State private var recentRecords: [TranscriptionRecord] = []
    @State private var dailyActivity: [Date: Int] = [:]
    @State private var providerStats: [(provider: String, words: Int, icon: String)] = []
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
private extension DashboardHomeView {
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
private extension DashboardHomeView {
    var statsSection: some View {
        HStack(spacing: 1) {
            // Hero — words this month + sparkline + delta
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
                statLabel("Words this month")

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(formatNumber(metricsStore.snapshot.totalWords))
                        .font(DashboardTheme.Fonts.serif(52, weight: .medium))
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
            }
            .padding(DashboardTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardTheme.cardBg)

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

// MARK: - Activity — 28-day waveform timeline
private extension DashboardHomeView {
    var activitySection: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            sectionHeader("Activity", sub: "last 28 days")

            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
                ActivityTimeline(values: last28DailyValues(),
                                 accent: DashboardTheme.accent,
                                 ink: DashboardTheme.ink,
                                 rule: DashboardTheme.rule)
                    .frame(height: 84)

                axisLabels

                Divider().background(DashboardTheme.rule)

                HStack {
                    summaryStat(
                        label: "Best day",
                        valueView: bestDayLabel
                    )
                    Spacer()
                    summaryStat(
                        label: "Daily average",
                        valueView: AnyView(
                            Text("\(dailyAverageWords()) words")
                                .font(DashboardTheme.Fonts.serif(15, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(DashboardTheme.ink)
                        ),
                        alignment: .trailing
                    )
                }
            }
            .padding(DashboardTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                    .stroke(DashboardTheme.rule, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
        }
    }

    var axisLabels: some View {
        HStack {
            ForEach(timelineAxisLabels(), id: \.self) { label in
                Text(label)
                    .font(DashboardTheme.Fonts.sans(10, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkFaint)
                Spacer()
            }
            Text("this week")
                .font(DashboardTheme.Fonts.sans(10, weight: .semibold))
                .foregroundStyle(DashboardTheme.accent)
        }
        .padding(.horizontal, 4)
    }

    func summaryStat<V: View>(label: String, valueView: V, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            statLabel(label)
            valueView
        }
    }

    var bestDayLabel: AnyView {
        let best = bestDay()
        if let best = best {
            return AnyView(
                HStack(spacing: 4) {
                    Text(best.dateString)
                        .font(DashboardTheme.Fonts.serif(15, weight: .medium))
                        .foregroundStyle(DashboardTheme.ink)
                    Text("·")
                        .font(DashboardTheme.Fonts.serif(15, weight: .regular))
                        .foregroundStyle(DashboardTheme.inkFaint)
                    Text("\(best.words) words")
                        .font(DashboardTheme.Fonts.serif(15, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(DashboardTheme.accent)
                }
            )
        }
        return AnyView(
            Text("—")
                .font(DashboardTheme.Fonts.serif(15, weight: .medium))
                .foregroundStyle(DashboardTheme.inkMuted)
        )
    }
}

// MARK: - Sources — usage bars, no rank column
private extension DashboardHomeView {
    var sourcesSection: some View {
        let sourceStats = sourceUsageStore.topSources(limit: 5)
        let maxWords = max(1, sourceStats.map { $0.totalWords }.max() ?? 1)

        return VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            sectionHeader("Top sources", sub: nil)

            VStack(alignment: .leading, spacing: 0) {
                if sourceStats.isEmpty && providerStats.isEmpty {
                    emptySourcesView
                } else if !sourceStats.isEmpty {
                    ForEach(Array(sourceStats.enumerated()), id: \.element.id) { idx, stat in
                        sourceRow(stat, pct: Double(stat.totalWords) / Double(maxWords))
                        if idx < sourceStats.count - 1 {
                            Divider().background(DashboardTheme.ruleSoft)
                        }
                    }
                } else {
                    let maxProvider = max(1, providerStats.map { $0.words }.max() ?? 1)
                    ForEach(Array(providerStats.prefix(5).enumerated()), id: \.element.provider) { idx, stat in
                        providerRow(stat, pct: Double(stat.words) / Double(maxProvider))
                        if idx < min(providerStats.count, 5) - 1 {
                            Divider().background(DashboardTheme.ruleSoft)
                        }
                    }
                }
            }
            .background(DashboardTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                    .stroke(DashboardTheme.rule, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
        }
    }

    var emptySourcesView: some View {
        VStack(spacing: DashboardTheme.Spacing.sm) {
            Text("No sources yet")
                .font(DashboardTheme.Fonts.sans(13, weight: .medium))
                .foregroundStyle(DashboardTheme.inkLight)
            Text("Use AudioWhisper in different apps to see which ones you use most.")
                .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                .foregroundStyle(DashboardTheme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DashboardTheme.Spacing.xl)
        .padding(.horizontal, DashboardTheme.Spacing.md)
    }

    func sourceRow(_ stat: SourceUsageStats, pct: Double) -> some View {
        ZStack(alignment: .leading) {
            // Usage bar behind the row
            GeometryReader { geo in
                Rectangle()
                    .fill(DashboardTheme.accentSubtle)
                    .frame(width: geo.size.width * pct)
            }
            .allowsHitTesting(false)

            HStack(spacing: DashboardTheme.Spacing.md) {
                // App icon — bumped to 28pt
                Group {
                    if let image = stat.nsImage() {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DashboardTheme.rule)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(stat.initials.uppercased())
                                    .font(DashboardTheme.Fonts.sans(11, weight: .semibold))
                                    .foregroundStyle(DashboardTheme.inkMuted)
                            )
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)

                Text(stat.displayName)
                    .font(DashboardTheme.Fonts.sans(13, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(1)

                Spacer()

                Text(formatNumber(stat.totalWords))
                    .font(DashboardTheme.Fonts.mono(12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.inkLight)
            }
            .padding(.horizontal, DashboardTheme.Spacing.md)
            .padding(.vertical, DashboardTheme.Spacing.sm + 4)
        }
    }

    func providerRow(_ stat: (provider: String, words: Int, icon: String), pct: Double) -> some View {
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                Rectangle()
                    .fill(DashboardTheme.accentSubtle)
                    .frame(width: geo.size.width * pct)
            }
            .allowsHitTesting(false)

            HStack(spacing: DashboardTheme.Spacing.md) {
                Image(systemName: stat.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(providerColor(for: stat.provider))
                    .frame(width: 28, height: 28)

                Text(providerDisplayName(for: stat.provider))
                    .font(DashboardTheme.Fonts.sans(13, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)

                Spacer()

                Text(formatNumber(stat.words))
                    .font(DashboardTheme.Fonts.mono(12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DashboardTheme.inkLight)
            }
            .padding(.horizontal, DashboardTheme.Spacing.md)
            .padding(.vertical, DashboardTheme.Spacing.sm + 4)
        }
    }
}

// MARK: - Recent (mostly unchanged, with refined radius)
private extension DashboardHomeView {
    var recentSection: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("Recent transcripts", sub: nil)
                Spacer()
                if !recentRecords.isEmpty {
                    Button {
                        selectedNav = .transcripts
                    } label: {
                        HStack(spacing: 3) {
                            Text("View all")
                                .font(DashboardTheme.Fonts.sans(12, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(DashboardTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if recentRecords.isEmpty {
                emptyRecentView
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recentRecords.prefix(5).enumerated()), id: \.element.id) { index, record in
                        transcriptRow(record)
                        if index < min(recentRecords.count, 5) - 1 {
                            Divider().background(DashboardTheme.ruleSoft).padding(.leading, 80)
                        }
                    }
                }
                .background(DashboardTheme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                        .stroke(DashboardTheme.rule, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
            }
        }
    }

    var emptyRecentView: some View {
        VStack(spacing: DashboardTheme.Spacing.md) {
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DashboardTheme.inkFaint)
            VStack(spacing: 2) {
                Text("No transcripts yet")
                    .font(DashboardTheme.Fonts.sans(14, weight: .medium))
                    .foregroundStyle(DashboardTheme.inkLight)
                Text("Press your hotkey to start recording")
                    .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DashboardTheme.Spacing.xxl)
        .background(DashboardTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.md)
                .stroke(DashboardTheme.rule, lineWidth: 0.5)
        )
    }

    func transcriptRow(_ record: TranscriptionRecord) -> some View {
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
            Text(formatTime(record.date))
                .font(DashboardTheme.Fonts.mono(11, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(DashboardTheme.inkMuted)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    if let iconData = record.sourceAppIconData,
                       let nsImage = NSImage(data: iconData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    Text(record.sourceAppName ?? record.provider)
                        .font(DashboardTheme.Fonts.sans(11, weight: .medium))
                        .foregroundStyle(DashboardTheme.inkLight)
                }

                Text(record.text)
                    .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                    .foregroundStyle(DashboardTheme.ink)
                    .lineLimit(2)
                    .lineSpacing(2)
            }

            Spacer(minLength: DashboardTheme.Spacing.md)

            Text("\(record.wordCount)w")
                .font(DashboardTheme.Fonts.mono(11, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(DashboardTheme.inkFaint)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, DashboardTheme.Spacing.md)
    }
}

// MARK: - Section header
private extension DashboardHomeView {
    func sectionHeader(_ title: String, sub: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(DashboardTheme.Fonts.sans(11, weight: .semibold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(DashboardTheme.inkLight)

            if let sub = sub {
                Text(sub)
                    .font(DashboardTheme.Fonts.sans(11, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
            }
        }
    }
}

// MARK: - Activity timeline (the bar histogram)

internal struct ActivityTimeline: View {
    let values: [Int]          // 28 daily word counts, oldest → newest
    let accent: Color
    let ink: Color
    let rule: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = max(1, values.max() ?? 1)
            let count = max(1, values.count)
            let gap: CGFloat = 4
            let totalGap = gap * CGFloat(count - 1)
            let barW = max(2, (geo.size.width - totalGap) / CGFloat(count))

            HStack(alignment: .center, spacing: gap) {
                ForEach(values.indices, id: \.self) { i in
                    let v = values[i]
                    let isThisWeek = i >= values.count - 7
                    let normalized = max(2.0, CGFloat(v) / CGFloat(maxV) * (geo.size.height - 6))

                    RoundedRectangle(cornerRadius: barW / 2)
                        .fill(v == 0 ? rule : (isThisWeek ? accent : ink.opacity(0.78)))
                        .frame(width: barW, height: normalized)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - MiniSparkline
internal struct MiniSparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            guard values.count >= 2 else {
                return AnyView(EmptyView())
            }
            let maxV = max(1, values.max() ?? 1)
            let step = geo.size.width / CGFloat(values.count - 1)
            let path = Path { p in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height - (CGFloat(v) / CGFloat(maxV)) * (geo.size.height - 4) - 2
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else      { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            let lastIdx = values.count - 1
            let lastY = geo.size.height - (CGFloat(values[lastIdx]) / CGFloat(maxV)) * (geo.size.height - 4) - 2
            let lastX = CGFloat(lastIdx) * step

            return AnyView(
                ZStack(alignment: .topLeading) {
                    path
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .offset(x: lastX - 3, y: lastY - 3)
                }
            )
        }
    }
}

// MARK: - Data loading
private extension DashboardHomeView {
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

    func lastNDailyValues(_ n: Int) -> [Int] {
        Array(last28DailyValues().suffix(n))
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
    ) -> [(provider: String, words: Int, icon: String)] {
        var stats: [String: Int] = [:]
        for record in records { stats[record.provider, default: 0] += record.wordCount }
        return stats
            .map { (provider: $0.key, words: $0.value, icon: providerIcon(for: $0.key)) }
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
    ) -> [(provider: String, words: Int, icon: String)] {
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
