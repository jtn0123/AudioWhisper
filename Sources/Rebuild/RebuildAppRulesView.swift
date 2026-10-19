import AppKit
import SwiftUI

@MainActor
struct RebuildAppRulesView: View {
    let session: RebuildSession?
    @AppDefault(\.appDictationRules) private var rules
    @AppDefault(\.savedDictationModes) private var modes
    @State private var error: String?
    private var locked: Bool { session?.phase.isBusy == true || session?.maintenanceInProgress == true }

    var body: some View {
        RebuildSection(title: "App rules", caption: "Choose Automatic in the mode picker to use these rules. "
                       + "A manual mode stays selected until you choose Automatic again.") {
            ForEach(rules) { rule in
                HStack {
                    Toggle(rule.appName, isOn: Binding(get: { rule.enabled }, set: { value in
                        guard !locked, let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
                        rules[index].enabled = value
                    })).frame(maxWidth: 220, alignment: .leading)
                    Picker("Mode for \(rule.appName)", selection: Binding(get: { rule.modeID }, set: { id in
                        guard !locked, let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
                        rules[index].modeID = id
                    })) {
                        if !modes.contains(where: { $0.id == rule.modeID }) {
                            Text("Mode removed · using current settings").tag(rule.modeID)
                        }
                        ForEach(modes) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                    Button("Remove") { rules.removeAll { $0.id == rule.id } }
                        .accessibilityLabel("Remove rule for \(rule.appName)")
                }
            }
            Button("Add app…", action: chooseApp).disabled(modes.isEmpty || rules.count >= 64)
            if modes.isEmpty { Text("Save a dictation mode first.").font(.caption).foregroundStyle(.secondary) }
            if let error { RebuildCallout(tone: .error, message: error) }
        }.disabled(locked)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, !locked, let url = panel.url, let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier, let mode = modes.first, rules.count < 64 else { return }
            guard !rules.contains(where: { $0.bundleIdentifier == id }) else {
                error = "This app already has a rule. Change its mode above."
                return
            }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            rules.append(AppDictationRule(bundleIdentifier: id, appName: name, modeID: mode.id))
        }
    }
}
