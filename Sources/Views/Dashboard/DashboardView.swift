import SwiftUI
import SwiftData
import AppKit

// MARK: - DashboardTheme (refined)
//
// What changed vs the previous version:
// 1. Dropped the blue gradient sidebar. Sidebar is now drawn with
//    NSVisualEffectView material `.sidebar` — the standard macOS treatment
//    used by Finder, Mail, Settings. Lets the recording window stay the
//    brand moment.
// 2. Accent moved from system blue to the app's coral (#D9734D, matching
//    the recording-window coral so the two surfaces feel related).
// 3. `Fonts.serif` now actually uses `.serif` design (New York). Used for
//    page titles and large numerals. SF stays for body / UI.
// 4. Radius scale fixed: cards are 10pt (was 2 — basically square), pills
//    stay at 6, the window itself is 12. Three steps, no surprises.
// 5. All `tabular` numerals where numbers stack — stats grid, mono labels.

internal enum DashboardTheme {
    // App-wide warm coral accent (matches recording window)
    static let accent       = Color(red: 0.85, green: 0.45, blue: 0.30)
    static let accentDeep   = Color(red: 0.70, green: 0.34, blue: 0.23)
    static let accentLight  = Color(red: 0.85, green: 0.45, blue: 0.30).opacity(0.12)
    static let accentSubtle = Color(red: 0.85, green: 0.45, blue: 0.30).opacity(0.06)

    // Sidebar — drawn via NSVisualEffectView .sidebar material.
    // These tokens are kept for hover/active states inside the sidebar.
    static let sidebarText       = Color(nsColor: .labelColor)
    static let sidebarTextMuted  = Color(nsColor: .secondaryLabelColor)
    static let sidebarTextFaint  = Color(nsColor: .tertiaryLabelColor)
    static let sidebarDivider    = Color(nsColor: .separatorColor)
    static let sidebarHover      = Color.black.opacity(0.04)
    static let sidebarActive     = Color.black.opacity(0.07)

    // Main content — native macOS surfaces
    static let pageBg   = Color(nsColor: .windowBackgroundColor)
    static let cardBg   = Color(nsColor: .controlBackgroundColor)
    static let cardBgAlt = Color(nsColor: .controlBackgroundColor).opacity(0.8)

    // Text
    static let ink       = Color(nsColor: .labelColor)
    static let inkLight  = Color(nsColor: .secondaryLabelColor)
    static let inkMuted  = Color(nsColor: .tertiaryLabelColor)
    static let inkFaint  = Color(nsColor: .quaternaryLabelColor)

    // Borders & dividers
    static let rule     = Color(nsColor: .separatorColor)
    static let ruleSoft = Color(nsColor: .separatorColor).opacity(0.5)
    static let ruleBold = Color(nsColor: .gridColor)

    // Provider colors (kept; tuned slightly off the coral accent)
    static let providerOpenAI   = Color(red: 0.45, green: 0.55, blue: 0.50)
    static let providerGemini   = Color(red: 0.50, green: 0.52, blue: 0.65)
    static let providerLocal    = Color(red: 0.55, green: 0.48, blue: 0.58)
    static let providerParakeet = accent

    // Activity heatmap (kept for any code that still references it; the
    // refined Overview uses a continuous timeline, but settings/empty-states
    // may still want these).
    static let heatmapEmpty  = Color(nsColor: .separatorColor)
    static let heatmapLow    = accent.opacity(0.25)
    static let heatmapMedium = accent.opacity(0.45)
    static let heatmapHigh   = accent.opacity(0.70)
    static let heatmapMax    = accent

    // Semantic colors — adaptive to light/dark
    static let success     = Color(red: 0.45, green: 0.75, blue: 0.55)
    static let destructive = Color(nsColor: .systemRed)

    // MARK: - Typography
    enum Fonts {
        /// Editorial serif (New York). For page titles, stat numerals.
        static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        /// Sans for body / UI (SF Pro).
        static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        /// Monospace for data — times, word counts, IDs.
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    // MARK: - Spacing (8pt base)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radius (three-step scale)
    enum Radius {
        static let xs: CGFloat = 4   // chips
        static let sm: CGFloat = 6   // buttons, inline pills
        static let md: CGFloat = 10  // cards (was 2 — too tight)
        static let lg: CGFloat = 12  // windows
    }

    // Animation timings used across the dashboard
    enum Animation {
        /// Stagger delay between consecutive sections when entering. Index 0 = no delay.
        static func stagger(_ index: Int) -> Double {
            Double(index) * 0.05
        }
        /// Standard durations used across the dashboard.
        static let quick: Double = 0.15
        static let standard: Double = 0.3
    }
}

// MARK: - SidebarVisualEffect
// NSVisualEffectView wrapper — gives us the standard translucent sidebar
// material instead of a flat blue gradient.

internal struct SidebarVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Navigation Item

internal enum DashboardNavItem: String, CaseIterable, Identifiable {
    case dashboard = "Overview"
    case transcripts = "Transcripts"
    case categories = "Categories"
    case recording = "Input"
    case providers = "Models"
    case visuals = "Visuals"
    case preferences = "General"
    case permissions = "Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard:   return "square.text.square"
        case .transcripts: return "doc.text"
        case .categories:  return "folder"
        case .recording:   return "mic.fill"
        case .providers:   return "cpu"
        case .visuals:     return "paintpalette"
        case .preferences: return "gearshape"
        case .permissions: return "lock"
        }
    }
}

