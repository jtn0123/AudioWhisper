# AudioWhisper compared with Superwhisper, 2026-10-18

AudioWhisper has the core local dictation building blocks. The clearest product
gaps are reusable workflows, automatic app selection, richer context, history
reprocessing and meetings. Reliability and actual device acceptance remain more
urgent than adding every competitor feature. The work is tracked with stable
IDs in the [product roadmap](../product-roadmap.md).

This is a bounded REA MCP static investigation plus current official
documentation and AudioWhisper source review. It is not a complete decompilation
or a matched runtime/accuracy benchmark.

## What was actually inspected

- AudioWhisper source at `e494a0fa54235849f889a7d9758bdd7091042cb8`.
- Fresh vendor download from
  `https://builds.superwhisper.com/latest/superwhisper.dmg`, reached from the
  official Superwhisper download link. Its shipped plist reports **3.0.1**.
- Existing **REA 6.5.0**, connected through an actual stdio MCP session using its
  public launcher and MCP initialize/tools-list/tools-call protocol. The agent's
  native catalog lacked REA, but its version-pinned package was already cached
  and registered for Claude Code. No client configuration was changed.
- REA `inspect_artifact`, `inspect_plist`, `inspect_signature`, `inspect_macho`,
  retained analysis views and `demangle_swift`. Complete native/application
  Evidence bundles and individual responses were retained locally.

DMG SHA-256:
`87f9c9a5ef21fff1b293ca4e6e1de15af72720ccb2fd9ce92ab289ceb1099df2`.
Main executable SHA-256:
`6e58b3da398c104c9015079d2e6c6611e94afbff02d127d25b0cb10507767e4c`.
It is a universal x86_64/arm64 executable; the Mach-O inspection selected arm64.

REA could inventory the DMG but its extraction operation rejected that format.
The bundle was therefore copied with ordinary macOS tools from an owned,
read-only mount, which was detached afterward. That extraction is shell evidence,
not a successful REA extraction. The downloaded app was not launched and existing
user history was not read.

## Shipped-artifact findings

The [curated evidence index](superwhisper-2026-10-18-evidence.json) retains full
REA Evidence IDs and hashes. Its filtered observations are:

1. **Several local engine components are packaged.** The artifact inventory
   contains `ArgmaxSDK`, `WhisperNative`, `SuperDiarizeNative`, `Cmlx`, `libllama`
   and related frameworks. Packaging establishes their presence, not the backend
   selected for any particular user session.
2. **The executable references streaming, vocabulary and diarization APIs.**
   REA's Mach-O imports and Swift demangler identify
   `ArgmaxSDK.WhisperKitPro.makeStreamSession`,
   `WhisperKitPro.setCustomVocabulary` and `SortformerDiarizationOptions` metadata.
   This supports investigating those integration boundaries; it does not recover
   their call paths, runtime settings, accuracy or source code. It is not proof
   that Superwhisper's local draft algorithm matches AudioWhisper's rolling loop.
3. **Meeting/context integration has shipped platform hooks.** Mach-O
   dependencies include ScreenCaptureKit and EventKit. The plist declares
   microphone, Accessibility, Apple Events and calendar use, and registers the
   `superwhisper` URL scheme. These are static declarations, not observations of
   actual recording, calendar reads or successful paste.
4. **Distribution has a different maturity boundary.** Signature inspection
   reports Developer ID Application authority, team `XDP69BYUP9` and hardened
   runtime. The plist declares Sparkle's appcast. REA explicitly does not establish
   trust/notarization acceptance from this signature-byte snapshot. AudioWhisper's
   current acceptance evidence remains development signing, not a public release.

Procedure search returned `provider_unavailable`: Hopper's launcher was absent,
Ghidra was not configured, and IDA had no MCP configuration. The Ghidra route also
reported that this universal input would first need thinning to a selected
slice. No pseudocode, control-flow trace or native UI behavior was recovered.
These are unresolved investigation limits, tracked as RE1.

## Product comparison

“Documented” below means current vendor documentation, not behavior observed in
this static pass. Missing AudioWhisper paths are bounded source-review findings.

