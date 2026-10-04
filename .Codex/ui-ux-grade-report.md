# UI/UX Grade Report

**Project:** AudioWhisper Rebuild
**Audited:** 2026-10-04
**Stack:** Native macOS SwiftUI/AppKit, observable session, SwiftData, local speech and writing engines.
**Version:** `rebuild/native-v2`; audit checkout `2d3e058`; packaged source `f0cc89a40dd380668c432ec186826772f3cd2b03`.
**Runtime evidence:** Fresh native rendered Record, Models & setup, Writing profiles, Preferences and history-off Library; actual installed-model verification and recording start/cancel. Earlier same-build live transcription, repeated capture and cold relaunch evidence is identified separately.
**Artifacts:** `.Codex/ui-ux-audit/2026-10-04-regrade/` ([provenance and capture index](ui-ux-audit/2026-10-04-regrade/README.md)).
**Previous reports:** [2026-10-03 rebuild audit](baseline-2026-10-03-native-v2/ui-ux-grade-report.md); [original app baseline](baseline-f3adb17/ui-ux-grade-report.md).
**ID scope:** Existing UI IDs are retained. Prefix requests with **UI** to distinguish them from code IDs. Completed items are excluded from open counts.

## Summary

| ID | Category | Grade | Open items |
|----|----------|-------|------------|
| A | Visual Design & Theme Cohesion | B | 0 |
| B | Layout, Information Architecture & Navigation | B | 0 |
| C | Interaction Design & Workflow Quality | B | 0 |
| D | Accessibility & Inclusive UX | B− provisional | 1 |
| E | Responsive & Cross-State Experience | B− provisional | 1 |
| F | Frontend Code & Design System Health | B | 0 |
| G | UI Performance & Asset Efficiency | B− provisional | 1 |
| H | Data Linkages & State Reliability | B | 0 |
| I | Polish, Delight & Product Feel | B− | 1 |
| **Overall** | | **B** | **4** |

**Top 5 highest-leverage actions:** UI I1, UI D1, UI G1, UI E1, and **code D3** (native acceptance). There are four open UI findings; the fifth action closes a validation gap tracked in the code report.

The previous C+ grade was driven by misleading state and incomplete device/data linkages. Those defects are now addressed, and this local preview earns B for its coherent utility design, clearer setup and working core recording path. A higher grade needs physical shortcut/Smart Paste/accessibility acceptance and measured large-file performance, alongside the remaining polish. B does not mean every macOS interaction or distribution requirement is complete.

---

## Evidence Limits

- All five screenshots are actual app windows, inspected visually alongside native accessibility trees. Dark/system appearance at the current window size is readable; minimum-size layouts, light mode, long-content stress and all error states were not visually retested.
- Fresh installed Parakeet verification showed disabled **Verifying…** controls and reached **Model ready (offline)**. Fresh recording start showed **Finish recording**, Record showed Listening and microphone levels, file import was disabled with an explanation, and Cancel returned to Ready without a permission prompt.
- Writing controls were all disabled during the active recording. A suspected Writing-button mismatch during recording was disproved and excluded. Possible behavior during unrelated model maintenance remains an unconfirmed investigation candidate, not a graded finding.
- Earlier observations of this same source passed five start/cancel cycles, selected MacBook Pro Microphone capture, stop/transcription with nonempty clipboard output and cold quit/relaunch without renewed consent. Signature checks after inference passed. Those observations are documented in [recommended-fix validation](recommended-fixes-validation.md), not claimed as all freshly repeated.
- History remained off and preferences were unchanged. Fresh inspection did not test a real save into a mounted Library, a populated filtered list, Smart Paste, physical global shortcut/hold, VoiceOver, actual disconnect/sleep or the complete normal-window/recording-overlay Spaces matrix. The mounted-list fix has isolated real SwiftData/session/observation coverage.
- No frame/jank, startup or long-file peak-memory benchmark was collected during this audit. Prior fixture cold/warm timings establish local cache reuse only. Performance and cross-state grades are provisional where direct evidence is missing.
- Current preview is universal and completely ad-hoc signed. Developer ID/notarization and stability across changed signing identities remain separate distribution concerns.

