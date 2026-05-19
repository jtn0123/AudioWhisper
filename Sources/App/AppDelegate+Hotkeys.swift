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
        let immediateRecording = AppDefaults.immediateRecording

        if immediateRecording {
            guard let recorder = audioRecorder else {
                Logger.app.error("AudioRecorder not available for immediate recording")
                toggleRecordWindow()
                return
            }

            if recorder.isRecording {
                updateMenuBarIcon(isRecording: false)
                if recordingWindow == nil || recordingWindow?.isVisible == false {
                    toggleRecordWindow()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .spaceKeyPressed, object: nil)
                }
            } else {
                if PermissionManager.shared.microphonePermissionState != .granted {
                    toggleRecordWindow()
                    return
                }

                if recorder.startRecording() {
                    updateMenuBarIcon(isRecording: true)
                    SoundManager().playRecordingStartSound()
                    // Show the recording window so the user gets visual
                    // feedback, mirroring the press-and-hold path.
                    showRecordingWindowForProcessing()
                } else {
                    toggleRecordWindow()
                    NotificationCenter.default.post(
                        name: .recordingStartFailed,
                        object: nil
                    )
                }
            }
        } else {
            toggleRecordWindow()
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
