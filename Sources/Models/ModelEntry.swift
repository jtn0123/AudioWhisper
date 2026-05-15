import SwiftUI

internal protocol ModelEntry {
    var title: String { get }
    var subtitle: String { get }
    var sizeText: String? { get }
    var statusText: String? { get }
    var statusColor: Color? { get }
    var isDownloaded: Bool { get }
    var isDownloading: Bool { get }
    var isSelected: Bool { get }
    var badgeText: String? { get }
    var onSelect: () -> Void { get }
    var onDownload: () -> Void { get }
    var onDelete: () -> Void { get }
}

internal struct LocalWhisperEntry: ModelEntry {
    let model: WhisperModel
    let stage: DownloadStage?
    let estimatedTimeRemaining: TimeInterval?
    let isDownloaded: Bool
    let isDownloading: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var title: String { model.displayName }
    var subtitle: String { model.description }
    var sizeText: String? { model.fileSize }
    var statusText: String? {
        guard let stage = stage else { return nil }
        let time = estimatedTimeRemaining.map { remaining -> String in
            let totalSeconds = max(0, Int(remaining))
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return minutes > 0 ? "~\(minutes)m \(seconds)s" : "~\(seconds)s"
        }
        return stage.displayText + (time.map { " • \($0)" } ?? "")
    }
    var statusColor: Color? {
        guard let stage = stage else { return nil }
        switch stage {
        case .failed: return .red
        case .preparing, .downloading, .processing, .completing: return .blue
        case .ready: return .green
        }
    }
    var badgeText: String? { model == .base ? "RECOMMENDED" : nil }
}

internal struct MLXEntry: ModelEntry {
    let model: MLXModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let statusText: String?
    let sizeText: String?
    let isSelected: Bool
    let badgeText: String?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var title: String { model.displayName }
    var subtitle: String { model.description }
    var statusColor: Color? {
        if let status = statusText,
           status.localizedCaseInsensitiveContains("error") || status.localizedCaseInsensitiveContains("please") {
            return .red
        }
        return isDownloading ? .blue : nil
    }
}