| Area | AudioWhisper now | Superwhisper documentation | Assessment |
|---|---|---|---|
| Local dictation and cleanup | Whisper/Parakeet, local cleanup, vocabulary/replacements, cursor-aware formatting and Smart Paste | Local voice models and offline formatting are supported, with model/mode restrictions. [Introduction](https://superwhisper.com/docs/get-started/introduction) | Both cover local dictation. Our simpler local-only policy is useful positioning, not exclusive privacy capability. |
| Saved workflows | One global configuration captured per session; fixed conservative cleanup policy | Named modes pair voice/AI settings and custom instructions. [Modes](https://superwhisper.com/docs/modes/modes) | P1 is a clear everyday workflow gap. |
| App-based switching | App identity is captured for delivery/history; it does not select a mode/model/prompt | App/site rules, shortcuts and deep links select modes. [Switching modes](https://superwhisper.com/docs/modes/switching-modes) | P2 follows saved presets. |
| Context-aware rewriting | Nearby cursor text supports final spacing/capitalization. Selected text and clipboard contents are not model inputs | Selected text, clipboard and application context are captured at different stages. [Context](https://superwhisper.com/docs/common-issues/context) | P3 adds explicit context scope and timing; current cursor formatting should remain credited. |
| Live words | Optional local Parakeet drafts over the latest 12 seconds, one second between inferences; final full-recording recognition after Stop | On-screen Realtime supports selected local/cloud models. [Realtime](https://superwhisper.com/docs/common-issues/realtime) | Both display live words. Stability, commit semantics and relative latency were not compared; no confirmed streaming-equivalence or speed claim. |
| History | Search/copy/export/original comparison; no retained successful capture audio or saved-history reprocessing route | History supports reprocessing past dictations. [History](https://superwhisper.com/docs/get-started/history) | P4 needs an explicit retention decision before audio reruns. |
| Meetings | Microphone recording and file import; no system-audio meeting/diarization flow found | Meeting recording, notes and offline speaker labels are documented. [Meetings](https://superwhisper.com/meetings) | P5 is a larger separate feature, not a small recorder-polish task. |
| Automation | Recording diagnostics CLI and private ML subprocess RPC | Public CLI and MCP integration. [CLI/MCP](https://superwhisper.com/docs/get-started/cli) | P6 is a separate public interface. Private JSON-RPC is not MCP. |

Two previous comparison shortcuts need correcting. Offline processing is not
unique to AudioWhisper: Superwhisper documents offline voice, formatting and
meeting options. Also, AudioWhisper already has live drafts; “no live
transcription” would be inaccurate. Neither this static inspection nor vendor
copy establishes that one app is faster or more accurate.

## AudioWhisper source anchors

- Global session configuration and final recording path:
  `Sources/Rebuild/RebuildSession.swift:162`, `:204`.
- Fixed cleanup instructions: `Sources/Services/CorrectionPrompt.swift:1` and
  `Sources/Rebuild/RebuildWritingView.swift:56`.
- Correction receives app identity but uses the same policy:
  `Sources/Services/SemanticCorrectionService.swift:69`.
- Cursor access and final formatting:
  `Sources/Managers/FocusedTextAccess.swift:98`,
  `Sources/Rebuild/RebuildPasteDelivery.swift:39` and
  `Sources/Services/Formatting/CursorContextFormatter.swift:10`.
- Existing vocabulary: `Sources/Services/Formatting/CustomVocabulary.swift:3`.
- Preview cadence and draft semantics:
  `Sources/Rebuild/RebuildLivePreview.swift:24`, `:86` and
  `Sources/Services/Audio/RecordingPreviewAudio.swift:7`.
- History storage and actions: `Sources/Models/TranscriptionRecord.swift:9`,
  `Sources/Rebuild/RebuildLibraryView.swift:231` and
  `Sources/Rebuild/RebuildLibraryState.swift:37`.
- Microphone capture and file import:
  `Sources/Services/Audio/AudioEngineRecorder+Startup.swift:15` and
  `Sources/Rebuild/RebuildApp.swift:122`.
- Current executable interface: `Sources/App/AudioWhisperEntryPoint.swift:6`.

## Next evidence to collect

Close R1–R4 in the roadmap. For a deeper RE pass, supply an available native
provider, then trace a named question such as mode selection, context capture or
draft finalization. Compare the same speech, local model class, hardware and
cleanup policy before judging speed/accuracy. This report supplies no percentage
parity score because the required matched runtime evidence does not exist.
