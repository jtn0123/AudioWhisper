# UI/UX Grade Report

**Project:** AudioWhisper, compared with Superwhisper 3.0.1
**Audited:** 2026-10-18
**Stack:** Native macOS SwiftUI/AppKit, local Whisper/Parakeet, local writing cleanup.
**Source:** merged master `9634ed53eb0c774f433186177070c96c896a847c`.
**Runtime evidence:** Fresh native offscreen fixture renders plus current source, tests and hosted CI. Physical capture/paste and competitor runtime were not repeated.
**Artifacts:** `.Codex/ui-ux-audit/2026-10-18-regrade/` ([provenance](ui-ux-audit/2026-10-18-regrade/README.md)).
**Previous report:** [2026-10-04](ui-ux-grade-report-2026-10-04.md). This explicit regrade resets UI IDs; use UI C1/H1 etc. Roadmap P1-P6 and R1-R4 retain their meaning.

## Implementation follow-up — 2026-10-19

The original audit and grades below remain an October 18 baseline. All six bounded
product increments were authorized and implemented in [draft PR #51](https://github.com/jtn0123/AudioWhisper/pull/51).
The [live tracker](../docs/product-roadmap.md) and [workflow contracts](../docs/dictation-workflows.md)
state current scope and acceptance; implementation alone does not raise these grades.

| Audit IDs | Current execution status |
|---|---|
| C1, C2, C4, C5, H1 | Software implemented with focused regression/integration tests: complete mode editing, app rules, original-preserving writing versions, selected UUID identity and truthful delivery/restoration. Native verification is in progress. |
| C3 | Bounded reference context implemented with consent, one-time capture, visible scope/truncation and copy-only selected-reference delivery. General voice editing of selected text is not claimed. |
| D1 | Session-owned coarse announcements implemented and tested, including Express Mode. Actual VoiceOver acceptance remains R4. |
| H2 / R1 | Production Base compatibility candidate now passes the previously failing hosted macOS 15 environment. Current-head, fresh/restored derived-cache and physical acceptance remain in progress under PR #49. |
| G1, I1, I2 | Matched competitor performance, physical microphone/delivery and public-release acceptance remain open. |

## Summary

**Competitive product judgment: B- overall. Interface: B; workflow breadth relative to Superwhisper: C+.**
AudioWhisper is a capable focused local dictation app. The largest difference is workflow depth and release confidence, rather than a need to redraw the whole interface. These are evidence-bounded judgments, not measured accuracy scores or percentage parity.

The UI/UX grade below remains B, provisional where device/performance acceptance is missing. The broader B- competitive judgment additionally includes missing per-app/context/history workflows and the unresolved release qualification. Superwhisper is the feature benchmark; its internals, security and actual accuracy are not being assigned an untested A grade.

| ID | Category | Grade | Items |
|---|---|---|---|
| A | Visual Design & Theme Cohesion | B | 0 |
| B | Layout, Information Architecture & Navigation | B | 0 |
| C | Interaction Design & Workflow Quality | B- | 5 |
| D | Accessibility & Inclusive UX | B- provisional | 1 |
| E | Responsive & Cross-State Experience | B provisional | 0 |
| F | Frontend Code & Design System Health | B+ | 0 |
| G | UI Performance & Asset Efficiency | B provisional | 1 |
| H | Data Linkages & State Reliability | B | 2 |
| I | Polish, Delight & Product Feel | B- | 2 |
| **Overall UI/UX** | | **B, provisional** | **11** |

**Top 5 fixes:** H2/R1 (recognition compatibility), H1 (truthful delivery status), D1 (session announcements), C2/P2 (app rules), C1/P1 (useful writing modes). R2/R3 physical acceptance is a parallel gate; cosmetic changes cannot substitute for it.

## Evidence Limits

- Current master CI and CodeQL both pass. #50 is merged; saved modes receive full credit. #45 warm microphone is open, #49 recognition diagnostics is draft; neither is credited as merged product behavior.
- Fresh previews cover real SwiftUI views with fixture settings, fake capture/transcription effects and a fake history provider. The environment reports no active display; offscreen views still render, but some frames omit cached layers/clip headers. These are not graded as application window-placement defects. Native VoiceOver, physical hold/mic routing, Spaces and complete normal-window interactions remain unverified.
- Existing #50 validation passed 3,211 tests with 53 skips and zero failures; the source tree matches the resulting merge. This audit's preview fixture passes one test; it is not another full-suite run.
- Real-engine successes are from diagnostic PR #49 at `dc7e1dd`, not a new current-master recording test: [full nine-engine fixtures](https://github.com/jtn0123/AudioWhisper/actions/runs/39161164830), [restored-cache Whisper](https://github.com/jtn0123/AudioWhisper/actions/runs/39161787961). Its production inference path is unchanged; saved-mode changes do not establish hardware or release acceptance.
- Superwhisper claims below come from official documentation and the [3.0.1 changelog](https://superwhisper.com/changelog), checked today. No new competitor runtime or decompilation was performed. Earlier REA static findings remain in [the earlier comparison](../docs/research/superwhisper-2026-10-18.md), with their provider limits intact.
- No matched local-model accuracy, first-word, latency, long-dictation or battery benchmark exists. No claim that either app is faster or more accurate is justified by this report.

## What is already competitive

Local Whisper/Parakeet recognition, local conservative cleanup, vocabulary/replacements, filler removal, spoken punctuation, cursor-aware insertion, Smart Paste with fallback, optional live Parakeet drafts, text history/search/export, original-result comparison, file import, failure retry, practice, configurable hotkeys and hold-to-record all exist. Saved modes now store/select/remove processing setups and protect active sessions.

Offline processing is a useful policy, not an exclusive advantage: Superwhisper also documents local transcription and offline formatting options with model/mode restrictions. See its [introduction](https://superwhisper.com/docs/get-started/introduction). Cloud/BYOK models and non-Mac platforms widen its scope; they are optional product-direction choices for AudioWhisper, not requirements to abandon local-only processing.

## Product gaps against Superwhisper

| Roadmap ID | AudioWhisper now | Superwhisper documented benchmark | Missing increment | Priority / size |
|---|---|---|---|---|
| P1 | Named settings snapshots are merged; manual save/select/remove | Per-mode language/model/AI instructions and purpose-specific tone | Language and task instructions; edit/rename/duplicate/export; fix identical-mode label | Next / M |
| P2 | App identity is used for paste/history | Automatic app/site selection, mode shortcuts and deep links | App-to-mode rules resolved at session start, then websites | Next / M |
| P3 | Cursor-aware insertion only | Selected-text, clipboard and application context | Explicit opt-in captured context for rewriting | After P1/P2 / M-L |
| P4 | Text history, original comparison, export and current-failure retry | Reprocess a prior dictation through another mode | Cleanup-only history reruns first; optional retained audio separately | After modes / M-L |
| P5 | Microphone capture and external audio import | System audio, live speakers and meeting summaries | A separate meeting capture/segments/summary workflow | Later / L |
| P6 | Diagnostic CLI and private subprocess RPC | Public app-control/transcribe CLI and history/vocabulary MCP | A bounded documented public interface | Later / M |

Official benchmark sources: [Modes](https://superwhisper.com/docs/modes/modes), [Custom instructions](https://superwhisper.com/docs/modes/custom), [Switching](https://superwhisper.com/docs/modes/switching-modes), [Context](https://superwhisper.com/docs/common-issues/context), [History](https://superwhisper.com/docs/get-started/history), [Meetings](https://superwhisper.com/meetings), [CLI/MCP](https://superwhisper.com/docs/get-started/cli).

Both apps can show live words: AudioWhisper already has rolling local Parakeet drafts. Superwhisper documents selected local/cloud Realtime models. The missing evidence is stability, whole-session behavior and latency, not the existence of live text. [Realtime documentation](https://superwhisper.com/docs/common-issues/realtime).

## A — Visual Design & Theme Cohesion — B

The current Record and Preferences renders show a coherent slate/teal utility design, clear primary action and consistent native typography. Semantic light/dark/Increase Contrast tokens live in `Sources/Rebuild/RebuildDesign.swift:8-104`. Keep that identity; no evidence supports a wholesale cosmetic rewrite.

## B — Layout, Information Architecture & Navigation — B

Five clear destinations, Cmd1-Cmd5, setup next steps and grouped settings make the app navigable (`RebuildWorkspace.swift:90-171`). Saved modes are now visible on Record and in Preferences. A dedicated editing flow can grow under C1 rather than adding another navigation layer prematurely.

## C — Interaction Design & Workflow Quality — B-

Core record/cancel/retry/import actions and active-job locks are sound on source/test review. Named modes improve daily reuse, but task-specific instructions, automatic app selection and later history/context workflows remain behind the documented benchmark. C5 is a concrete small feedback defect; C1-C4 are missing workflows, not claims that existing recording is broken.

#### C1 — Finish useful modes rather than only saving settings
- **Where:** Sources/Models/SavedDictationMode.swift:5; Sources/Rebuild/RebuildSavedModesView.swift:43; Sources/Services/SemanticCorrectionService.swift:109; Sources/Services/LocalWhisperService.swift:206
- **Evidence:** P1 now saves/selects/removes named processing snapshots. The schema has no explicit language or custom instructions, and the active cleanup service supplies one fixed prompt.
- **Layman's term:** A Work preset remembers your switches, but cannot yet ask for a different tone or output format.
- **What's wrong:** Mode controls do not yet express task-specific writing workflows. Lower-level legacy prompt-file support is bypassed by the active explicit prompt.
- **Impact:** Moderate — limits repeated task-specific use.
- **Significance:** High
- **Difficulty:** M
- **Fix:** Add explicit language and bounded local writing instructions to the stored mode and session snapshot, then edit/rename/duplicate/import/export. Keep conservative cleanup available as the default.
- **Grade lift:** B- → B+ for task-specific workflows

#### C2 — Choose the right mode for the active app
- **Where:** Sources/Rebuild/RebuildSession.swift:204; Sources/Rebuild/RebuildPasteDestination.swift:26
- **Evidence:** Session start captures a paste destination but snapshots global settings directly. No app-to-mode rule is consulted. This maps to P2.
- **Layman's term:** Mail and Slack currently use whichever setup you last picked.
- **What's wrong:** App identity helps delivery and history but does not select a writing workflow.
- **Impact:** Moderate — repeated manual switching adds everyday friction.
- **Significance:** High
- **Difficulty:** M
- **Fix:** Add explicit bundle-ID-to-mode rules resolved once at recording start, with clear manual override. Add website rules separately.
- **Grade lift:** B- → B+ for frequent app switching

#### C3 — Add explicit, scoped rewriting context
- **Where:** Sources/Managers/FocusedTextAccess.swift:98; Sources/Rebuild/RebuildPasteDelivery.swift:39; Sources/Rebuild/RebuildSession.swift:213
- **Evidence:** Existing cursor context adjusts final spacing/capitalization. Selected text, clipboard content and window content are not inputs to the active cleanup configuration. This maps to P3.
- **Layman's term:** The app can insert text neatly, but cannot yet rewrite a highlighted paragraph using your voice.
- **What's wrong:** Insertion context and model context serve different jobs; richer rewriting needs explicit capture and scope.
- **Impact:** Moderate — advanced voice editing is missing.
- **Significance:** Medium
- **Difficulty:** M
- **Fix:** Start with opt-in selected text or clipboard context per mode, visible capture time/scope, and a preview. Keep app changes from silently changing the captured context.
- **Grade lift:** B- → B+ for contextual editing

#### C4 — Reprocess saved text before adding retained audio
- **Where:** Sources/Models/TranscriptionRecord.swift:9; Sources/Rebuild/RebuildLibraryView.swift:231; Sources/Rebuild/RebuildSession.swift:263
- **Evidence:** Library stores original/cleaned text and supports search/copy/export. Failed sessions can retry, but successful captured audio is deleted and a history entry cannot run another mode. This maps to P4.
- **Layman's term:** You can find an old result, but cannot easily ask the app to clean it up differently.
- **What's wrong:** Failure retry and external audio import do not provide successful-history reprocessing.
- **Impact:** Moderate — users repeat work or copy text out manually.
- **Significance:** Medium
- **Difficulty:** M
- **Fix:** Add cleanup-only reruns from stored original text while retaining the original result. Design optional audio retention, deletion and consent separately for retranscription.
- **Grade lift:** B- → B for recoverable history workflows

#### C5 — Keep the selected mode name when settings are identical
- **Where:** Sources/Rebuild/RebuildSavedModesView.swift:16
- **Evidence:** The picker getter selects the first mode whose settings equal the current snapshot. Selecting a second differently named mode with identical settings resolves to the first name.
- **Layman's term:** Personal can appear to switch back to Work even though the processing settings are correct.
- **What's wrong:** The displayed identity is inferred from settings rather than the selected UUID.
- **Impact:** Minor — confusing feedback in the new mode picker.
- **Significance:** Medium
- **Difficulty:** S
- **Fix:** Track selected mode identity, invalidate it when current settings diverge, and cover selection of two identical snapshots.
- **Grade lift:** B- → B through consistent selection feedback

## D — Accessibility & Inclusive UX — B- provisional

Semantic labels, sidebar focus and Reduced Motion support provide real groundwork. D1 identifies a specific announcement-coverage gap; full VoiceOver/keyboard acceptance under R4 has not been run. No unsupported claim that all screen-reader use fails is made.

#### D1 — Announce complete session outcomes, including Express Mode
- **Where:** Sources/Rebuild/RebuildAccessibility.swift:4; Sources/Rebuild/RebuildRecorderView.swift:57; Sources/Rebuild/RebuildPracticeView.swift:69; Sources/Rebuild/RebuildPreferencesView.swift:129
- **Evidence:** Announcement bindings cover the HUD title and practice completion. Main Record completion/errors/delivery lack a binding; the helper defaults to no initial announcement and Express Mode suppresses the HUD. This is a static coverage gap, not a reproduced VoiceOver failure.
- **Layman's term:** Someone listening to the app should get the same essential feedback as someone watching it.
- **What's wrong:** Lifecycle announcement ownership depends on temporary views and does not cover the whole recording-to-delivery journey.
- **Impact:** Moderate — status and recovery may be harder to understand without vision.
- **Significance:** High
- **Difficulty:** M
- **Fix:** Own coarse start/processing/failure/delivery announcements at the session coordinator. Keep timers and draft words quiet. Verify keyboard and VoiceOver normal/Express flows under R4.
- **Grade lift:** B- → B/B+ after native acceptance

## E — Responsive & Cross-State Experience — B provisional

The UI designs setup-needed, loading, history-off, empty/search-no-results, failure and busy states (`RebuildReadiness.swift:7`, `RebuildContentState.swift:3`, `RebuildLibraryView.swift:24-69`). Fresh fixture previews include setup-needed and recording. Offscreen/minimum-size artifacts are not complete native resize, text-enlargement or multi-display acceptance.

## F — Frontend Code & Design System Health — B+

The active rebuilt app has reusable semantic themes, cards, content states and explicit session ownership (`RebuildDesign.swift:108-292`, `RebuildSession.swift:6`). The active entry point is RebuildApp; legacy Dashboard code is not treated as current UX. No strong additional design-system defect was found merely to fill an item count.

## G — UI Performance & Asset Efficiency — B provisional

Timing instrumentation, warm runtime reuse, paged/debounced Library loading and bounded recent-speech previews are meaningful strengths. No matched end-to-end speed evidence supports an A or a competitor ranking. G1 is an evidence/measurement increment, not a proven performance regression.

#### G1 — Measure real dictation speed and preview stability
- **Where:** Sources/Rebuild/RebuildSessionTiming.swift:3; Sources/Rebuild/RebuildLivePreview.swift:24; Sources/Rebuild/RebuildPerformanceView.swift:7
- **Evidence:** Timing instrumentation and cached-engine evidence exist. Live preview uses recent speech with final recognition at Stop. No matched Superwhisper test measures physical first-word capture, first preview, long dictation or confirmed paste.
- **Layman's term:** A fast short-file test is not yet a measurement of how fast dictation feels in another app.
- **What's wrong:** Relative speed and live-draft quality are unqualified; this is not a demonstrated slowdown.
- **Impact:** Moderate — confidence in the central comparison is limited.
- **Significance:** High
- **Difficulty:** M
- **Fix:** Use identical speech, hardware, model class, cleanup and destination apps. Report median/tail start-to-capture, first draft and stop-to-confirmed-paste, plus word retention and memory for short/long sessions.
- **Grade lift:** Evidence-dependent; a benchmark may confirm or change B

## H — Data Linkages & State Reliability — B

Captured configurations protect jobs and retries; history persistence does not delay delivery, and paste validation distinguishes confirmed/unverified/fallback outcomes (`RebuildSession.swift:260-310`, `RebuildPasteDelivery.swift:30-94`). H1 is a real mismatch between that state and the main success copy. H2 is a separate unresolved recognition-compatibility qualification.

#### H1 — Make the success headline match delivery and clipboard restoration
- **Where:** Sources/Rebuild/RebuildWorkspace.swift:371; Sources/Rebuild/RebuildSession.swift:365; Sources/Rebuild/RebuildSession.swift:390; Tests/RebuildPasteDeliveryTests.swift:200
- **Evidence:** Completed Record always says Copied to your clipboard. Smart Paste can restore the previous clipboard after confirmed or unverified delivery. Accurate timing.delivery is under Advanced. Source and restoration tests establish this mismatch; this audit did not perform a real paste.
- **Layman's term:** The app can say your transcript is on the clipboard after putting your previous clipboard contents back.
- **What's wrong:** The primary result message ignores delivery and restoration state already known by the session.
- **Impact:** Moderate — users can misunderstand delivery or paste older content.
- **Significance:** High
- **Difficulty:** S
- **Fix:** Expose copied, paste-confirmed, paste-unverified and manual-recovery outcomes on Record; reflect restoration and keep an explicit Copy text action. Add outcome-view tests.
- **Grade lift:** B → B+ for truthful completion states

#### H2 — Resolve the hosted macOS 15 recognition boundary
- **Where:** Sources/Services/LocalWhisperService.swift:47; Package.swift:8; PR #49 and its investigation record
- **Evidence:** With identical Xcode 26.3 builds and matching models, hosted macOS 15 encoder inference diverges and recognition fails. The diagnostic branch passes six Whisper cases on macOS 26 with fresh/restored models and all nine real-engine fixtures. The failing older OS has not been checked on physical hardware. This maps to R1.
- **Layman's term:** We know a modern hosted environment works, but cannot yet promise every supported Mac does.
- **What's wrong:** Green PR checks do not close real recognition acceptance; diagnostics are still in an open draft and the production fix is unresolved.
- **Impact:** Major — affects confidence in core transcription compatibility.
- **Significance:** High
- **Difficulty:** L
- **Fix:** Reproduce on physical macOS 15 or an equivalent provisioned target, isolate the Core ML failure and validate a real fix. Retain meaningful speech assertions and Parakeet/MLX passes. Do not hide the failure by dropping the OS test.
- **Grade lift:** B → B+/A- only after compatible-runtime acceptance

## I — Polish, Delight & Product Feel — B-

Practice, helpful recovery copy, local-only scope and preserved originals make the product feel considered. Daily-device acceptance, optional warm input and public installation trust still constrain finished-product confidence. R2-R4 are qualification work, not an excuse to mark all implemented features absent.

#### I1 — Qualify the microphone and delivery path on real hardware
- **Where:** Sources/Services/Audio/AudioEngineRecorder+Startup.swift:15; Sources/Rebuild/RebuildPasteDelivery.swift:30; docs/product-roadmap.md:R2/R3; PR #45
- **Evidence:** R2 hardware scenarios remain open. Optional warm microphone in PR #45 is not merged; its three hardware checks remain unchecked despite unit tests and green hosted checks.
- **Layman's term:** A polished recorder keeps your first word, follows the right mic and puts text in the right place every time.
- **What's wrong:** The remaining gap is daily-device acceptance, not absence of recording/hold/Smart Paste implementations.
- **Impact:** Major — first-word and destination mistakes break the core promise.
- **Significance:** High
- **Difficulty:** M
- **Fix:** Record exact packaged identity and devices; test built-in/USB/Bluetooth fallback, press/hold release, unplug, sleep/wake, disable/quit, Spaces and exactly-once paste. Merge warm mic after its acceptance.
- **Grade lift:** B- → B+ once daily behavior is proven

#### I2 — Finish public-install trust and update acceptance
- **Where:** scripts/build.sh; docs/product-roadmap.md:R4; /tmp/audiowhisper-modes-package-diagnostics.json
- **Evidence:** A locally signed debug bundle passed signature/resource/read-only diagnostics in the #50 work. Developer ID/notarization, clean quarantined install and update/relaunch acceptance remain open.
- **Layman's term:** The development app is not yet a fully qualified download-and-trust product.
- **What's wrong:** Local development signing does not establish a smooth public distribution lifecycle.
- **Impact:** Moderate — affects installation confidence and support burden.
- **Significance:** High
- **Difficulty:** M
- **Fix:** Validate universal Developer ID build, notarization/stapling and Gatekeeper on a clean quarantined install. Exercise launch/update/permissions and document the tested release artifact.
- **Grade lift:** B- → B+ for finished distribution

## Recommended order

1. Close R1 and run R2/R3/R4 acceptance alongside feature work; H1 and D1 are bounded trust improvements available now.
2. P2 app-to-mode activation and P1 language/task instructions give the largest everyday Superwhisper lift. Resolve mode identity while improving its editor.
3. P3 explicit context, then P4 cleanup-only history reprocessing.
4. P5 meetings and P6 public automation are separate expansions, not prerequisites for a good focused dictation utility.

Address fixes by UI ID (for example H1 or D1), or by the stable product roadmap ID (P1-P6 / R1-R4). This audit changes reports and tracking only; no app fixes are implemented.
