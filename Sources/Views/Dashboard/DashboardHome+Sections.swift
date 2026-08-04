import SwiftUI
import AppKit

// MARK: - Activity — 28-day waveform timeline
extension DashboardHomeView {
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
extension DashboardHomeView {
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

    func providerRow(_ stat: ProviderStat, pct: Double) -> some View {
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
extension DashboardHomeView {
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
extension DashboardHomeView {
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
