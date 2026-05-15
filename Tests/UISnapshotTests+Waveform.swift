import XCTest
import SwiftUI
import SwiftData
@testable import AudioWhisper

// Waveform-style and additional view snapshot tests, split out of UISnapshotTests
// to keep each file and type within SwiftLint limits.
@MainActor
extension UISnapshotTests {
    // MARK: - Waveform Style Snapshots

    func testWaveformContainerClassicSnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.6,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0.5, count: 8),
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-classic-recording",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    func testWaveformContainerReadySnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")

        let view = WaveformContainer(
            status: .ready,
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0, count: 8),
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-ready",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    func testWaveformContainerSuccessSnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")

        let view = WaveformContainer(
            status: .success,
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: [],
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-success",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    func testWaveformContainerProcessingSnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .processing("Transcribing..."),
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: [],
            processingAnimated: false,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-processing",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    func testWaveformContainerErrorSnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")

        let view = WaveformContainer(
            status: .error( "Failed"),
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: [],
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-error",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    // MARK: - Visual Intensity Snapshots

    func testWaveformContainerGlowIntensitySnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.glow.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0.5, count: 8),
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-glow-intensity",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    func testWaveformContainerBurstIntensitySnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.burst.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0.5, count: 8),
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-burst-intensity",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    // MARK: - Provider Selection Dark Mode Snapshots

    func testDashboardProvidersViewParakeetDarkSnapshot() {
        defaults.set(TranscriptionProvider.parakeet.rawValue, forKey: "transcriptionProvider")

        let view = DashboardProvidersView()
        assertSnapshot(
            view,
            named: "DashboardProvidersView-parakeet-dark",
            size: CGSize(width: 750, height: 800),
            colorScheme: .dark
        )
    }

    // MARK: - Preferences View Snapshots

    func testDashboardPreferencesViewSnapshot() {
        let view = DashboardPreferencesView()
        assertSnapshot(
            view,
            named: "DashboardPreferencesView-light",
            size: CGSize(width: 750, height: 700),
            colorScheme: .light
        )
    }

    func testDashboardPreferencesViewDarkSnapshot() {
        let view = DashboardPreferencesView()
        assertSnapshot(
            view,
            named: "DashboardPreferencesView-dark",
            size: CGSize(width: 750, height: 700),
            colorScheme: .dark
        )
    }

    // MARK: - Correction View Dark Mode Snapshots

    func testDashboardCorrectionViewDarkSnapshot() {
        defaults.set(SemanticCorrectionMode.localMLX.rawValue, forKey: "semanticCorrectionMode")

        let view = DashboardCorrectionView()
        assertSnapshot(
            view,
            named: "DashboardCorrectionView-dark",
            size: CGSize(width: 750, height: 700),
            colorScheme: .dark
        )
    }

    // MARK: - Permission Modal Snapshots

    func testPermissionEducationModalSnapshot() {
        let view = PermissionEducationModal(
            onProceed: {},
            onCancel: {}
        )
        assertSnapshot(
            view,
            named: "PermissionEducationModal-light",
            size: CGSize(width: 450, height: 350),
            colorScheme: .light
        )
    }

    func testPermissionRecoveryModalSnapshot() {
        let view = PermissionRecoveryModal(
            onOpenSettings: {},
            onCancel: {}
        )
        assertSnapshot(
            view,
            named: "PermissionRecoveryModal-light",
            size: CGSize(width: 450, height: 350),
            colorScheme: .light
        )
    }

    func testAccessibilityPermissionModalSnapshot() {
        let view = AccessibilityPermissionModal(
            onAllow: {},
            onDontAllow: {}
        )
        assertSnapshot(
            view,
            named: "AccessibilityPermissionModal-light",
            size: CGSize(width: 450, height: 400),
            colorScheme: .light
        )
    }

    // MARK: - Transcripts View Snapshots

    func testDashboardTranscriptsViewSnapshot() throws {
        let container = try makePreviewContainer()
        let view = DashboardTranscriptsView()
            .modelContainer(container)

        assertSnapshot(
            view,
            named: "DashboardTranscriptsView-light",
            size: CGSize(width: 750, height: 600),
            colorScheme: .light
        )
    }

    // MARK: - Additional Waveform Style Snapshots (D3)
    //
    // The existing waveform tests only exercise the `classic` style. These add
    // baselines for the remaining 5 styles so visual regressions in any one
    // renderer are caught by the snapshot suite.

    private static let sampleWaveformSamples: [Float] = (0..<64).map { index in
        // Deterministic pseudo-samples so the snapshot is stable across runs.
        let phase = Float(index) * 0.25
        return sin(phase) * 0.4 + cos(phase * 1.7) * 0.2
    }

    private static let sampleFrequencyBands: [Float] = [
        0.85, 0.70, 0.60, 0.50, 0.40, 0.30, 0.22, 0.15
    ]

    func testWaveformContainerNeonDarkSnapshot() {
        defaults.set(WaveformStyle.neon.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-neon-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    func testWaveformContainerSpectrumDarkSnapshot() {
        defaults.set(WaveformStyle.spectrum.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-spectrum-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    // The redesign replaced the old circular/pulseRings/particles styles with
    // halo/heartbeat/stream. These exercise the new renderers through the
    // WaveformContainer's style switch so visual regressions are caught.
    func testWaveformContainerHaloDarkSnapshot() {
        defaults.set(WaveformStyle.halo.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-halo-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    func testWaveformContainerHeartbeatDarkSnapshot() {
        defaults.set(WaveformStyle.heartbeat.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-heartbeat-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    func testWaveformContainerStreamDarkSnapshot() {
        defaults.set(WaveformStyle.stream.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-stream-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark
        )
    }

    // Light-mode contrast: spectrum genuinely looks different against a
    // light background because the bg color is themed.
    func testWaveformContainerSpectrumLightSnapshot() {
        defaults.set(WaveformStyle.spectrum.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-spectrum-light",
            size: CGSize(width: 320, height: 200),
            colorScheme: .light
        )
    }

    // Classic recording in light mode — complements the existing dark variant
    // so the recording-state visual is locked down across color schemes.
    func testWaveformContainerClassicRecordingLightSnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0.5, count: 8),
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-classic-recording-light",
            size: CGSize(width: 320, height: 200),
            colorScheme: .light
        )
    }

}
