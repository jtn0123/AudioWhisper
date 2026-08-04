import SwiftUI

/// A `ScrollView` that can be flattened for offscreen rendering.
///
/// `ImageRenderer` — which the snapshot tests use — does not draw `ScrollView`
/// content. It produces a single flat rectangle instead. That made 13 of the 39
/// committed snapshot baselines blank images, 10 of them a single colour, and
/// every one of those tests had been passing since the day it was recorded
/// while asserting nothing at all.
///
/// Rather than duplicate each view's body into a test-only variant (which then
/// drifts from the real one), the scroll container itself becomes conditional.
/// In the app `flattensScrollViews` is always false and this is exactly a
/// `ScrollView`; only `SnapshotTestCase` ever sets it true.
internal struct ScrollableContent<Content: View>: View {
    @Environment(\.flattensScrollViews) private var flattened

    @ViewBuilder var content: Content

    var body: some View {
        if flattened {
            content
        } else {
            ScrollView {
                content
            }
        }
    }
}

private struct FlattensScrollViewsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Renders `ScrollableContent` without its `ScrollView` wrapper so the
    /// content is visible to `ImageRenderer`. Test-only; never set in the app.
    internal var flattensScrollViews: Bool {
        get { self[FlattensScrollViewsKey.self] }
        set { self[FlattensScrollViewsKey.self] = newValue }
    }
}
