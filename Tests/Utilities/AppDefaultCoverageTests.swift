import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

// MARK: - AppDefault Property Wrapper Tests
@MainActor
final class AppDefaultCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): AppDefault bridges to AppDefaults which reads UserDefaults.standard.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    /// Host view that exercises the @AppDefault wrapper's update()/body path.
    private struct ProbeView: View {
        @AppDefault(\.waveformStyle) var style
        @AppDefault(\.immediateRecording) var immediate

        var body: some View {
            VStack {
                Text(style.rawValue)
                Text(immediate ? "on" : "off")
            }
        }
    }

    func testWrapperReadsInitialValueFromAppDefaults() {
        AppDefaults.waveformStyle = .neon
        let wrapper = AppDefault(\.waveformStyle)
        XCTAssertEqual(wrapper.wrappedValue, .neon)
    }

    func testProjectedValueBindingReadsInitialValue() {
        AppDefaults.immediateRecording = false
        let wrapper = AppDefault(\.immediateRecording)
        let binding = wrapper.projectedValue
        XCTAssertFalse(binding.wrappedValue)
    }

    func testProjectedValueIsAccessible() {
        let wrapper = AppDefault(\.waveformStyle)
        // Exercise the projectedValue accessor / Binding construction path.
        let binding = wrapper.projectedValue
        XCTAssertEqual(binding.wrappedValue, wrapper.wrappedValue)
    }

    func testWrapperRendersInsideHostingView() {
        AppDefaults.waveformStyle = .heartbeat
        AppDefaults.immediateRecording = true
        let hosting = NSHostingView(rootView: ProbeView())
        hosting.frame = CGRect(x: 0, y: 0, width: 120, height: 80)
        hosting.layout()
        XCTAssertNotNil(hosting)
    }

    func testUpdateDoesNotCrashWhenStoreChanges() {
        let wrapper = AppDefault(\.waveformStyle)
        // Simulate an external store mutation then invoke update().
        AppDefaults.waveformStyle = .halo
        wrapper.update()
        XCTAssertNotNil(wrapper)
    }
}
