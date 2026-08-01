// swiftlint:disable:next unused_import - verified required: removing it breaks the build
import SwiftUI
import Combine

/// A stoppable per-frame timer for waveform animations.
///
/// `Timer.publish(...).autoconnect()` runs forever the moment a view is
/// created — even for waveform tiles that are off-screen or in an idle state.
/// With the Visuals grid showing 8 styles at once that is hundreds of
/// main-thread state mutations per second while nothing is visible.
///
/// `FrameTimer` instead exposes a passthrough `publisher` that only emits
/// while `start()` has been called and `stop()` has not. Views drive it from
/// `onAppear`/`onDisappear`, so the timer is fully cancelled — not merely
/// ignored — whenever the view leaves the screen.
final class FrameTimer {
    /// Per-frame tick stream. Emits only between `start()` and `stop()`.
    let publisher = PassthroughSubject<Date, Never>()

    private let interval: TimeInterval
    private var cancellable: AnyCancellable?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Begin emitting ticks. No-op if already running.
    func start() {
        guard cancellable == nil else { return }
        cancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [publisher] date in publisher.send(date) }
    }

    /// Stop emitting ticks and cancel the underlying timer.
    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }
}
