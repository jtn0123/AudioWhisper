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
- Writing-model verification completed offline; the existing Terminal profile opened in the editor and canceled without creating a profile.
- Local validation passed 2,991 Swift tests, 88 Python tests, strict SwiftLint and strict Python type checks. A separate real-engine run passed Parakeet transcription, Whisper transcription (cold and warm), and MLX writing cleanup.
- The first live microphone test exposed repeated macOS consent requests. The preview had only a linker signature: `Identifier=AudioWhisper`, `Info.plist=not bound`, no sealed resources, and bundle verification failed. Signing the completed bundle changed the identifier to `com.audiowhisper.rebuild`, bound its Info.plist/resources and passed strict verification. After one consent for the corrected identity, five consecutive live start/cancel cycles, live start/stop/transcription, and start/cancel after a cold relaunch passed without another prompt.
- The build now signs local previews ad hoc when no certificate is available and fails on signature errors. CI checks the complete bundle signature, app identifier, signing requirement and Foundation localization resolution. The latter handles SwiftPM's flat and Contents/Resources bundle layouts.
- A post-transcription signature check found Python adding `ml/__pycache__` inside the signed app. Daemon, download and verification subprocesses now disable bytecode writes; packaging strips development caches from every resource bundle before signing. A real daemon ping regression reproduced the added files before the fix and preserved the resource tree afterward. All 89 targeted daemon, model verification, download and session checks passed, with strict SwiftLint still clean.

The global shortcut could not be exercised by the native automation key command, so physical shortcut delivery remains unverified; its temporary test setting was returned to off. Hold-to-record, Smart Paste and the full desktop/full-screen window matrix still need native validation under the new identity. The known Whisper failure on a macOS CI runner is unresolved. Ad-hoc signing retains permission for the same build across launches; a different build may need new consent. Distribution needs a Developer ID and notarization. Existing library import is intentionally pending explicit migration design.
