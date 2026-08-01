import Foundation

/// A coordinator for managing notification observers with automatic cleanup.
/// Provides a cleaner API than manually tracking NSObjectProtocol references.
@MainActor
final class NotificationCoordinator {
    private var observers: [Notification.Name: NSObjectProtocol] = [:]
    private var tasks: [Notification.Name: Task<Void, Never>] = [:]
    /// In-flight handler Tasks spawned by `observeOnMainActor`, keyed by
    /// notification name. Tracked so `remove`/`removeAll` can cancel handlers
    /// that are still running, preventing them from mutating state after
    /// teardown. Each task removes itself on completion to avoid accumulation.
    private var handlerTasks: [Notification.Name: [UUID: Task<Void, Never>]] = [:]

    deinit {
        // Clean up any remaining observers
        // Note: This runs on whatever thread triggers deallocation
        let observersToRemove = observers.values
        for observer in observersToRemove {
            NotificationCenter.default.removeObserver(observer)
        }

        // Cancel async-stream Tasks so the `for await` loops in
        // `observeAsync` terminate when the coordinator is dropped (bug H11).
        // `Task.cancel()` is safe to call from any thread.
        for task in tasks.values {
            task.cancel()
        }

        // Cancel in-flight handler Tasks spawned by `observeOnMainActor` so
        // they cannot mutate state after the coordinator is gone (bug H11).
        for tasksForName in handlerTasks.values {
            for task in tasksForName.values {
                task.cancel()
            }
        }
    }

    // MARK: - Traditional Observer Pattern

    /// Adds an observer for a notification using the traditional closure-based API.
    /// The observer is automatically tracked and can be removed with `remove(for:)` or `removeAll()`.
    ///
    /// - Parameters:
    ///   - name: The notification name to observe
    ///   - queue: The operation queue to run the handler on (defaults to main)
    ///   - handler: The closure to execute when the notification is received
    func observe(
        _ name: Notification.Name,
        queue: OperationQueue? = .main,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        // Remove existing observer for this name if any
        remove(for: name)

        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: queue,
            using: handler
        )
        observers[name] = observer
    }

    /// Adds an observer that wraps the handler in a MainActor Task.
    /// Useful for observers that need to update UI state.
    ///
    /// - Parameters:
    ///   - name: The notification name to observe
    ///   - handler: The async closure to execute on the MainActor
    func observeOnMainActor(
        _ name: Notification.Name,
        handler: @escaping @MainActor (Notification) async -> Void
    ) {
        observe(name, queue: .main) { [weak self] notification in
            // Spawn the handler Task on the MainActor and track it so it can be
            // cancelled by `remove`/`removeAll`. The Task removes itself from
            // tracking on completion so finished tasks don't accumulate.
            Task { @MainActor in
                guard let self else {
                    await handler(notification)
                    return
                }
                let id = UUID()
                let task = Task { @MainActor in
                    await handler(notification)
                }
                self.handlerTasks[name, default: [:]][id] = task
                _ = await task.value
                self.handlerTasks[name]?.removeValue(forKey: id)
                if self.handlerTasks[name]?.isEmpty == true {
                    self.handlerTasks.removeValue(forKey: name)
                }
            }
        }
    }

    /// Cancels and clears all in-flight handler Tasks for a notification name.
    private func cancelHandlerTasks(for name: Notification.Name) {
        if let tasksForName = handlerTasks.removeValue(forKey: name) {
            for task in tasksForName.values {
                task.cancel()
            }
        }
    }

    // MARK: - Async Stream Pattern

    // MARK: - Cleanup

    /// Removes the observer for a specific notification name.
    func remove(for name: Notification.Name) {
        if let observer = observers.removeValue(forKey: name) {
            NotificationCenter.default.removeObserver(observer)
        }
        if let task = tasks.removeValue(forKey: name) {
            task.cancel()
        }
        // Cancel any in-flight handler Tasks spawned for this notification.
        cancelHandlerTasks(for: name)
    }

    /// Removes all observers and cancels all tasks.
    func removeAll() {
        for observer in observers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()

        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()

        // Cancel any in-flight handler Tasks so they cannot mutate state
        // after teardown.
        for tasksForName in handlerTasks.values {
            for task in tasksForName.values {
                task.cancel()
            }
        }
        handlerTasks.removeAll()
    }

    // MARK: - Query

    /// Returns true if an observer exists for the given notification name.
    func isObserving(_ name: Notification.Name) -> Bool {
        observers[name] != nil || tasks[name] != nil
    }

    /// Returns the count of active observers.
    var observerCount: Int {
        observers.count + tasks.count
    }
}
