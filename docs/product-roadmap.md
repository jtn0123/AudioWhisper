# Product and release tracker

Last checked: 2026-10-19. Merged baseline: `9634ed5`; product increments are in [draft PR #51](https://github.com/jtn0123/AudioWhisper/pull/51). [Current graded comparison](../.Codex/ui-ux-grade-report.md).
Keep the IDs stable. Mark an item complete only when its acceptance evidence is
linked here. On October 18 the user authorized all increments below ("Let's do
all smartly"). Keep hardware and distribution gates open until observed.

## Current work

| ID | Priority | Status | Work and completion criteria |
|---|---|---|---|
| R1 | First | Production candidate passes hosted macOS 15; qualification in progress | **Whisper recognition compatibility.** [PR #49](https://github.com/jtn0123/AudioWhisper/pull/49) now has a bounded production fix for the exact affected Base encoder on Apple Silicon macOS 15. The actual service/factory passes [hosted macOS 15](https://github.com/jtn0123/AudioWhisper/actions/runs/39234333345) at `5daae51`. Seven cache/policy/cancellation tests and three real recognition/persistence tests pass locally; newer package-only/source-snapshot safeguards are committed at `86402ea`. Fresh-download macOS 26, current-head hosted acceptance, restored prepared-cache reuse, complete Parakeet/MLX preservation and physical macOS 15 remain open. PR CI is separate from recognition acceptance. |
| R2 | First | Device verification pending | **Daily dictation on actual hardware.** Identify the tested packaged commit and microphone devices. Exercise permission denial/recovery, first/last words, repeated start/stop/cancel and physical hold/release. Test built-in/USB/AirPods, input change/unplug, sleep/wake, native/browser text fields, full-screen Spaces and multiple displays. Verify exactly-once paste to the intended field, clipboard fallback and normal Preferences placement. Existing renders and audio fixtures do not close this item. |
| R3 | Next | [PR #45](https://github.com/jtn0123/AudioWhisper/pull/45) open; all 11 checks pass | **Optional warm microphone.** Five reproduced lifecycle cases are fixed and the full 3,244-test suite passes. First-word/pre-roll, ranked/default input switching/unplug, Bluetooth exclusion and sleep/wake need hardware acceptance. Confirm release on disable/quit and safe ordinary-start fallback. The three manual checks remain unchecked. |
| R4 | Before distribution | Acceptance pending | **Accessibility and release packaging.** Complete VoiceOver and keyboard-only setup, recording/cancel/retry, model install, vocabulary, library and Preferences journeys; verify focus, status/error announcements and Reduce Motion. For public distribution, validate the universal Developer ID build, accepted notarization/stapling, Gatekeeper on a clean quarantined install, and permission/signature behavior across relaunch and update. |

## Authorized product increments

The [fresh comparison and REA evidence](research/superwhisper-2026-10-18.md)
distinguish documented behavior, shipped-artifact observations and unknowns.

| ID | Increment | Current implementation and remaining boundary |
|---|---|---|
| P1 | Named modes/presets | Draft #51 adds language, conservative cleanup/rewrite tasks, bounded instructions, edit/rename/duplicate/import/export and persistent selected identity. Legacy migration, archive limits/consent reset, rewrite integrity and editor controls are tested. Native and release acceptance remain open. |
| P2 | Per-app activation | Exact bundle-ID rules resolve once before recording, with persistent manual override and explicit Automatic selection. A different resolved voice model gets its own setup checks before capture. Website rules remain a later increment. |
| P3 | Opt-in context | Selected text or clipboard is captured once with visible source/time/truncation and retained for retry. Context is reference data, excluded from ordinary history/import/automation. Selected-reference delivery is copy-only to protect the selected source. This is bounded reference support; arbitrary voice editing of selected text remains outside this increment. |
| P4 | Reprocess history | Cleanup-only reruns preview from the stored original; explicit save retains ten versions on the same record without adding usage. No ordinary dictation audio retention or retranscription is introduced. SwiftData persistence/deletion and UI controls are tested. |
| P5 | Meeting workflow | Draft #51 implements separate microphone/system capture, timestamped chunks, interrupted-manifest recovery, local Whisper segments, optional estimated speaker clusters and local notes. Sources are retained on failure and deleted only after success unless Keep audio is chosen. Processing/retention/recovery tests pass; actual system capture, devices, permission recovery, echo and long-session acceptance remain open. |
| P6 | Public automation | Bounded installed-model file CLI, navigation-only deep links and stdio MCP status/transcribe are implemented. Scope checks, framing/lifecycle, cancellation/EOF cleanup, strict runtime policy and real executable transport are tested. No automation microphone/context/clipboard/history/paste effects. |

Live drafts already exist. Compare actual cadence, stability, long-dictation
behavior and Stop-to-paste latency before choosing a streaming redesign. No
matched Superwhisper performance comparison has been run.

## Completed in this pass

- [PR #46](https://github.com/jtn0123/AudioWhisper/pull/46), merged `530893f`:
  recorder/Preferences polish, optional Parakeet drafts, independent delivery and
  history saving, focus-safe paste, practice, vocabulary and timing diagnostics.
- [PR #47](https://github.com/jtn0123/AudioWhisper/pull/47), merged `e494a0f`:
  verified analyzer-result caching and live progress/profiles. The hosted
  identical-input rerun took 33 seconds after a 32m23s cold job. Swift edits still
  require full analysis. See [CI analysis](ci-analysis.md).

## Investigation follow-up

**RE1 — native function tracing:** REA MCP 6.5.0 connected and inspected the
Superwhisper 3.0.1 artifact. Procedure search reported `provider_unavailable`:
Ghidra, Hopper and IDA are not configured/available. Static inventory, signature,
plist, Mach-O imports and Swift demangling succeeded. Function-level behavior,
matched runtime UX and relative speed remain unverified. Use an existing
configured decompiler before closing RE1; no engine installation was performed.

Historical implementation evidence remains in
[daily dictation](../.Codex/dictation-flow-2026-10-16/README.md) and
[recorder polish](../.Codex/recorder-polish-2026-10-16/README.md).

## Current regrade

[2026-10-18 comparison](../.Codex/ui-ux-grade-report.md): competitive product judgment B-, interface B, workflow breadth C+. Draft #51 implements the six bounded increments plus UI H1, D1 and C5. The full 3,253-test Swift run passes; local new Swift-code coverage is 80.77%; hosted coverage/analysis and native acceptance remain in progress. Original grades are retained pending native evidence and acceptance. These grades do not claim matched accuracy/speed or complete device/release acceptance.
