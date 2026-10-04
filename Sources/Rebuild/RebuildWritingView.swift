import AppKit
import SwiftUI

struct RebuildWritingView: View {
    let session: RebuildSession
    @AppDefault(\.semanticCorrectionMode) private var mode
    @AppDefault(\.semanticCorrectionModelRepo) private var model
    @State private var selectedCategory: CategoryDefinition?
    @State private var newCategory = false
    @State private var installing = false
    @State private var status: String?
    @State private var mappingApp = ""
    @State private var mappingCategory = "general"
    @State private var deletingCategory: CategoryDefinition?
    @State private var confirmCategoryDelete = false
    @State private var confirmModelDelete = false
    @State private var verifying = false
    @State private var apps: [NSRunningApplication] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RebuildPageHeading(
                    title: "Sound like yourself.",
                    subtitle:
                        "Optional local cleanup that understands where you’re writing. "
                        + "The original transcript survives if cleanup fails."
                )
                RebuildSection(title: "LOCAL WRITING CLEANUP") {
                    Picker("Correction model", selection: $model) {
                        ForEach(MLXModelManager.recommendedModels) {
                            Text("\($0.displayName) · \($0.estimatedSize)").tag($0.repo)
                        }
                    }.disabled(installing || verifying || !Arch.isAppleSilicon)
                    Toggle(
                        "Clean up grammar, punctuation and filler words",
                        isOn: Binding(
                            get: { mode == .localMLX }, set: { mode = $0 ? .localMLX : .off }
                        )
                    ).disabled(!Arch.isAppleSilicon || !MLXModelManager.shared.isModelCachedOnDisk(repo: model))
                    HStack {
                        Text(
                            MLXModelManager.shared.isModelCachedOnDisk(repo: model)
                                ? "Correction model installed" : "Install the selected model to enable cleanup"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(installing ? "Installing…" : "Install correction model") {
                            Task {
                                guard !session.phase.isBusy, !session.isInstalling,
                                    !session.maintenanceInProgress
                                else { return }
                                installing = true
                                session.maintenanceInProgress = true
                                defer {
                                    installing = false
                                    session.maintenanceInProgress = false
                                }
                                status = nil
                                let selected = model
                                do {
                                    _ = try await UvBootstrap.ensureVenv()
                                    await MLXModelManager.shared.downloadModel(selected)
                                    status =
                                        MLXModelManager.shared.isModelCachedOnDisk(repo: selected)
                                        ? "Installed. You can enable cleanup now."
                                        : "Installation did not complete. Check your connection and retry."
                                } catch { status = error.localizedDescription }
                                installing = false
                            }
                        }.disabled(installing || verifying || !Arch.isAppleSilicon)
                    }
                    if MLXModelManager.shared.isModelCachedOnDisk(repo: model) {
                        HStack {
                            Button(verifying ? "Verifying…" : "Verify correction model") {
                                Task { await verifyModel() }
                            }
                            .disabled(installing || verifying)
                            Button("Remove correction model", role: .destructive) { confirmModelDelete = true }
                                .disabled(installing || verifying)
                        }
                    }
                    if !Arch.isAppleSilicon {
                        Text("Local writing cleanup requires Apple Silicon.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let status { Text(status).font(.caption).textSelection(.enabled) }
                }
                RebuildSection(title: "WRITING PROFILES") {
                    ForEach(CategoryStore.shared.categories) { category in
                        HStack(spacing: 12) {
                            Image(systemName: category.icon).foregroundStyle(category.color).frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.displayName).font(.headline)
                                Text(category.promptDescription).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { selectedCategory = category }
                            if !category.isSystem {
                                Button("Delete", role: .destructive) {
                                    deletingCategory = category
                                    confirmCategoryDelete = true
                                }
                            }
                        }
                        Divider()
                    }
                    Button("New profile") { newCategory = true }
                }
                RebuildSection(title: "APP-AWARE WRITING") {
                    Picker("Application", selection: $mappingApp) {
                        Text("Choose a running app").tag("")
                        ForEach(apps, id: \.processIdentifier) { app in
                            Text(app.localizedName ?? app.bundleIdentifier ?? "Application").tag(
                                app.bundleIdentifier ?? "")
                        }
                    }
                    Picker("Profile", selection: $mappingCategory) {
                        ForEach(CategoryStore.shared.categories) { Text($0.displayName).tag($0.id) }
                    }
                    Button("Assign profile") {
                        AppCategoryManager.shared.setCategory(id: mappingCategory, for: mappingApp)
                    }.disabled(mappingApp.isEmpty)
                    ForEach(AppCategoryManager.shared.userMappings.keys.sorted(), id: \.self) { id in
                        HStack {
                            Text(id).font(.caption)
                            Spacer()
                            Text(
                                CategoryStore.shared.category(
                                    withId: AppCategoryManager.shared.userMappings[id] ?? "general"
                                ).displayName)
                            Button("Reset") { AppCategoryManager.shared.resetToDefault(for: id) }
                        }
                    }
                }
            }.padding(36)
        }
        .disabled(session.phase.isBusy)
        .task {
            apps = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier != nil && $0.activationPolicy == .regular
            }
        }
        .onChange(of: model) { _, selected in
            status = nil
            if !MLXModelManager.shared.isModelCachedOnDisk(repo: selected) { mode = .off }
        }
        .confirmationDialog("Delete this writing profile?", isPresented: $confirmCategoryDelete) {
            Button("Delete profile", role: .destructive) {
                guard let category = deletingCategory else { return }
                for (app, id) in AppCategoryManager.shared.userMappings where id == category.id {
                    AppCategoryManager.shared.resetToDefault(for: app)
                }
                CategoryStore.shared.delete(category)
                deletingCategory = nil
            }
        }
        .confirmationDialog("Remove these shared correction weights?", isPresented: $confirmModelDelete) {
            Button("Remove model", role: .destructive) {
                let selected = model
                Task {
                    guard !session.phase.isBusy, !session.isInstalling,
                        !session.maintenanceInProgress
                    else { return }
                    installing = true
                    session.maintenanceInProgress = true
                    defer {
                        installing = false
                        session.maintenanceInProgress = false
                    }
                    mode = .off
                    await MLXModelManager.shared.deleteModel(selected)
                    status =
                        MLXModelManager.shared.isModelCachedOnDisk(repo: selected)
                        ? "Removal failed. The model is still on disk." : "Correction model removed."
                }
            }
        }
        .sheet(item: $selectedCategory) { category in RebuildProfileEditor(category: category) }
        .sheet(isPresented: $newCategory) {
            RebuildProfileEditor(
                category: CategoryDefinition(
                    id: UUID().uuidString.lowercased(), displayName: "New profile", icon: "pencil",
                    colorHex: "#B34529", promptDescription: "Custom writing style", promptTemplate: "", isSystem: false
                ))
        }
    }

    private func verifyModel() async {
        guard !session.phase.isBusy, !session.isInstalling, !session.maintenanceInProgress else { return }
        verifying = true
        session.maintenanceInProgress = true
        status = nil
        let selected = model
        defer {
            verifying = false
            session.maintenanceInProgress = false
        }
        do {
            let python = try await UvBootstrap.ensureVenv()
            let result = try await ModelVerificationService.verify(
                scriptName: "verify_mlx", arguments: [selected] + ModelPins.scriptArguments(for: selected),
                pythonPath: python.path, successFallback: "Correction model is ready")
            status = result.message
        } catch { status = error.localizedDescription }
    }

}

struct RebuildProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var category: CategoryDefinition
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Writing profile").font(.system(size: 26, design: .serif))
            TextField("Name", text: $category.displayName).textFieldStyle(.roundedBorder)
            TextField("Short description", text: $category.promptDescription).textFieldStyle(.roundedBorder)
            Text("Instructions for local cleanup").font(.headline)
            TextEditor(text: $category.promptTemplate).frame(height: 220).border(.secondary.opacity(0.2))
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save profile") {
                    CategoryStore.shared.upsert(category)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(category.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(30).frame(width: 560)
    }
}
