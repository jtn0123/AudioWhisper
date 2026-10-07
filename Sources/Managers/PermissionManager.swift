import AppKit
import AVFoundation
import Observation

internal enum PermissionState {
    case unknown
    case notRequested
    case requesting
    case granted
    case denied
    case restricted

    var needsRequest: Bool {
        switch self {
        case .unknown, .notRequested:
            return true
        default:
            return false
        }
    }

    var canRetry: Bool {
        switch self {
        case .denied:
            return true
        default:
            return false
        }
    }
}

@MainActor
@Observable
internal class PermissionManager {
    static let shared = PermissionManager()

    var microphonePermissionState: PermissionState = .unknown
    var accessibilityPermissionState: PermissionState = .unknown
    private enum PermissionModal: Equatable {
        case education, recovery, accessibility
    }
    private var presentedModal: PermissionModal?
    var showEducationalModal: Bool {
        get { presentedModal == .education }
        set { setModal(.education, isPresented: newValue) }
    }
    var showRecoveryModal: Bool {
        get { presentedModal == .recovery }
        set { setModal(.recovery, isPresented: newValue) }
    }
    var showAccessibilityModal: Bool {
        get { presentedModal == .accessibility }
        set { setModal(.accessibility, isPresented: newValue) }
    }
    typealias MicrophoneRequest = (@escaping @Sendable (Bool) -> Void) -> Void
    @ObservationIgnored private let microphoneRequest: MicrophoneRequest?
    private let isTestEnvironment: Bool
    private let accessibilityManager = AccessibilityPermissionManager()

    var allPermissionsGranted: Bool {
        let enableSmartPaste = AppDefaults.enableSmartPaste
        if enableSmartPaste {
            return microphonePermissionState == .granted && accessibilityPermissionState == .granted
        } else {
            return microphonePermissionState == .granted
        }
    }

    init(microphoneRequest: MicrophoneRequest? = nil) {
        self.microphoneRequest = microphoneRequest
        // Detect if running in tests
        isTestEnvironment = AppEnvironment.isRunningTests
        // Load actual permission state on initialization
        checkPermissionState()
    }

    func checkPermissionState() {
        checkMicrophonePermission()
        // Always check accessibility permission for accurate status display
        checkAccessibilityPermission()
    }

