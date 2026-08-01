import SwiftUI

internal struct MLXModelManagementView: View {
    @Environment(MLXModelManager.self) private var modelManager
    @Binding var selectedModelRepo: String
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                Text("MLX Models")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                if modelManager.totalCacheSize > 0 {
                    Text(modelManager.formatBytes(modelManager.totalCacheSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Button(action: {
                    isRefreshing = true
                    Task {
                        await modelManager.refreshModelList()
                        await MainActor.run {
                            isRefreshing = false
                        }
                    }
                }, label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                })
                .buttonStyle(.plain)
                // C1: icon-only, so it announced as an unlabelled button.
                .accessibilityLabel(isRefreshing ? "Refreshing model list" : "Refresh model list")
                .disabled(isRefreshing)
                .help("Refresh model list to check downloaded models")
            }

            if selectedModelRepo.isEmpty || !modelManager.downloadedModels.contains(selectedModelRepo) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No MLX model installed — choose one below to download.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Model List (shared row UI using adapters)
            VStack(spacing: 8) {
                let entries: [ModelEntry] = MLXModelManager.recommendedModels.map { model in
                    let startDownload = {
                        Task { @MainActor in
                            modelManager.isDownloading[model.repo] = true
                            modelManager.downloadProgress[model.repo] = "Starting download..."
                        }
                        Task { await modelManager.downloadModel(model.repo) }
                    }

                    return MLXEntry(
                        model: model,
                        isDownloaded: modelManager.downloadedModels.contains(model.repo),
                        isDownloading: modelManager.isDownloading[model.repo] ?? false,
                        statusText: modelManager.downloadProgress[model.repo],
                        sizeText: (modelManager.modelSizes[model.repo]).map(modelManager.formatBytes) ?? model.estimatedSize,
                        isSelected: selectedModelRepo == model.repo,
                        badgeText: isRecommended(model.repo) ? "RECOMMENDED" : nil,
                        onSelect: {
                            selectedModelRepo = model.repo
                            if !modelManager.downloadedModels.contains(model.repo) {
                                startDownload()
                            }
                        },
                        onDownload: startDownload,
                        onDelete: {
                            Task {
                                await modelManager.deleteModel(model.repo)
                                if selectedModelRepo == model.repo {
                                    // Prefer another already-downloaded model. If none is
                                    // available, leave the selection empty so the "no MLX
                                    // model installed" badge above the list is visible.
                                    selectedModelRepo = modelManager.nextSelectionAfterDeletion(deletedRepo: model.repo) ?? ""
                                }
                            }
                        }
                    )
                }
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    UnifiedModelRow(
                        title: entry.title,
                        subtitle: entry.subtitle,
                        sizeText: entry.sizeText,
                        statusText: entry.statusText,
                        statusColor: entry.statusColor,
                        isDownloaded: entry.isDownloaded,
                        isDownloading: entry.isDownloading,
                        isSelected: entry.isSelected,
                        badgeText: entry.badgeText,
                        onSelect: entry.onSelect,
                        onDownload: entry.onDownload,
                        onDelete: entry.onDelete
                    )
                }
            }

            // Info text with clickable path
            VStack(alignment: .leading, spacing: 4) {
                Text("Models are stored in:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("~/.cache/huggingface/hub/")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)

                    Button(action: {
                        let path = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent(".cache/huggingface/hub")
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                    }, label: {
                        Image(systemName: "folder")
                            .font(.caption2)
                    })
                    .buttonStyle(.plain)
                    .help("Open in Finder")
                    // C1: `.help` is a mouse tooltip — VoiceOver does not read
                    // it, so the button still needed an explicit label.
                    .accessibilityLabel("Show models in Finder")
                }
            }
        }
    }

    private func isRecommended(_ repo: String) -> Bool {
        // B1: this badged Llama-3.2-1B while DashboardCorrectionView badged
        // Qwen3-1.7B — two screens telling the user different things. Both now
        // read the one constant that the correction pipeline also uses.
        return repo == AppDefaults.defaultSemanticCorrectionModelRepo
    }
}
