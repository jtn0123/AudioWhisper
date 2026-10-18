# Product and release tracker

Last checked: 2026-10-18 against `e494a0fa54235849f889a7d9758bdd7091042cb8`.
Keep the IDs stable. Mark an item complete only when its acceptance evidence is
linked here. Proposed product work is not an implementation commitment.

## Current work

| ID | Priority | Status | Work and completion criteria |
|---|---|---|---|
| R1 | First | Open | **Whisper recognition on the hosted runner.** [Nightly 39125168286](https://github.com/jtn0123/AudioWhisper/actions/runs/39125168286) still returns `>>` on cold/warm calls and the CPU-only diagnostic. Parakeet and MLX pass. Close after unchanged meaningful-speech assertions pass with both fresh and restored model caches. Loading parity must check expected speech content as well as equality: two equal `>>` results currently pass that parity test. Preserve the other engine passes. |
| R2 | First | Device verification pending | **Daily dictation on actual hardware.** Identify the tested packaged commit and microphone devices. Exercise permission denial/recovery, first/last words, repeated start/stop/cancel and physical hold/release. Test built-in/USB/AirPods, input change/unplug, sleep/wake, native/browser text fields, full-screen Spaces and multiple displays. Verify exactly-once paste to the intended field, clipboard fallback and normal Preferences placement. Existing renders and audio fixtures do not close this item. |
| R3 | Next | [PR #45](https://github.com/jtn0123/AudioWhisper/pull/45) open | **Optional warm microphone.** Review against current master and pass current-head CI. Verify first-word/pre-roll capture, ranked/default microphone change/unplug and sleep/wake on hardware. Confirm off by default, release on disable/quit, Bluetooth exclusion and safe ordinary-start fallback for stale/unavailable input. The PR's three manual checks remain unchecked. |
| R4 | Before distribution | Acceptance pending | **Accessibility and release packaging.** Complete VoiceOver and keyboard-only setup, recording/cancel/retry, model install, vocabulary, library and Preferences journeys; verify focus, status/error announcements and Reduce Motion. For public distribution, validate the universal Developer ID build, accepted notarization/stapling, Gatekeeper on a clean quarantined install, and permission/signature behavior across relaunch and update. |

## Product gaps to consider after reliability

The [fresh comparison and REA evidence](research/superwhisper-2026-10-18.md)
distinguish documented behavior, shipped-artifact observations and unknowns.

| ID | Proposed increment | Bounded first outcome |
|---|---|---|
| P1 | Named modes/presets | Save, duplicate, select and export a named local configuration covering voice model, language, cleanup/instructions and formatting. Preserve a simple default. |
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