---

## A — Visual Design & Theme Cohesion — B

[Record](ui-ux-audit/2026-10-04-regrade/record-ready.png) and [Preferences](ui-ux-audit/2026-10-04-regrade/preferences.png) share a restrained paper/ink/rust identity, serif headings, consistent section cards and native controls. Theme tokens and shared headings/sections keep the five screens visually related (`Sources/Rebuild/RebuildWorkspace.swift:4-12,93-114`). The app has a recognizable point of view appropriate for a private dictation utility; no decorative redesign is needed to improve its remaining workflows.

---

## B — Layout, Information Architecture & Navigation — B

The five explicit destinations separate recording, saved text, setup, writing and preferences (`Sources/Rebuild/RebuildWorkspace.swift:35-41,63-75`). [Models](ui-ux-audit/2026-10-04-regrade/models-ready.png) presents the two required setup steps before optional features; [Writing](ui-ux-audit/2026-10-04-regrade/writing.png) keeps cleanup separate from speech setup. Native navigation and selected sidebar semantics worked in fresh checks. Minimum-size and realistic long-content inspection remain limits rather than invented layout defects (`Sources/Rebuild/RebuildApp.swift:36-55`).

---

## C — Interaction Design & Workflow Quality — B

Shared session action rules now drive Record, Voice Models, menu and import (`Sources/Rebuild/RebuildSession.swift:325-365`, `RebuildModelsView.swift:98-100`, `RebuildStatusController.swift:34-40`). Fresh verification and recording checks showed appropriate disabled/finish/cancel controls and explained why file import was unavailable. Retry retains captured audio and reports blocked admission instead of discarding it; correction failure preserves the original transcript. Physical shortcut/hold and Smart Paste acceptance remain **code D3**, so the grade stops below A.

#### ~~C1~~ ✓ done 2026-10-03 — Match recording/import affordances to actual actions

Shared titles, enabled states and reasons are implemented with state-matrix regressions. Fresh AX evidence confirms disabled Verifying, Finish recording, Listening, blocked import and cancellation back to Ready; the prior Voice Models/import mismatch is closed.

---

## D — Accessibility & Inclusive UX — B− provisional

Fresh AX trees expose selected navigation, named recording/import actions, checkboxes, pickers and a microphone-level value. Escape cancellation and Reduce Motion handling are connected (`Sources/Rebuild/RebuildWorkspace.swift:47`, `Sources/Views/Components/Waveform/WaveformContainer.swift:171,350`, `WaveformSubviews.swift:42-46`). Repeated profile/history actions and text editors still omit explicit target names. Actual VoiceOver, complete keyboard/focus order and measured contrast were not tested, limiting confidence.

#### D1 — Name editors and repeated actions by their purpose

- **Where:** `Sources/Rebuild/RebuildWorkspace.swift:209-210`; `Sources/Rebuild/RebuildWritingView.swift:97-102,131,217-218`; `Sources/Rebuild/RebuildLibraryView.swift:59-64`; [Writing AX](ui-ux-audit/2026-10-04-regrade/writing.ax.txt).
- **Evidence:** Fresh AX lists six generic Edit buttons; source editors have no explicit accessibility names, and history actions reuse generic Copy/Delete. No severe VoiceOver failure is claimed without a VoiceOver run.
- **Layman's term:** Without seeing the row, it is harder to know which text or profile a control affects.
- **What's wrong:** Control names omit their target content or editor purpose.
- **Impact:** Moderate — repeated controls are harder to distinguish with assistive navigation.
- **Significance:** Medium — inclusive access affects editing and saved-text use.
- **Difficulty:** S.
- **Fix:** Give transcript/profile editors explicit names and contextual row actions based on profile names or concise transcript date/context. Verify fresh AX labels, VoiceOver announcements and keyboard focus through sheets.
- **Grade lift:** B− provisional → B after native verification, by making control targets understandable.

---

## E — Responsive & Cross-State Experience — B− provisional

