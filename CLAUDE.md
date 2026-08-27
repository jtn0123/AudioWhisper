# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Pull Requests — Critical

**ALWAYS open pull requests against this repository (`jtn0123/AudioWhisper`), never against any upstream/fork parent.** This repo is a fork; `gh pr create` will default to the upstream parent (`mazdak/AudioWhisper`) — that default is WRONG. Always pass `--repo jtn0123/AudioWhisper` and target the `master` branch of this repo. Never create, push, or retarget a PR to a different repository.

## Build Commands

> **Toolchain:** the package compiles `Sources/Assets.xcassets`, which needs
> `actool` — Xcode only, **not** Command Line Tools. If `xcode-select -p` points
> at `/Library/Developer/CommandLineTools` (which happens silently after a CLT
> update), every bare `swift build` / `swift test` dies with
> `Failed to decode version info for '/usr/bin/actool'` followed by
> `error: fatalError`, naming neither the cause nor the fix.
>
> The `make` targets and `scripts/*.sh` all source `scripts/lib/xcode-env.sh`,
> which sets `DEVELOPER_DIR` for that process and recovers automatically — so
> **prefer `make build` / `make test`**. Bare `swift` commands bypass that
> recovery; if you use them on a CLT-selected machine, prefix them:
>
> ```bash
> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --parallel
> ```

```bash
# Build release app bundle
make build

# Run in development mode
swift run

# Build for release (without app bundle)
swift build -c release

# Run tests. Prefer this over bare `swift test`: it recovers from a
# CLT-selected toolchain (see the note above) and sweeps the scratch settings
# domains. Settings are isolated per process by AppDefaults, so the --parallel
# it runs is safe.
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

# Type-check the bundled Python (mypy --strict, config in mypy.ini).
# Sources/ml is the only code here with no compiler in front of it, so this is
# the equivalent gate. Needs no venv and no models — mypy.ini exempts the ML
# imports per-module — so it runs on a bare checkout in seconds.
make typecheck

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
- `HotKeyManager.swift` - Global keyboard shortcuts via KeyboardShortcuts
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

Only two direct SwiftPM dependencies — see `Package.swift`. Everything else is
an Apple framework or the embedded Python runtime.

**SwiftPM:**
- **KeyboardShortcuts** (sindresorhus, 3.x) - Global hotkeys and the recorder UI
- **WhisperKit** via **argmax-oss-swift** (1.x) - CoreML local transcription

**Apple frameworks:**
- **SwiftUI + AppKit** - UI and menu bar integration
- **AVFoundation** - Audio recording and file duration
- **Accelerate (vDSP)** - FFT and level metering for the waveform
- **SwiftData** - Transcription history persistence
- **CryptoKit** - SHA-256 for model and `uv` binary integrity checks

**Embedded Python** (uv-managed, see ADR 0002): `parakeet-mlx` for Parakeet
transcription and `mlx-lm` for semantic correction.

There is **no Swift HTTP client** — `URLSession` appears nowhere in `Sources/`.
Model downloads go through WhisperKit and, for MLX/Parakeet, `huggingface_hub`
in the Python subprocess. There is likewise no Keychain usage: this fork removed
the cloud providers (ADR 0005), so there are no API keys to store.

## Code Patterns

- Swift 5.9+ targeting macOS 14+
- Use `@MainActor` for UI components
- Prefer `guard let` over force unwrapping
- Use `[weak self]` in closures to prevent retain cycles
- Swift Concurrency (`async`/`await`) for async flows
- Keep functions ≤ 40 lines
