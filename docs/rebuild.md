# AudioWhisper native rebuild

Branch `rebuild/native-v2`, isolated worktree outside Documents. The installed app and its data remain intact.

## Product direction

A new SwiftUI workspace, one session controller, one setup checklist, explicit permission actions, and an unobtrusive recorder. A warm paper/ink palette with restrained rust accents, native controls, keyboard navigation, readable typography, and reduced-motion support. Normal windows stay on desktops. Only the recorder can appear over full-screen apps.

The existing CoreAudio and model engines are reusable infrastructure, not the new app's state or navigation. The obsolete SwiftUI app entry is removed. Legacy view/controller implementations remain compiled temporarily for regression tests; the rebuild never launches their shell.

## Required feature parity

- Live recording: click, configurable shortcut, Express Mode, modifier hold/toggle, cancel, microphone choice, input boost, sound, live levels.
- Transcription: Whisper on Intel/Apple Silicon; Parakeet on Apple Silicon; selected-model installation, progress, verification, deletion, retry and offline readiness.
- Delivery: clipboard, captured-target Smart Paste, visible correction fallback, no stale session delivery.
- Files: explicit file picker/drop, supported audio validation, cancel and retry.
- Writing: optional local correction, model choice/install, editable profiles, per-app mappings and prompt overrides.
- Library: opt-in local history, search, paging, copy, export, delete, retention, usage totals.
- Preferences: shortcut, startup, appearance, overlay styles/intensity, privacy, diagnostics.

## Storage and isolation

`com.audiowhisper.rebuild` uses separate preferences, history, categories, runtime and Whisper assets. App-managed files live in Application Support; shared Hugging Face weights remain in the unprotected cache. Startup never scans Documents/Desktop/Downloads and does not migrate old files implicitly. Existing data can be imported through explicit user selection later.

## Verification boundaries

Existing macOS runner Whisper inference failure remains visible. No microphone or Accessibility access is granted automatically. A new identity permits side-by-side review without replacing the installed app; global recording is opt-in to avoid competing shortcuts.

## Verification log

- 2026-10-03: blocked recording click opened the existing setup page without requesting permissions.
- Parakeet verification loaded the selected cached model offline from the new UI.
- The packaged app transcribed `speech_sample.wav` as “The quick brown fox jumps over the lazy dog.” with microphone access still unrequested. Delivery and usage counters updated.
- Preferences initially crashed because the release script omitted dependency resource bundles. The repaired bundle reopened Preferences and rendered the shortcut editor. Packaging and CI now require those bundles and the English shortcut localization.
- Light and system/dark appearance were inspected in the native app. Original app data and bundle remain separate.

Microphone recording, hold-to-record, Smart Paste and the full desktop/full-screen window matrix still need native validation under the new identity. The known Whisper failure on a macOS CI runner is unresolved. The preview is unsigned without a configured signing identity. Existing library import is intentionally pending explicit migration design.
