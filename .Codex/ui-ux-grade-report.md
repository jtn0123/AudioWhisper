# UI/UX Grade Report

**Project:** AudioWhisper Rebuild
**Audited:** 2026-10-03
**Stack:** Native macOS 14+ SwiftUI/AppKit, AVFoundation, SwiftData and on-device voice/writing engines.
**Version:** `rebuild/native-v2`, code commit `c75a55d3b0b12c2bd5dc7f5c67422584de792246`.
**Runtime evidence:** Fresh native screenshots and accessibility trees of Record, Library, Models & setup, Writing profiles and Preferences. Earlier live recording/transcription/cancel and same-build relaunch checks passed at this exact code build.
**Artifacts:** `.Codex/ui-ux-audit/2026-10-03-native-v2/`
**Historical report:** [Original app UI baseline](baseline-f3adb17/ui-ux-grade-report.md). These new IDs describe the rebuild.

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Visual Design & Theme Cohesion | B | 0 |
| B | Layout, Information Architecture & Navigation | B | 0 |
| C | Interaction Design & Workflow Quality | C+ | 1 |
| D | Accessibility & Inclusive UX | B− provisional | 1 |
| E | Responsive & Cross-State Experience | B− provisional | 1 |
| F | Frontend Code & Design System Health | B | 0 |
| G | UI Performance & Asset Efficiency | B− provisional | 1 |
| H | Data Linkages & State Reliability | C− | 4 |
| I | Polish, Delight & Product Feel | B− | 1 |
| **Overall** | | **C+** | **9** |

**Top 5 highest-leverage fixes:** H1, H2, H3, C1, H4.

The interface is substantially clearer and more coherent than the original: recording, setup, writing and opt-in history have distinct homes. Visual quality earns B. Overall C+ weights truthful capture, model readiness and saved-history updates more heavily than decoration. Zero-item categories have no independently validated visual/navigation defect worth inventing; their remaining improvement is better workflow reliability and broader verification.

---

## Evidence Limits

Five fresh screenshots show the actual running dark/system appearance; they are not ImageRenderer proposals. The live user-facing tests referenced in `docs/rebuild.md:31-42` were completed earlier in this same rebuild session, not repeated merely for this report. This pass navigated and inspected without altering preferences, microphone access, history or the user's shortcut.

VoiceOver announcements, keyboard focus through every sheet, smallest-window resizing, long content, increased text sizes, high contrast, light-mode captures at the final build, physical shortcut/hold recording, Smart Paste and the complete desktop/full-screen Spaces matrix remain unverified. No measured UI frame/startup benchmark was collected. Accessibility, cross-state and performance grades therefore remain provisional.

H1/H2/H3/H4 and C1 are source-confirmed linkage/admission problems, not physical route/sleep/corrupt-model experiments. The normal native recording and same-build microphone-consent paths passed. Earlier permission spam is not assumed still present after the signing/bytecode fixes. The preview remains ad-hoc signed, so a different rebuilt artifact can require fresh development consent.

Writing capture contains a white strip outside the content near its bottom; this was not confirmed as an app rendering defect and is not counted. Library history was off, so its populated/export workflows were assessed from source. The full audit's security/dependency concerns are in the [code report](grade-report.md), not hidden inside this visual grade.

### Captures

- [Record workspace](ui-ux-audit/2026-10-03-native-v2/record-dark.png): primary action, readiness, empty transcript and safe test totals.
- [Library with history off](ui-ux-audit/2026-10-03-native-v2/library-history-off.png): clear optional saving and local-storage copy.
- [Models ready](ui-ux-audit/2026-10-03-native-v2/models-ready.png): permission/model checklist and explicit verification/removal.
- [Writing profiles](ui-ux-audit/2026-10-03-native-v2/writing-capture.png): optional cleanup and profile actions.
- [Preferences/shortcut](ui-ux-audit/2026-10-03-native-v2/preferences-shortcut.png): actual shortcut field and enable state.

---

## A — Visual Design & Theme Cohesion — B

The running screens share charcoal/ink surfaces, warm rust accents, serif page headings and consistent section treatment; the [Record](ui-ux-audit/2026-10-03-native-v2/record-dark.png), [Models](ui-ux-audit/2026-10-03-native-v2/models-ready.png) and [Preferences](ui-ux-audit/2026-10-03-native-v2/preferences-shortcut.png) captures support this grade. `Sources/Rebuild/RebuildWorkspace.swift:4-12,93-114` centralizes theme and page chrome. The primary action stands out and dense controls remain grouped, though final-build alternate appearance/contrast validation is incomplete. No separate verified visual defect is assigned.

