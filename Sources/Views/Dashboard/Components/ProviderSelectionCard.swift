// MARK: - Provider Display Extensions

extension TranscriptionProvider {
    var subtitle: String {
        switch self {
        case .local: return "On-Device"
        case .parakeet: return "Apple Silicon"
        }
    }
}
