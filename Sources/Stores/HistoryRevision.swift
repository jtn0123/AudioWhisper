import Observation

/// Changes only after the history store successfully commits a mutation.
@MainActor
@Observable
final class HistoryRevision {
    private(set) var value: UInt64 = 0
    func advance() { value &+= 1 }
}
