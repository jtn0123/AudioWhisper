import Foundation
import WhisperKit
import UserNotifications
import os.log

// MARK: - Enhanced Model Management Methods

extension ModelManager {
    func setupFileSystemWatching() {
        WhisperKitStorage.ensureBaseDirectoryExists()
        guard let whisperKitPath = WhisperKitStorage.storageDirectory() else { return }

        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: whisperKitPath, withIntermediateDirectories: true)
        } catch {
            let redactedPath = whisperKitPath.path.redactingHomeDirectory
            Logger.modelManager.error(
                "Failed to create WhisperKit directory at \(redactedPath): \(error.localizedDescription)"
            )
        }

        let descriptor = open(whisperKitPath.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        fileSystemWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        fileSystemWatcher?.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.refreshDownloadedModels()
            }
        }

        fileSystemWatcher?.setCancelHandler {
            close(descriptor)
        }

        fileSystemWatcher?.resume()
    }

    func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshDownloadedModels()
            }
        }
    }

    @MainActor
    func refreshDownloadedModels() async {
        var newDownloadedModels: Set<WhisperModel> = []

        for model in WhisperModel.allCases where await isModelDownloaded(model) {
            newDownloadedModels.insert(model)
        }

        // Only update if there are changes to avoid unnecessary UI updates
        if newDownloadedModels != downloadedModels {
            downloadedModels = newDownloadedModels
            lastRefresh = Date()
        }
    }

    nonisolated func estimateDownloadTime(for model: WhisperModel) -> TimeInterval {
        // Estimate based on model size and typical download speeds
        let sizeInMB = Double(model.estimatedSize) / (1024 * 1024)

        // Assume average download speed of 10 MB/s (conservative estimate)
        let estimatedSeconds = sizeInMB / 10.0

        // Add processing time based on model size
        let processingTime = sizeInMB / 50.0 // Rough estimate for model processing

        return estimatedSeconds + processingTime
    }

    nonisolated func getAvailableStorageSpace() async throws -> Int64 {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ModelError.applicationSupportDirectoryNotFound
        }

        let resourceValues = try documentsPath.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(resourceValues.volumeAvailableCapacity ?? 0)
    }

    nonisolated func sendDownloadCompletionNotification(for model: WhisperModel) async {
        // Check if notifications are available (only works in proper app bundles)
        guard Bundle.main.bundleIdentifier != nil else {
            // Running in development/debug mode, skip notifications
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Model Download Complete"
        content.body = "\(model.displayName) is ready for offline transcription"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "model-download-\(model.rawValue)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Silently fail if notifications aren't available (e.g., when running with swift run)
            Logger.modelManager.debug("Failed to send notification: \(error.localizedDescription)")
        }
    }

    @MainActor
    func refreshModelStates() async {
        await refreshDownloadedModels()
    }

    /// Check if a model is ready for use (downloaded and not currently downloading).
    /// This is an async function to ensure thread-safe access to MainActor-isolated state.
    nonisolated func isModelReady(_ model: WhisperModel) async -> Bool {
        return await MainActor.run {
            downloadedModels.contains(model) && !downloadingModels.contains(model)
        }
    }

    @MainActor
    func getDownloadStage(for model: WhisperModel) -> DownloadStage? {
        return downloadStages[model]
    }

    @MainActor
    func getEstimatedTimeRemaining(for model: WhisperModel) -> TimeInterval? {
        return downloadEstimates[model]
    }
}