---

## B — Layout, Information Architecture & Navigation — B

Five explicit sidebar destinations make the main jobs discoverable (`Sources/Rebuild/RebuildApp.swift:36-55`; `Sources/Rebuild/RebuildWorkspace.swift:128-137`). [Models & setup](ui-ux-audit/2026-10-03-native-v2/models-ready.png) groups the two recording prerequisites, while Writing profiles and Library remain optional and separate. Native navigation among these screens worked. Shortcut visibility in the primary workflow is addressed by I1; the full keyboard/minimum-window matrix is still unverified.

---

## C — Interaction Design & Workflow Quality — C+

One shared session handles recording, cancellation, retry and captured delivery; inline failure and optional cleanup fallback improve recovery (`Sources/Rebuild/RebuildSession.swift:135-179,198-259`). Live normal recording and repeat-cancel checks support the happy path. Some connected controls still contradict session admission, and H's device-state gaps affect the central workflow.

#### C1 — Match action labels and enabled states to actual behavior
- **Where:** `Sources/Rebuild/RebuildModelsView.swift:92`; `Sources/Rebuild/RebuildWorkspace.swift:141-176`; `Sources/Rebuild/RebuildStatusController.swift:34-38`; `Sources/Rebuild/RebuildSession.swift:141-143,170-175`.
- **Evidence:** Models always renders Start recording when readiness is true; that command stops an active recording and ignores a transcribing one. Import remains enabled during maintenance/install while the session rejects it silently.
- **Layman's term:** A button can mean something different from its label, or accept a file and then do nothing.
- **What's wrong:** Views duplicate only part of the session's action rules.
- **Impact:** Moderate — confusing controls and discarded import attempts.
- **Significance:** High — these are primary recording/file actions.
- **Difficulty:** S.
- **Fix:** Expose shared recording/import titles, availability and blocked reasons. Apply them to Record, setup and menu; test idle, recording, transcribing, installing and maintenance.
- **Grade lift:** C+ → B−; B with H's fixes, by making actions predictable.

---

## D — Accessibility & Inclusive UX — B− provisional

Fresh AX observations expose selected navigation, named record controls, checkboxes, pickers and the shortcut field. Escape cancellation and connected Reduce Motion handling exist (`Sources/Views/Components/Waveform/WaveformContainer.swift:171,350`; `Sources/Views/Components/Waveform/WaveformSubviews.swift:42-46`), so the original app's motion finding is not carried forward. Generic editor/action names remain; actual VoiceOver and complete keyboard/focus testing were not performed.

#### D1 — Name editors and repeated actions by their purpose
- **Where:** `Sources/Rebuild/RebuildWorkspace.swift:199`; `Sources/Rebuild/RebuildWritingView.swift:97-102,218`; `Sources/Rebuild/RebuildLibraryView.swift:54-59`; [Writing capture](ui-ux-audit/2026-10-03-native-v2/writing-capture.png).
- **Evidence:** Editors lack explicit accessible names; profile/history rows reuse generic Edit, Copy and Delete.
- **Layman's term:** Without visual context, controls are harder to tell apart.
- **What's wrong:** Names omit the target content or editor purpose.
- **Impact:** Moderate — screen-reader and keyboard navigation become harder.
- **Significance:** Medium.
- **Difficulty:** S.
- **Fix:** Label transcript/profile editors and contextual actions using profile titles or concise transcript dates/context. Verify AX names, VoiceOver announcements and keyboard focus through sheets.
- **Grade lift:** B− provisional → B after native verification, by making control targets understandable.

---

## E — Responsive & Cross-State Experience — B− provisional

The [history-off screen](ui-ux-audit/2026-10-03-native-v2/library-history-off.png) explains optional saving clearly. Setup has explicit missing/denied/install states, while session failure/cancel/retry and optional correction fallback exist in source (`Sources/Rebuild/RebuildSession.swift:216-246,292-337`). Dark/system layouts were readable at the current window size; minimum size, long content and all errors were not visually exercised.

