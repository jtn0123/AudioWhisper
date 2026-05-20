import AppKit
import os.log

internal extension AppDelegate {
    func configureShortcutMonitors() {
        pressAndHoldMonitor?.stop()
        pressAndHoldMonitor = nil
        isHoldRecordingActive = false

        let newConfiguration = PressAndHoldSettings.configuration()
        pressAndHoldConfiguration = newConfiguration

        guard newConfiguration.enabled else { return }

        let keyUpHandler: (() -> Void)? = (newConfiguration.mode == .hold) ? { [weak self] in
            self?.handlePressAndHoldKeyUp()
        } : nil

        let monitor = PressAndHoldKeyMonitor(
            configuration: newConfiguration,
            keyDownHandler: { [weak self] in
                self?.handlePressAndHoldKeyDown()
            },
            keyUpHandler: keyUpHandler
        )

        pressAndHoldMonitor = monitor
        monitor.start()
    }

    private func handlePressAndHoldKeyDown() {
        switch pressAndHoldConfiguration.mode {
        case .hold:
            startRecordingFromPressAndHold()
        case .toggle:
            handleHotkey(source: .pressAndHold)
        }
    }

    private func handlePressAndHoldKeyUp() {
        guard pressAndHoldConfiguration.mode == .hold else { return }
        stopRecordingFromPressAndHold()
    }

    private func startRecordingFromPressAndHold() {
        guard let recorder = audioRecorder else { return }

        // H2: While a transcription is still being processed the recorder is
        // already stopped; treat the key-down as a no-op so we don't fall into
        // the start-recording branch and surface a misleading failure toast.
        if isTranscriptionProcessing {
            Logger.app.debug("Press-and-hold ignored: transcription in progress")
            return
        }

        if recorder.isRecording {
            isHoldRecordingActive = true
            return
        }

        if PermissionManager.shared.microphonePermissionState != .granted {
            showRecordingWindowForProcessing()
            return
        }

        if recorder.startRecording() {
            isHoldRecordingActive = true
            updateMenuBarIcon(isRecording: true)
            SoundManager().playRecordingStartSound()
            // Show recording window immediately so user sees visual feedback while holding
            showRecordingWindowForProcessing()
        } else {
            isHoldRecordingActive = false
            showRecordingWindowForProcessing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(
                        name: .recordingStartFailed,
                        object: nil
                    )
                }
            }
        }
    }

    private func stopRecordingFromPressAndHold() {
        guard isHoldRecordingActive else { return }
        guard let recorder = audioRecorder, recorder.isRecording else {
            isHoldRecordingActive = false
            return
        }

        isHoldRecordingActive = false
        updateMenuBarIcon(isRecording: false)

        showRecordingWindowForProcessing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .spaceKeyPressed, object: nil)
            }
        }
    }

    func handleHotkey(source: HotkeyTriggerSource) {
        // H3: If the recorder is actively recording, ALWAYS stop it on press —
        // regardless of the current `immediateRecording` toggle. Otherwise
        // flipping the setting off mid-recording would route the stop press
        // through `toggleRecordWindow()` and strand the recorder.
        if let recorder = audioRecorder, recorder.isRecording {
            stopActiveRecordingFromHotkey()
            return
        }

        // H1: A press received while transcription is still running would
        // otherwise fall into the start-branch (recorder is already stopped)
        // and produce a "recordingStartFailed" toast. No-op instead.
        if isTranscriptionProcessing {
            Logger.app.debug("Hotkey ignored: transcription in progress")
            return
        }

        if AppDefaults.immediateRecording {
            startImmediateRecordingFromHotkey()
        } else {
            toggleRecordWindow()
        }
    }

    private func stopActiveRecordingFromHotkey() {
        updateMenuBarIcon(isRecording: false)
        if recordingWindow == nil || recordingWindow?.isVisible == false {
            toggleRecordWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .spaceKeyPressed, object: nil)
        }
    }

    private func startImmediateRecordingFromHotkey() {
        guard let recorder = audioRecorder else {
            Logger.app.error("AudioRecorder not available for immediate recording")
            toggleRecordWindow()
            return
        }

        if PermissionManager.shared.microphonePermissionState != .granted {
            toggleRecordWindow()
            return
        }

        if recorder.startRecording() {
            updateMenuBarIcon(isRecording: true)
            SoundManager().playRecordingStartSound()
            // Show the recording window so the user gets visual feedback,
            // mirroring the press-and-hold path.
            showRecordingWindowForProcessing()
        } else {
            toggleRecordWindow()
            NotificationCenter.default.post(
                name: .recordingStartFailed,
                object: nil
            )
        }
    }

    /// Drives the menu bar icon state. The renderer owns its own timer and
    /// produces a smooth coral pulse while recording.
    func updateMenuBarIcon(isRecording: Bool) {
        iconRenderer?.setState(isRecording ? .recording : .idle)
    }

    @objc func onRecordingStopped() {
        updateMenuBarIcon(isRecording: false)
    }
}
