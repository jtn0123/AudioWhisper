# Recommended rebuild fixes — validation

Date: 2026-10-03. Worktree: `/Users/justin/.t3/worktrees/AudioWhisper/native-v2`.
Branch: `rebuild/native-v2`. Packaged source commit: `f0cc89a40dd380668c432ec186826772f3cd2b03`.
App: `AudioWhisper.app`, bundle ID `com.audiowhisper.rebuild`, version 2.0.0.

## Implemented

- E1: uv 0.12.23, verified vendor archives for both architectures; reject installers below 0.11.15.
- A1 / UI H1: UUID-scoped capture interruptions reconcile session, overlay and temporary audio ownership.
- B1 / UI H2: route the selected input Audio Unit before recording, surface unavailable inputs, boost/restore the captured device.
- D1: injectable setup coordinator with seven permission/setup/install regressions.
- B2 / UI H3: failed load verdicts persist by selected model and asset identity; block capture and file jobs until repair or successful verification. Whisper verification loads the model.
- A2: retry respects model/setup/maintenance gates and retains its captured audio while blocked.
- C1 / UI C1: shared action titles, enabled states and reasons across workspace, setup, menu, picker and drops.
- C2 / UI H4: successful store mutations publish an observed revision; Library reloads while retaining its query.

## Local validation

- Full parallel Swift suite: 3,026 discovered cases, exit 0. Opt-in real-engine tests run separately below.
- Strict full Swift lint: pass, local SwiftLint 0.65.1 (CI pins 0.65.0).
- Strict Python type check: pass, 11 source files.
- Python unit suite: 88 tests, pass.
- Actual engine fixtures: 3 tests, pass. Parakeet transcribes speech; Whisper cold/warm runs both produce “The quick brown fox jumps over the lazy dog.” and actual model verification loads successfully; writing cleanup performs actual MLX inference.
- Frozen runtime refresh 0.763 s; warm reuse 0.0013 s. Whisper cold 0.665 s, warm 0.069 s on this Mac. These are individual fixture observations, not performance guarantees.
- Universal release build: pass, x86_64 + arm64. Bundled uv reports 0.12.23.
- Complete app signature: strict/deep validation passes; no bundled .pyc files or __pycache__ directories. Signing is ad hoc, not a notarized release.

## Native verification

- Final artifact launches in a conventional workspace window.
- Fresh build consent is not granted yet; readiness correctly says Allow microphone access.
- Five blocked recording commands stay in one setup window and do not request permission. Only clicking Allow microphone requests OS consent; the button becomes Waiting for macOS and is disabled.
- Live recording, same-build cold relaunch, selected-input and mounted Library checks are pending that one macOS consent click.

## Limits

Only one physical microphone is attached. Two distinguishable inputs, actual device disconnection/sleep, VoiceOver, physical global shortcut delivery and Smart Paste remain unverified. The original worktree is clean and synced at 37301a1. No distribution certificate, notarization or release is claimed.

Remote CI: [code run](https://github.com/jtn0123/AudioWhisper/actions/runs/37178898261) is in progress. The prior grade reports remain the original C+ audit with addressed IDs marked complete; these changes are not a fresh nine-category regrade.