// MARK: - Main Dashboard View

internal struct DashboardView: View {
    @State private var selectedNav: DashboardNavItem = .dashboard
    @State private var metricsStore = UsageMetricsStore.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().frame(width: 0.5).overlay(DashboardTheme.rule)
            mainContent
        }
        .background(DashboardTheme.pageBg)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            SidebarVisualEffect()
                .edgesIgnoringSafeArea(.all)

            VStack(alignment: .leading, spacing: 0) {
                // Masthead — small coral mark + app name + tagline
                masthead
                    .padding(.horizontal, DashboardTheme.Spacing.md)
                    .padding(.top, DashboardTheme.Spacing.lg + 28) // leave room for traffic lights
                    .padding(.bottom, DashboardTheme.Spacing.lg)

                // Navigation
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
                    navSection(items: [.dashboard, .transcripts, .categories])
                    sectionDivider("Settings")
                    navSection(items: [.recording, .providers, .visuals, .preferences, .permissions])
                }
                .padding(.horizontal, DashboardTheme.Spacing.sm)

                Spacer()

                if metricsStore.snapshot.totalSessions > 0 {
                    statsFooter
                }
            }
        }
        .frame(width: LayoutMetrics.DashboardWindow.sidebarWidth)
    }

    private var masthead: some View {
        HStack(spacing: 10) {
            // Small coral mark — gradient + inset highlight so it reads as a
            // real "app icon" at this size, not a flat color blob.
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [DashboardTheme.accent, DashboardTheme.accentDeep],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)

                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("AudioWhisper")
                    .font(DashboardTheme.Fonts.sans(13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.sidebarText)
                Text("Voice to text")
                    .font(DashboardTheme.Fonts.sans(10.5, weight: .regular))
                    .foregroundStyle(DashboardTheme.sidebarTextMuted)
            }
        }
    }

    private func navSection(items: [DashboardNavItem]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(items, id: \.id) { item in navButton(item) }
        }
    }

    private func sectionDivider(_ label: String) -> some View {
        Text(label)
            .font(DashboardTheme.Fonts.sans(10, weight: .semibold))
            .foregroundStyle(DashboardTheme.sidebarTextFaint)
            .tracking(0.6)
            .textCase(.uppercase)
            .padding(.horizontal, DashboardTheme.Spacing.sm)
            .padding(.top, DashboardTheme.Spacing.sm)
            .padding(.bottom, 4)
    }

    private func navButton(_ item: DashboardNavItem) -> some View {
        let isActive = selectedNav == item
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedNav = item }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 16)
                    .foregroundStyle(isActive ? DashboardTheme.accent : DashboardTheme.sidebarTextMuted)

                Text(item.rawValue)
                    .font(DashboardTheme.Fonts.sans(13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(DashboardTheme.sidebarText)

                Spacer()
            }
            .padding(.horizontal, DashboardTheme.Spacing.sm)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.Radius.sm)
                    .fill(isActive ? DashboardTheme.sidebarActive : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statsFooter: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xs) {
            Rectangle()
                .fill(DashboardTheme.sidebarDivider)
                .frame(height: 0.5)
                .padding(.horizontal, DashboardTheme.Spacing.md)

            VStack(alignment: .leading, spacing: 2) {
                Text("Total recorded")
                    .font(DashboardTheme.Fonts.sans(10, weight: .semibold))
                    .foregroundStyle(DashboardTheme.sidebarTextFaint)
                    .tracking(0.6)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatNumber(metricsStore.snapshot.totalWords))
                        .font(DashboardTheme.Fonts.serif(22, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(DashboardTheme.sidebarText)

                    Text("words")
                        .font(DashboardTheme.Fonts.sans(11, weight: .regular))
                        .foregroundStyle(DashboardTheme.sidebarTextMuted)
                }
            }
            .padding(.horizontal, DashboardTheme.Spacing.md)
            .padding(.vertical, DashboardTheme.Spacing.md)
        }
    }

    // MARK: - Content switcher

    @ViewBuilder
    private var mainContent: some View {
        switch selectedNav {
        case .dashboard:   DashboardHomeView(selectedNav: $selectedNav)
        case .transcripts: DashboardTranscriptsView()
        case .categories:  DashboardCategoriesView()
        case .recording:   DashboardRecordingView()
        case .providers:   DashboardProvidersView()
        case .visuals:     DashboardVisualsView()
        case .preferences: DashboardPreferencesView()
        case .permissions: DashboardPermissionsView()
        }
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Preview
#Preview("Dashboard") {
    DashboardView()
        .frame(width: LayoutMetrics.DashboardWindow.previewSize.width,
               height: LayoutMetrics.DashboardWindow.previewSize.height)
}
