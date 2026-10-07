# Next-five batch: D3, B1, C1, D2, G1

Executed 2026-10-07 on `rebuild/native-v2`, in PR #40. The original [post-PR audit](../grade-report-b64f707.md) and failed headless probe remain unchanged. This batch implements its saved IDs; it is not a new whole-codebase audit.

## Changes and meaningful checks

| ID | User-visible result | Verification |
|---|---|---|
| D3 | Real Record, setup, Library, Writing and Preferences controls have automated behavioral fixtures. Startup ordering, native menu commands, held-record ownership and actual window policies are covered. | ViewInspector is pinned to 0.10.5 only in the test target. Fixtures inspect visible labels, disabled states, bindings and real callbacks; they never grant OS permissions or present test windows. Local full suite exits 0, 3,047 discovered cases; optional physical/model/snapshot cases can skip. Hosted Sonar passes its unchanged 80% new-code gate at 80.5%. |
| B1 | Successful imports and retries retain audio length in history and usage; live capture keeps its measured duration. | Regression failed with nil duration/zero usage before the fix. [Native import](import-duration.json) now saves exactly 2.67075 seconds and adds the same amount to usage, with correct text, unchanged source WAV and valid signature. |
| C1 | Preferences refreshes microphone choices on connection/disconnection, app activation and permission refresh. An unavailable saved microphone stays selected and explained. | Notification/authorization transition and actual Picker-row fixtures pass without requesting access. Saved UIDs are preserved. Physical hotplug acceptance remains part of D1. |
| D2 | Real fixtures explicitly exercise offered Parakeet v2/v3, Spanish v3 and Qwen3.5/3.8 cleanup, including warm reuse and switching. | [Six actual inference tests](real-models.txt) pass at `3312fd3`, in 28.0 seconds on the 48 GB Apple Silicon Mac. No inference fallback or mock counts as success. `scripts/test-current-models.sh` repeats the full set; larger models require at least 32 GB. Hosted nightly is explicitly the lightweight subset. |
| G1 | History cleanup and usage scans run in a background SwiftData model actor, with cancellation and guards against stale totals. | Actual multi-page SwiftData aggregation, cancellation, retention boundary/counts and revision races pass. A pre-cancelled fallback previously consumed 51 records; now it consumes none. No UI freeze or large-library timing improvement is claimed from these functional fixtures. |

Additional regressions discovered by the new fixtures: an old hold-key release could finish a replacement recording, and the newly constructed recorder window could start at 0x0. The capture-identity guard and explicit 380x230 window size pass their regressions. These are programmatic tests, not physical key proof.

The first combined real-model run failed: the older Qwen fixture left its shared Python worker running. Foundation's serial AsyncBytes reader then blocked the independent Parakeet worker. [Failing run](real-models-before.txt) is retained. The correction fixture now owns and shuts down its worker; all six tests pass together. No production model selection or default was changed.

## Coverage and hosted checks

- Tested production source/package: `5c5a13d2271f555a0e6582f61b902dc617fc9d92`. `3312fd35be5b83ee2c6345190dc5b168854f4a4c` changes only the correction fixture cleanup; production Sources are identical.
- Full local Sources-only line coverage: **51.01%**, 18,853/36,956 lines, 198 source files, passing the unchanged 40% floor. Pinned SwiftLint 0.65.0: zero violations across 445 Swift files.
- [Local changed Swift-line estimate](changed-swift-coverage.json): **80.31%**, 3,761/4,683 changed executable Source lines. [Hosted artifact intersection](hosted-changed-swift-coverage.json): **79.49%**, 3,724/4,685. Toolchain/hosted-test differences make these estimates distinct; neither substitutes for Sonar's combined new-code metric.
- The established **80% Sonar new-code gate remains intact**, with no new exclusions or skipped existing tests. [Official Sonar](sonar-status.json) passes at **80.5%**, with A reliability/security/maintainability ratings, zero new duplication and 100% reviewed hotspots. [Analysis identity](sonar-analysis.json) confirms source `5c5a13d`; the earlier failed 45.8% result belongs to `6ac9b7b`, before this batch.
- [5c5a13d PR CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37689278997): build/tests, lint and Sonar scan passed; analyzer and packaged smoke still running. [3312fd3 PR CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37690111618) is the test-fixture follow-up. Live checks remain on [PR #40](https://github.com/jtn0123/AudioWhisper/pull/40/checks).

## Packaged native acceptance

Fresh signed package, macOS 26.6.2 QA guest, source `5c5a13d`:

- [Ten actual shortcut/start/native Cancel cycles](native-recording.json), followed by real Stop/transcription and exactly one app-generated Smart Paste into disposable TextEdit. The HUD stayed contained and the destination retained focus.
- [All five pages in light and dark](screen-capture.json), contained at the 870x620 minimum. Selected/focused navigation is captured in the report. Screenshots are in this directory; Record, Library, Models, Writing and Preferences were visually reviewed.
- [Native import duration](import-duration.json), [result screenshot](import-duration-result.png).
- Strict complete-bundle signature remains valid after inference/import; no new guest consent was needed.

[Host install](host-install.json) on macOS 27.2 preserves the persistent signing requirement, all 19 checked preference values and history, with SQLite integrity `ok` and exactly one running rebuild. Installed executable SHA-256 is `f75d1f81665ffe2ae32c22367cd6b4f49d033aacd0a4ed8d032121dc685a3f2a`, identical to the accepted guest package. No consent reset or host microphone/Accessibility test was performed.

Limits: VM key events are synthetic, audio uses a virtual microphone and public speech fixture, and this is a development-signed package. Physical hold modifiers, device interruption/sleep recovery, a complete VoiceOver walk-through and notarized public distribution remain open. Earlier fullscreen acceptance retains its original source provenance; it was not repeated in this batch. PR #40 remains open and unmerged; nothing was publicly released.
