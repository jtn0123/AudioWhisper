import AppKit
import SwiftUI
import os.log
import UniformTypeIdentifiers

// MARK: - AppDelegate+Menu (refined)
//
// Builds the status menu with:
//   1. Branded header (AW mark + provider + today's WPM)
//   2. Standard actions with visible keyboard shortcuts
//   3. Inline "Recent" preview (up to 3 transcripts, click to copy)
//   4. Dashboard / Help / Quit
//
// The header + recent rows are SwiftUI views hosted via NSHostingView and
// attached to NSMenuItem.view. The menu re-populates each time it opens
// (via NSMenuDelegate) so the Recent section stays current.

internal extension AppDelegate {

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        populateStatusMenu(menu)
        return menu
    }

    /// Rebuilds the menu's items. Called on creation and before each open.
    func populateStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // ── Header
        menu.addItem(makeHeaderItem())
        menu.addItem(.separator())

        // ── Primary actions
        menu.addItem(makeActionItem(
            title: "Start Recording",
            selector: #selector(toggleRecordWindow),
            keyEquivalent: " ",
            modifiers: [.command, .shift]
        ))
        menu.addItem(makeActionItem(
            title: "Transcribe a File…",
            selector: #selector(transcribeAudioFile),
            keyEquivalent: ""
        ))

        menu.addItem(.separator())

        // ── Recent transcripts (inline)
        let recent = recentTranscriptsForMenu()
        if !recent.isEmpty {
            menu.addItem(makeSectionLabelItem("Recent"))
            for record in recent.prefix(3) {
                menu.addItem(makeRecentItem(record: record))
            }
            menu.addItem(.separator())
        }

        // ── Dashboard / Help / Quit
        menu.addItem(makeActionItem(
            title: "Dashboard",
            selector: #selector(showDashboard),
            keyEquivalent: ",",
            modifiers: [.command]
        ))
        menu.addItem(makeActionItem(
            title: "Help",
            selector: #selector(showHelp),
            keyEquivalent: ""
        ))

        menu.addItem(.separator())

        menu.addItem(makeActionItem(
            title: "Quit AudioWhisper",
            selector: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            modifiers: [.command]
        ))
    }

    // MARK: - Recent transcripts

    /// Up to 3 most-recent transcripts for the menu preview. Reads a cached
    /// snapshot — the menu omits the Recent section if the cache is empty.
    private func recentTranscriptsForMenu() -> [TranscriptionRecord] {
        DashboardWindowManager.shared.cachedRecentRecords(limit: 3)
    }

    // MARK: - Custom menu items

    private func makeHeaderItem() -> NSMenuItem {
        let item = NSMenuItem()
        let providerRaw = UserDefaults.standard.string(forKey: "transcriptionProvider") ?? "parakeet"
        let wpm = Int(UsageMetricsStore.shared.snapshot.wordsPerMinute.rounded())

        let host = NSHostingView(rootView: MenuHeaderView(
            providerRaw: providerRaw,
            todayWPM: wpm > 0 ? wpm : nil
        ))
        host.frame = NSRect(x: 0, y: 0, width: menuWidth, height: 44)
        item.view = host
        item.isEnabled = false
        return item
    }

    private func makeSectionLabelItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        let host = NSHostingView(rootView: MenuSectionLabel(text: text))
        host.frame = NSRect(x: 0, y: 0, width: menuWidth, height: 22)
        item.view = host
        item.isEnabled = false
        return item
    }

    private func makeRecentItem(record: TranscriptionRecord) -> NSMenuItem {
        let item = NSMenuItem(
            title: record.text,  // Fallback for VoiceOver
            action: #selector(copyRecentTranscript(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = record

        let host = NSHostingView(rootView: RecentTranscriptMenuRow(
            timeString: Self.menuTimeFormatter.string(from: record.date),
            text: record.text
        ))
        host.frame = NSRect(x: 0, y: 0, width: menuWidth, height: 26)
        item.view = host
        return item
    }

    private func makeActionItem(
        title: String,
        selector: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        if !modifiers.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private var menuWidth: CGFloat { 300 }

    private static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    // MARK: - Actions

    /// Copies a recent transcript's text to the clipboard when clicked.
    @MainActor @objc func copyRecentTranscript(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? TranscriptionRecord else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.text, forType: .string)
        Logger.app.info("Copied recent transcript to clipboard")
    }

    @MainActor @objc func showHistory() {
        Logger.app.info("History menu item selected")
        HistoryWindowManager.shared.showHistoryWindow()
    }

    @MainActor @objc func showDashboard() {
        Logger.app.info("Dashboard menu item selected")
        DashboardWindowManager.shared.showDashboardWindow()
    }

    @objc func showHelp() {
        let shouldOpenSettings = WelcomeWindow.showWelcomeDialog()
        if shouldOpenSettings {
            DashboardWindowManager.shared.showDashboardWindow()
        }
    }

    @objc func transcribeAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .mpeg4Audio,
            .mp3,
            .wav,
            .aiff,
            .init(filenameExtension: "m4a") ?? .mpeg4Audio,
            .init(filenameExtension: "aac") ?? .mpeg4Audio,
            .init(filenameExtension: "flac") ?? .audio,
            .init(filenameExtension: "caf") ?? .audio
        ]
        panel.message = "Select an audio file to transcribe"
        panel.prompt = "Transcribe"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.processAudioFile(url)
        }
    }

    private func processAudioFile(_ url: URL) {
        if recordingWindow == nil {
            createRecordingWindow()
        }
        guard let window = recordingWindow else { return }
        if !window.isVisible {
            windowController.toggleRecordWindow(window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .transcribeAudioFile, object: url)
        }
    }

    @objc func screenConfigurationChanged() {
        AppSetupHelper.resetIconSizeCache()
        // Re-render the icon at the new size, preserving the current state.
        iconRenderer?.refresh()
    }
}

// MARK: - NSMenuDelegate
// Re-populate the menu before each open so the Recent section reflects the
// latest transcripts, and refresh the cache for the next open.

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        populateStatusMenu(menu)
        Task { await DashboardWindowManager.shared.refreshRecentRecordsCache() }
    }
}
