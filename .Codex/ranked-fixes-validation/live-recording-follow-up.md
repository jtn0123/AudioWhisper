# Live permission and recording follow-up — 2026-10-04

Tested unchanged signed bundle b47fe8e, com.audiowhisper.rebuild.

- User granted microphone consent. Four live start/cancel cycles succeeded (one before cold relaunch and three afterward). Consent persisted across cold relaunch; no additional microphone prompt appeared.
- Fifth start failed with CoreAudio status 1852797029 (`nope`). UI returned to idle, with usage unchanged at 6 sessions / 5,826 words. The captured app accessibility state records the error.
- A further repeated-start attempt blocked the main thread. A one-second native process sample of PID 57481 at 11:42:51 shows RebuildSession.toggleRecording -> AudioEngineRecorder.startRecording:365 -> AVAudioEngine.inputNode -> AVAEHalUtil::GetSubDevices -> CoreAudio property queries. Recording had not reached engine.start in that stack. This establishes the blocked boundary, not its underlying cause.
- Read-only audio inventory shows built-in MacBook Pro microphone as default input, 48 kHz, one input channel; built-in speakers are the only other device. Relevant persisted app/coreaudiod log queries returned no events. No new AudioWhisper crash report was located. PID 57481 later exited; the mechanism of exit was not established.
- User explicitly approved Accessibility and completed OS authentication. Adding the exact rebuild bundle changed the lower duplicate AudioWhisper.app entry to enabled. The app's AXIsProcessTrusted check still reported false, including after cold relaunch. Stale signing identity is an unconfirmed hypothesis, not a diagnosis.
- Native control could toggle permissions but could not select the permission row. Coordinate actions failed with noWindowsAvailable. Later Finder observation failed with ScreenCaptureKit -3811, and reconnecting after a REPL reset timed out. These control failures are separate from the sampled app hang.
- Smart Paste was enabled for testing; physical hold, Smart Paste delivery and live stop/transcription remain unperformed. Its test toggle could not be restored through the unavailable native-control channel. Shortcut and hold mode remained off. No Library transcript was saved.

No speculative source change or repackaging was performed. The recording failure remains open. Prior passing unit/CI results do not supersede this failed live acceptance check.
