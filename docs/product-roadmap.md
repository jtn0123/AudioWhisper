# Product and release tracker

Last checked: 2026-10-18 against merged master `9634ed5`. [Current graded comparison](../.Codex/ui-ux-grade-report.md).
Keep the IDs stable. Mark an item complete only when its acceptance evidence is
linked here. Proposed product work is not an implementation commitment.

## Current work

| ID | Priority | Status | Work and completion criteria |
|---|---|---|---|
| R1 | First | Open, isolated to older hosted environment | **Whisper recognition compatibility.** [Draft PR #49](https://github.com/jtn0123/AudioWhisper/pull/49) strengthens speech assertions and isolates encoder inference. With identical Xcode 26.3 builds and matching model files, hosted macOS 15 still fails while macOS 26 passes fresh/restored Whisper and all nine real-engine fixtures. See [investigation](https://github.com/jtn0123/AudioWhisper/blob/2ec5800/docs/whisper-hosted-investigation.md). Physical macOS 15 scope and a production fix remain unresolved. Preserve Parakeet/MLX passes; green PR checks are not recognition acceptance. |
| R2 | First | Device verification pending | **Daily dictation on actual hardware.** Identify the tested packaged commit and microphone devices. Exercise permission denial/recovery, first/last words, repeated start/stop/cancel and physical hold/release. Test built-in/USB/AirPods, input change/unplug, sleep/wake, native/browser text fields, full-screen Spaces and multiple displays. Verify exactly-once paste to the intended field, clipboard fallback and normal Preferences placement. Existing renders and audio fixtures do not close this item. |
| R3 | Next | [PR #45](https://github.com/jtn0123/AudioWhisper/pull/45) open; all 11 checks pass | **Optional warm microphone.** Five reproduced lifecycle cases are fixed and the full 3,244-test suite passes. First-word/pre-roll, ranked/default input switching/unplug, Bluetooth exclusion and sleep/wake need hardware acceptance. Confirm release on disable/quit and safe ordinary-start fallback. The three manual checks remain unchecked. |
| R4 | Before distribution | Acceptance pending | **Accessibility and release packaging.** Complete VoiceOver and keyboard-only setup, recording/cancel/retry, model install, vocabulary, library and Preferences journeys; verify focus, status/error announcements and Reduce Motion. For public distribution, validate the universal Developer ID build, accepted notarization/stapling, Gatekeeper on a clean quarantined install, and permission/signature behavior across relaunch and update. |

## Product gaps to consider after reliability

The [fresh comparison and REA evidence](research/superwhisper-2026-10-18.md)
distinguish documented behavior, shipped-artifact observations and unknowns.

| ID | Proposed increment | Bounded first outcome |
|---|---|---|
| P1 | Named modes/presets | First increment merged in [PR #50](https://github.com/jtn0123/AudioWhisper/pull/50), master `9634ed5`: save/select/remove local setups for voice/cleanup models, vocabulary and formatting, with Record picker and busy-state protection. Language, task instructions, edit/rename/duplicate/export remain. UI C5 tracks identical-settings name ambiguity. |
| P2 | Per-app activation | Select a preset from an explicit app rule captured at recording start; keep manual override predictable. Website rules can follow separately. Depends on P1. |
| P3 | Opt-in context | Let a preset use explicitly selected text or copied text with visible scope and a recorded capture time. Verify behavior when focus changes. Current cursor-aware spacing remains supported. |
| P4 | Reprocess history | Choose another local model/preset without destroying the original result. Decide separately whether audio retention is optional and how deletion works; current successful capture audio is removed. |
| P5 | Meeting workflow | Treat system-audio capture, speaker/timestamp segments and summaries as a separate larger feature. Define long-recording recovery and retention before implementation. |
| P6 | Public automation | Add a bounded CLI/deep-link/MCP interface if desired. The current diagnostic CLI and private ML JSON-RPC are not a public integration. |

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

[2026-10-18 comparison](../.Codex/ui-ux-grade-report.md): competitive product judgment B-, interface B, workflow breadth C+. Highest-value feature increments remain P2 and P1; UI H1 delivery truth and D1 session announcements are bounded polish fixes. These grades do not claim matched accuracy/speed or complete device/release acceptance.