#### E1 — Distinguish no search matches from an empty Library
- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:38-41,70-76`.
- **Evidence:** The same empty copy says future recordings will appear even when existing saved transcripts simply do not match the query.
- **Layman's term:** Search can make it look as if your Library has no recordings.
- **What's wrong:** Empty-history and filtered-empty states use the same message.
- **Impact:** Minor — unnecessary uncertainty about saved content.
- **Significance:** Medium.
- **Difficulty:** XS.
- **Fix:** Show a query-specific No matching transcripts state with Clear search; keep the first-save explanation for truly empty history. Verify empty/query/history-off states.
- **Grade lift:** B− provisional → B with cross-state verification, by clarifying the list's state.

---

## F — Frontend Code & Design System Health — B

Purpose-specific native views reuse theme, page headings and sections (`Sources/Rebuild/RebuildWorkspace.swift:4-12,93-114`), rather than copying the legacy shell. Profile editing uses its observable store and removes stale mappings on profile deletion (`Sources/Rebuild/RebuildWritingView.swift:148-154,222-227`). Action-rule duplication is already an executable C1 finding; there is no additional refactor invented merely to fill this category.

---

## G — UI Performance & Asset Efficiency — B− provisional

Library uses 50-record paging/LazyVStack, 200 ms search deferral and streamed exports (`Sources/Rebuild/RebuildLibraryView.swift:43-76,110-114,134-142`). Recorder publication is bounded/throttled (`Sources/Services/Audio/AudioEngineRecorder.swift:388-400`) and Reduce Motion is connected. Native navigation worked, but no quantitative frame/startup/memory benchmark supports an A-level claim.

#### G1 — Bound memory during long audio imports
- **Where:** `Sources/Services/ParakeetService.swift:129-141,198-232`; `Sources/Services/LocalWhisperService.swift:185`; `Package.resolved`.
- **Evidence:** Parakeet retains complete decoded audio plus another Data copy; imports have no size/duration cap. Current Argmax 1.0.0 uses whole-file loading.
- **Layman's term:** A long recording uses much more memory before transcription even starts.
- **What's wrong:** File preparation grows with the complete input instead of bounded chunks.
- **Impact:** Moderate — large imports can put pressure on the Mac; no app OOM was reproduced.
- **Significance:** High — file transcription is a supported workflow.
- **Difficulty:** M.
- **Fix:** Stream Parakeet PCM conversion with cancellation/cleanup; adopt supported incremental Whisper loading. Measure a representative long file and verify short-file output parity. Coordinate with code G1/F3 rather than duplicating work.
- **Grade lift:** B− provisional → B after measured verification, by bounding import memory.

---

## H — Data Linkages & State Reliability — C−

Readiness includes selected-model structural presence, runtime and microphone access, and selection changes reject stale setup results (`Sources/Rebuild/RebuildSession.swift:264-287`). Delivery preserves ownership and reports correction/history failures. Four confirmed gaps still contradict visible capture, input, verification or history state; these outweigh the normal-path successes.

#### ~~H1~~ ✓ done 2026-10-03 — Reconcile recorder interruptions with Listening state
- **Where:** `Sources/Services/Audio/AudioEngineRecorder+Interruptions.swift:50-65`; `Sources/Rebuild/RebuildSession.swift:135-168`; `Sources/Rebuild/RebuildApp.swift:72-100`.
- **Evidence:** Sleep stops capture; engine failure cancels it. Their notifications have no new-shell subscriber.
- **Layman's term:** The app can say Listening after the microphone has stopped.
- **What's wrong:** Hardware recording and session phase can diverge.
- **Impact:** Major — potentially lost speech and stuck busy controls.
- **Significance:** High.
- **Difficulty:** M.
- **Fix:** Deliver typed interruption events to the owning session, reconcile phase/overlay, deliberately preserve graceful audio and fence stale events. Test both paths and perform a native route-change check.
- **Grade lift:** C− → C+; B− with H2/H3, by making capture status truthful.

**Implementation evidence:** The interruption/session bridge and stale-event cleanup are implemented and covered by failing-before/passing-after regressions. Physical device disconnection remains unverified.

#### H2 — Make the microphone choice control recording
- **Where:** `Sources/Rebuild/RebuildPreferencesView.swift:10,51-55`; `Sources/Rebuild/RebuildSession.swift:44-50`; `Sources/Services/Audio/AudioEngineRecorder.swift:150-155`; [Preferences capture](ui-ux-audit/2026-10-03-native-v2/preferences-shortcut.png).
- **Evidence:** The picker stores selectedMicrophone, but the connected recorder reads no such preference and uses the default input; boost targets the default too.
- **Layman's term:** Picking a microphone changes the setting, not the mic being recorded.
- **What's wrong:** Advertised device selection has no routing implementation.
- **Impact:** Major — wrong-source or silent recording.
- **Significance:** High.
- **Difficulty:** M.
- **Fix:** Capture/route selected CoreAudio device UID and apply boost/restoration to it. Report missing inputs; test device routing plus two distinguishable physical inputs.
- **Grade lift:** C− → C+; B− with H1/H3, by connecting the user's choice to capture.

#### H3 — Let failed model verification invalidate Ready
- **Where:** `Sources/Rebuild/RebuildModelsView.swift:149-177`; `Sources/Rebuild/RebuildSession.swift:274-287`; [Setup capture](ui-ux-audit/2026-10-03-native-v2/models-ready.png).
- **Evidence:** Verification's succeeded flag is ignored; refresh recomputes readiness from structural presence and runtime, not load success.
- **Layman's term:** The app can say Ready after its own model check failed.
- **What's wrong:** Verification feedback and recording eligibility disagree.
- **Impact:** Major — users can begin recording with a known unusable selected model.
- **Significance:** High.
- **Difficulty:** M.
- **Fix:** Keep engine/model/asset-keyed verification status. Block readiness on failure and offer repair; invalidate after asset/selection changes. Test present assets with failed load and successful recovery.
- **Grade lift:** C− → B− with H1/H2, by aligning setup claims with engine evidence.

#### H4 — Refresh an open Library when a recording is saved
- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:7,70-76,101-117`; `Sources/Rebuild/RebuildSession.swift:94,219-225`; `Sources/Stores/DataManager.swift:186-211`.
- **Evidence:** Library's fetched snapshot refreshes on search/history/actions. didDeliver has no assignment, and save emits no list invalidation.
- **Layman's term:** A saved recording can be missing until you leave the Library or search again.
- **What's wrong:** Background delivery does not update the visible list.
- **Impact:** Moderate — saving appears unreliable.
- **Significance:** High.
- **Difficulty:** S.
- **Fix:** Publish a successful-history revision and refresh mounted Library without changing query. Test shortcut/menu delivery with Library visible and cover retention/deletion.
- **Grade lift:** C− → B− with H1/H2/H3, by making saved content visible promptly.