The [history-off Library](ui-ux-audit/2026-10-04-regrade/library-off.png) clearly explains optional saving. Fresh Ready/verification/Listening/cancel states work, and coordinator/session tests cover denied consent, install failure/retry, stale refresh and failure ownership (`Tests/RebuildSetupTests.swift:42-141`, `Sources/Rebuild/RebuildSession.swift:151-193,325-424`). Current dark/system layouts are readable. Filtered-empty copy remains ambiguous, and other appearance/window/content/error combinations lack fresh visual evidence.

#### E1 — Separate no search results from an empty Library

- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:43-46`; [history-off Library](ui-ux-audit/2026-10-04-regrade/library-off.png).
- **Evidence:** Source uses the same empty-list message when saved transcripts do not match a query and when none exist. Fresh runtime only inspected history-off; the populated filtered state was not exercised.
- **Layman's term:** Searching can make it look as if the Library has no recordings.
- **What's wrong:** Empty history and no matching search results share copy.
- **Impact:** Minor — unnecessary uncertainty about saved content.
- **Significance:** Medium — search should clarify what happened to saved text.
- **Difficulty:** XS.
- **Fix:** Show No matching transcripts with Clear search for a nonempty query; keep first-save copy for truly empty history and privacy copy for history-off. Verify those three states.
- **Grade lift:** B− provisional → B with cross-state verification, by explaining the list's actual state.

---

## F — Frontend Code & Design System Health — B

Purpose-specific views reuse theme, page headings and section components (`Sources/Rebuild/RebuildWorkspace.swift:4-12,93-114`). One observable session owns job admission/state; Library observes mutation revisions and fences stale reloads (`RebuildSession.swift:325-365`, `RebuildLibraryView.swift:75-81,107-123`). Profile editing uses the existing store and removes obsolete mappings when deleting profiles (`RebuildWritingView.swift:148-154,222-227`). These foundations support consistent polish without a broad frontend rewrite; specific accessibility improvements are already D1.

---

## G — UI Performance & Asset Efficiency — B− provisional

Library uses 50-row paging/LazyVStack, deferred search and streamed export (`Sources/Rebuild/RebuildLibraryView.swift:43-81,117-121,141-148`). Capture publication is throttled and Reduce Motion is connected (`Sources/Services/Audio/AudioEngineRecorder.swift:295-312`, `Sources/Views/Components/Waveform/WaveformContainer.swift:171,350`). Native navigation worked, and prior same-source cold/warm fixtures support cache reuse. Whole-file decoding remains a real memory hotspot; no quantitative UI/large-file benchmark supports a higher grade.

#### G1 — Bound memory during long audio imports

- **Where:** `Sources/Services/ParakeetService.swift:129-141,198-235`; `Sources/Services/LocalWhisperService.swift:190-192`; `Package.resolved:4-9`.
- **Evidence:** Parakeet retains complete decoded PCM plus another Data copy; validation has no size/duration limit. Locked Argmax 1.0.0 uses whole-file loading; [vendor 1.1.0 supplies incremental loading](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0). App peak RSS and OOM behavior were not measured.
- **Layman's term:** A long recording uses much more memory before transcription starts.
- **What's wrong:** Audio preparation grows with the complete input instead of bounded chunks, and conversion does not check cancellation.
- **Impact:** Moderate — large imports can put pressure on the Mac and delay cancellation; no app OOM was reproduced.
- **Significance:** High — file transcription is a supported workflow.
- **Difficulty:** M.
- **Fix:** Stream Parakeet PCM with cancellation/cleanup and adopt incremental Whisper loading. Verify short-file output parity and measure representative long-file memory/cancel behavior. Coordinate with **code G1/F3** rather than duplicating implementation.
- **Grade lift:** B− provisional → B after measured verification, by bounding import memory.

---

## H — Data Linkages & State Reliability — B

Typed capture interruptions are tied to the owning session, selected input routing reaches the Audio Unit, and failed model load verdicts persist into readiness (`Sources/Rebuild/RebuildSession.swift:151-193,368-424`, `Sources/Services/Audio/AudioInputRouting.swift:23-64`). Store revisions now invalidate mounted Library queries only after successful mutation (`RebuildLibraryView.swift:75-81,107-123`, `Tests/RebuildLibraryInvalidationTests.swift:27-95`). Fresh verification/start/cancel supports the normal path, and prior same-build selected-input transcription/cold relaunch supports the improved trust level. Hardware interruption, two-source comparison and mounted-Library native acceptance remain explicit evidence gaps.

#### ~~H1~~ ✓ done 2026-10-03 — Reconcile recorder interruptions with Listening state

The typed capture/session bridge, ownership and stale-event cleanup are implemented and regression-tested. Physical device disconnection/sleep remain unperformed.

#### ~~H2~~ ✓ done 2026-10-03 — Make the microphone choice control recording

Selected UID routing and device-specific boost/restoration are implemented. Prior explicitly selected MacBook Pro Microphone native recording/transcription passed; two distinguishable physical inputs remain unavailable for comparison.

#### ~~H3~~ ✓ done 2026-10-03 — Let failed model verification invalidate Ready

Engine/model/asset-keyed failures persist and block recording/import across refresh/relaunch; successful repair clears the verdict. Whisper verification loads the actual model. Fresh Parakeet verification reached Model ready (offline); failure/recovery contracts are regression-tested.

#### ~~H4~~ ✓ done 2026-10-03 — Refresh an open Library when a recording is saved

Successful SwiftData mutation advances an observed revision; query-preserving reload and stale-fetch fencing are connected. A real isolated store/session/observation regression protects this behavior; a native save-while-mounted check remains code D3.

---

## I — Polish, Delight & Product Feel — B−

The warm restrained identity and optional-feature/privacy copy give the rebuilt utility a consistent feel ([Record](ui-ux-audit/2026-10-04-regrade/record-ready.png), [Library](ui-ux-audit/2026-10-04-regrade/library-off.png)). Preferences clearly groups recording, delivery, privacy and appearance ([capture](ui-ux-audit/2026-10-04-regrade/preferences.png)). The configured shortcut still appears only in Preferences; Record always presents generic enable-in-Preferences guidance (`Sources/Rebuild/RebuildWorkspace.swift:155-158`). Surfacing this frequent control matters more than adding decorative animation.

#### I1 — Show the configured shortcut where recording happens

- **Where:** `Sources/Rebuild/RebuildWorkspace.swift:155-158`; `Sources/Rebuild/RebuildStatusController.swift:11,34-40`; `Sources/Rebuild/RebuildPreferencesView.swift:35-38`; [Record](ui-ux-audit/2026-10-04-regrade/record-ready.png) and [Preferences](ui-ux-audit/2026-10-04-regrade/preferences.png).
- **Evidence:** Fresh Record shows generic shortcut advice; Preferences shows ⇧⌘Space with enable off. Source keeps the generic copy even when enabled, and menu keyEquivalent is empty. Custom/enabled/cleared behavior was not physically tested.
- **Layman's term:** The app does not remind you which keys record.
- **What's wrong:** Shortcut value and enabled state are absent from the primary recording flow.
- **Impact:** Minor — a frequent action is harder to discover and remember.
- **Significance:** Medium — shortcut recording is a daily convenience.
- **Difficulty:** S.
- **Fix:** Show the current rebuildRecording shortcut when enabled and a direct configure/enable path otherwise. Bind the menu equivalent to the same shortcut name; verify custom, disabled and cleared values. Coordinate with **code F1/D3**.
- **Grade lift:** B− → B, by surfacing an essential daily control.

---

## Changing the recording shortcut

Open **Preferences → Shortcuts & recording**, click the field showing **⇧⌘Space**, and press the desired combination. The library saves it automatically. Enable **the rebuild's recording shortcut** to activate it. The observed value is Command+Shift+Space and the enable checkbox remains off; this audit did not change it. If the original app is running with the same shortcut, choose a different combination or stop its conflicting registration.

Global shortcut and modifier-hold recording are separate controls. Hold recording requires Accessibility; changing the normal shortcut does not require enabling hold recording.

Request UI fixes by prefix, for example **UI I1 D1 G1 E1**. Code IDs have different meanings. This grading run changes reports/evidence only.