    private func checkMicrophonePermission() {
        // Don't overwrite if we're already requesting permission
        guard microphonePermissionState != .requesting else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            self.microphonePermissionState = .granted
        case .denied:
            self.microphonePermissionState = .denied
        case .restricted:
            self.microphonePermissionState = .restricted
        case .notDetermined:
            self.microphonePermissionState = .notRequested
        @unknown default:
            self.microphonePermissionState = .unknown
        }
    }

    private func checkAccessibilityPermission() {
        // Refreshes from recording/view lifecycle events must not turn an active
        // Settings/polling request back into another requestable permission.
        guard accessibilityPermissionState != .requesting else { return }
        // Use dedicated AccessibilityPermissionManager for consistent checking
        let trusted = accessibilityManager.checkPermission()

        self.accessibilityPermissionState = trusted ? .granted : .notRequested
    }

    func requestPermissionWithEducation() {
        guard !permissionRequestInProgress, !permissionModalIsPresented else { return }
        let enableSmartPaste = AppDefaults.enableSmartPaste

        let needsMicrophone = microphonePermissionState.needsRequest
        let needsAccessibility = enableSmartPaste && accessibilityPermissionState.needsRequest

        let canRetryMicrophone = microphonePermissionState.canRetry
        let canRetryAccessibility = enableSmartPaste && accessibilityPermissionState.canRetry

        // Recording depends on the microphone. Do not offer optional
        // Accessibility setup while the microphone is denied or restricted.
        if canRetryMicrophone {
            showRecoveryModal = true
        } else if needsMicrophone {
            showEducationalModal = true
        } else if microphonePermissionState == .granted && needsAccessibility {
            showEducationalModal = true
        } else if microphonePermissionState == .granted && canRetryAccessibility {
            showRecoveryModal = true
        }
    }

    func proceedWithPermissionRequest() {
        guard !permissionRequestInProgress, !showAccessibilityModal, !showRecoveryModal else { return }
        showEducationalModal = false
        beginMicrophoneRequest(includeAccessibility: AppDefaults.enableSmartPaste)
    }

    /// Recording requires only Microphone access. Optional Smart Paste setup
    /// remains a separate, explicit flow and never follows this request.
    func requestMicrophonePermission() {
        guard !permissionRequestInProgress, !permissionModalIsPresented else { return }
        beginMicrophoneRequest(includeAccessibility: false)
    }

    private var permissionRequestInProgress: Bool {
        microphonePermissionState == .requesting || accessibilityPermissionState == .requesting
    }

    private var permissionModalIsPresented: Bool {
        presentedModal != nil
    }

    private func setModal(_ modal: PermissionModal, isPresented: Bool) {
        if isPresented {
            guard !permissionRequestInProgress, presentedModal == nil || presentedModal == modal else { return }
            presentedModal = modal
        } else if presentedModal == modal {
            // A stale dismissal from one sheet must not dismiss a newer sheet.
            presentedModal = nil
        }
    }

    /// Handle response from AccessibilityPermissionModal
    func handleAccessibilityModalResponse(allowed: Bool) {
        guard !permissionRequestInProgress else { return }
        showAccessibilityModal = false

        if allowed {
            // User wants to grant permission - open System Settings
            accessibilityPermissionState = .requesting
            accessibilityManager.requestPermissionDirect { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.accessibilityPermissionState = granted ? .granted : .denied
                }
            }
        } else {
            // User chose "Don't Allow" - permanently disable SmartPaste
            AppDefaults.enableSmartPaste = false
            // No longer need accessibility permission since SmartPaste is disabled
        }
    }

    private func beginMicrophoneRequest(includeAccessibility: Bool) {
        if microphonePermissionState.needsRequest {
            // Reserve the request before yielding, including in the simulated
            // path. Repeated hotkey/view callbacks now see the same active run.
            microphonePermissionState = .requesting
            if let microphoneRequest {
                microphoneRequest { [weak self] granted in
                    Task { @MainActor [weak self] in
                        self?.finishMicrophoneRequest(granted: granted, includeAccessibility: includeAccessibility)
                    }
                }
                return
            }
            if isTestEnvironment {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    self?.finishMicrophoneRequest(granted: false, includeAccessibility: includeAccessibility)
                }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.finishMicrophoneRequest(granted: granted, includeAccessibility: includeAccessibility)
                }
            }
        } else if microphonePermissionState == .granted {
            if includeAccessibility { presentAccessibilityExplanationIfNeeded() }
        } else if microphonePermissionState == .denied {
            // macOS does not re-prompt once denied; the only path forward is to
            // route the user to System Settings → Privacy → Microphone.
            if isTestEnvironment { return }
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    private func finishMicrophoneRequest(granted: Bool, includeAccessibility: Bool) {
        microphonePermissionState = granted ? .granted : .denied
        // Denial remains inline. A recovery sheet is opened only by an
        // explicit requestPermissionWithEducation() call, never by a timer.
        if granted && includeAccessibility { presentAccessibilityExplanationIfNeeded() }
    }

    private func presentAccessibilityExplanationIfNeeded() {
        guard microphonePermissionState == .granted,
              AppDefaults.enableSmartPaste,
              accessibilityPermissionState != .granted,
              !permissionRequestInProgress,
              !permissionModalIsPresented else { return }
        showAccessibilityModal = true
    }

    func openSystemSettings() {
        // Skip actual system settings in test environment
        if isTestEnvironment {
            return
        }

        // Open the main Privacy & Security preferences
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
