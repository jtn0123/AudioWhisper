import SwiftUI
import Combine

/// A SwiftUI property wrapper that bridges `View` state to a typed `AppDefaults`
/// accessor. Equivalent to `@AppStorage` but reads/writes go through the
/// strongly-typed `AppDefaults` namespace instead of raw `UserDefaults` keys.
///
/// Usage:
///   @AppDefault(\.transcriptionProvider) var provider
///   @AppDefault(\.enableSmartPaste) var enableSmartPaste
///
/// The view re-renders when the underlying value changes. Two-way binding
/// works through `$provider`.
///
/// See ADR 0004 for the migration plan from `@AppStorage`.
@propertyWrapper
struct AppDefault<Value: Equatable>: DynamicProperty {
    private let keyPath: ReferenceWritableKeyPath<AppDefaults.Type, Value>
    @State private var value: Value
    @StateObject private var observer: AppDefaultObserver

    init(_ keyPath: ReferenceWritableKeyPath<AppDefaults.Type, Value>) {
        self.keyPath = keyPath
        let initial = AppDefaults.self[keyPath: keyPath]
        self._value = State(initialValue: initial)
        // The observer re-reads the SAME keyPath on every defaults change and
        // only invalidates when this view's value actually changed — so an
        // unrelated defaults write elsewhere in the app no longer forces a
        // re-render of every view holding any `@AppDefault`.
        self._observer = StateObject(wrappedValue: AppDefaultObserver {
            AppDefaults.self[keyPath: keyPath]
        })
    }

    var wrappedValue: Value {
        get { value }
        nonmutating set {
            value = newValue
            AppDefaults.self[keyPath: keyPath] = newValue
        }
    }

    var projectedValue: Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }

    func update() {
        // Re-read once per body invocation in case the underlying store changed
        // out from under us (e.g. user toggled a setting in another window).
        let current = AppDefaults.self[keyPath: keyPath]
        if current != value {
            DispatchQueue.main.async { self.value = current }
        }
    }
}

/// Listens for UserDefaults change notifications and triggers a SwiftUI
/// invalidation by mutating its own `@Published` — but ONLY when the specific
/// value this `@AppDefault` tracks actually changed.
///
/// `UserDefaults.didChangeNotification` fires for ANY defaults write anywhere
/// in the app and carries no key information, so it cannot be filtered at the
/// notification level. Instead the observer is given a `readValue` closure
/// bound to its `@AppDefault`'s keyPath; on each notification it re-reads that
/// value and skips the invalidation when nothing relevant changed. This
/// removes the over-broad re-render churn without changing `@AppDefault`'s
/// keyPath-based design.
private final class AppDefaultObserver: ObservableObject {
    @Published private var tick: UInt64 = 0
    private var cancellable: AnyCancellable?
    private let readValue: () -> AnyHashable?
    private var lastSnapshot: AnyHashable?

    /// - Parameter readValue: re-reads the tracked value. The value is wrapped
    ///   in `AnyHashable` for equality comparison; non-`Hashable` values fall
    ///   back to always invalidating (the previous behavior).
    init<Value: Equatable>(read: @escaping () -> Value) {
        self.readValue = { (read() as? AnyHashable) }
        self.lastSnapshot = readValue()
        cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.invalidateIfChanged() }
            }
    }

    @MainActor
    private func invalidateIfChanged() {
        let current = readValue()
        // If the value isn't Hashable we get nil here; treat that as "always
        // invalidate" so correctness is never regressed for such types.
        if current == nil || current != lastSnapshot {
            lastSnapshot = current
            tick &+= 1
        }
    }
}