---

## I — Polish, Delight & Product Feel — B−

The warm restrained visual identity, clear optional-feature copy and [Library privacy explanation](ui-ux-audit/2026-10-03-native-v2/library-history-off.png) give the rebuild a cohesive product feel. The actual shortcut is hidden from the primary Record flow, even though recording is the app's frequent action. Broader delight/interaction claims await the physical shortcut and window matrix.

#### I1 — Show the configured shortcut where recording happens
- **Where:** `Sources/Rebuild/RebuildWorkspace.swift:155-157`; `Sources/Rebuild/RebuildStatusController.swift:11,36`; `Sources/Rebuild/RebuildPreferencesView.swift:35-38`; [Record capture](ui-ux-audit/2026-10-03-native-v2/record-dark.png).
- **Evidence:** Record always says enable your shortcut in Preferences, even when enabled. Menu lacks the configured equivalent; only Preferences/diagnostics show the keys.
- **Layman's term:** The app does not remind you which keys record.
- **What's wrong:** Shortcut state is absent from the primary workflow.
- **Impact:** Minor — a frequent action is harder to discover/remember.
- **Significance:** Medium.
- **Difficulty:** S.
- **Fix:** Show the current rebuildRecording shortcut when enabled, a direct enable/configure path otherwise, and bind the menu equivalent to the same shortcut name. Verify custom, disabled and cleared shortcuts.
- **Grade lift:** B− → B, by surfacing an essential daily control.

---

## Changing the recording shortcut

Open **Preferences → Shortcuts & recording**. Click the field showing **⇧⌘Space** (Recording shortcut) and press the desired combination; the library saves it automatically. Enable **the rebuild’s recording shortcut** to activate it. Current observed value is Command+Shift+Space and the enable checkbox is off. If the original app is also running, use a different combination or stop its conflicting shortcut registration.

The normal global shortcut and optional modifier-hold setting are separate controls. The latter requires Accessibility access; changing the normal shortcut does not require enabling hold recording.

Request UI fixes by prefix, for example **UI H1 H2 I1**. Code IDs in the other report have different meanings. This is an audit, not a claim these findings are already repaired.
