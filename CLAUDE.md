# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Pull Requests — Critical

**ALWAYS open pull requests against this repository (`jtn0123/AudioWhisper`), never against any upstream/fork parent.** This repo is a fork; `gh pr create` will default to the upstream parent (`mazdak/AudioWhisper`) — that default is WRONG. Always pass `--repo jtn0123/AudioWhisper` and target the `master` branch of this repo. Never create, push, or retarget a PR to a different repository.

## Build Commands

```bash
# Build release app bundle
make build

# Run in development mode
swift run

# Build for release (without app bundle)
swift build -c release

# Run tests (parallel — settings are isolated per process by AppDefaults,
# so plain `swift test --parallel` is safe too)
make test

# Coverage. --parallel is fine: the old advice here was that llvm merges one
# .profraw per process so parallel workers race it, but measuring 2830 tests
# gives 53.50% parallel vs 53.54% sequential — 30 lines out of 92,525, which is
# ordinary run-to-run variance, not lost profile data.
swift test --parallel --enable-code-coverage

# Run a single test file
swift test --filter "DataManagerTests"

# Run a specific test
swift test --filter "DataManagerTests/testSaveAndLoadHistory"

# Lint (wrapper handles the Command Line Tools / Xcode sourcekitd trap, and
# warns if your SwiftLint differs from the version CI pins)
scripts/lint.sh

# Clean build artifacts
make clean
```

## Snapshot tests

UI snapshots are a **local-only** tool and are skipped unless opted into:

```bash
SNAPSHOT_TESTS=1  swift test --no-parallel -Xswiftc -DTESTING --filter UISnapshotTests   # check
SNAPSHOT_RECORD=1 swift test --no-parallel -Xswiftc -DTESTING --filter UISnapshotTests   # re-record
```

They do not run in CI, deliberately: a GitHub runner has no usable WindowServer,
so it draws AppKit-backed controls as a yellow "cannot render" placeholder and
whole views as flat rectangles. Never adopt a CI-rendered image as a baseline.

Two things to know before adding one:

* `ImageRenderer` cannot draw `ScrollView` content — it renders a flat
  rectangle. Use `ScrollableContent` (Sources/Views/Dashboard) instead, which
  the test harness flattens. 13 baselines were silently blank before this.
* Anything time-dependent must be pinned. Records stamped with `Date()` produce
  a different image every run; see `sampleHistoryRecords()`.

`assertSnapshot` fails any render that is >99.5% a single colour, so a snapshot
that quietly stops drawing cannot pass by matching an equally blank baseline.

## Deployment

After building, deploy to Applications:
```bash
pkill -x AudioWhisper 2>/dev/null || true
rm -rf /Applications/AudioWhisper.app
cp -R AudioWhisper.app /Applications/
open /Applications/AudioWhisper.app
```

**Accessibility Permission Note**: After deploying a new build, SmartPaste may break because macOS invalidates Accessibility permissions when the code signature changes. Users must remove and re-add AudioWhisper in System Settings → Privacy & Security → Accessibility.

## Architecture

### App Entry Point
- `Sources/App/AudioWhisperApp.swift` - SwiftUI app entry, menu bar app with no main window
- `Sources/App/AppDelegate.swift` - Core app delegate split across extensions:
  - `AppDelegate+Hotkeys.swift` - Global hotkey handling
  - `AppDelegate+Lifecycle.swift` - App lifecycle events
  - `AppDelegate+Menu.swift` - Menu bar setup
  - `AppDelegate+Notifications.swift` - System notifications
  - `AppDelegate+RecordingWindow.swift` - Recording UI management

### Transcription Services (`Sources/Services/`)
- `SpeechToTextService.swift` - Main transcription orchestrator, routes to appropriate provider
- `LocalWhisperService.swift` - WhisperKit CoreML transcription (offline)
- `ParakeetService.swift` - Parakeet-MLX transcription (Apple Silicon, offline)
- `SemanticCorrectionService.swift` - Post-processing cleanup (typos, punctuation)
- `MLXCorrectionService.swift` - Local MLX-based semantic correction

### State Management (`Sources/Stores/`)
- `DataManager.swift` - SwiftData persistence for transcription history
- `UsageMetricsStore.swift` - Session stats (words, WPM, time saved)
- `CategoryStore.swift` - App-aware category definitions
- `SourceUsageStore.swift` - Provider usage tracking

### Managers (`Sources/Managers/`)
- `HotKeyManager.swift` - Global keyboard shortcuts via HotKey library
- `PasteManager.swift` - Clipboard and SmartPaste functionality
- `PressAndHoldKeyMonitor.swift` - Push-to-talk modifier key handling
- `PermissionManager.swift` - Microphone/Accessibility permission checks
- `MLDaemonManager.swift` - Background Python process for MLX models

### Python Integration
The app embeds Python scripts for MLX-based features:
- `Sources/parakeet_transcribe_pcm.py` - Parakeet transcription
- `Sources/mlx_semantic_correct.py` - MLX semantic correction
- `Sources/ml/` - Python ML package
- `Sources/verify_parakeet.py`, `Sources/verify_mlx.py` - Model verification

Python dependencies are managed via bundled `uv` binary. `UvBootstrap.swift` handles environment setup.

## Key Dependencies

- **SwiftUI + AppKit** - UI and menu bar integration
- **AVFoundation** - Audio recording
- **Alamofire** - HTTP requests and model downloads
- **WhisperKit** - CoreML-based local transcription
- **HotKey** - Global keyboard shortcuts
- **KeychainAccess** - Secure API key storage (via Keychain)

## Code Patterns

- Swift 5.9+ targeting macOS 14+
- Use `@MainActor` for UI components
- Prefer `guard let` over force unwrapping
- Use `[weak self]` in closures to prevent retain cycles
- Swift Concurrency (`async`/`await`) for async flows
- Keep functions ≤ 40 lines
