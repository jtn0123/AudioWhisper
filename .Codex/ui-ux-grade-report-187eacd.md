# UI/UX Grade Report

**Project:** AudioWhisper Rebuild
**Audited:** 2026-10-04
**Code:** `187eacdb55737ba8eb6b57c9bb59f5e0cc23c506`
**Product:** Private local dictation: setup, recording/shortcut/hold, file import,
optional writing cleanup, clipboard/Smart Paste and optional local history.

This fresh report preserves the [historical UI/UX report](ui-ux-grade-report.md).
Its IDs are separate: refer to “187eacd UI B1,” for example. The
[overall codebase grade](grade-report-187eacd.md) also assesses transcript
integrity and distribution tooling; this report focuses on presentation,
interaction and UI state.

## Summary

| ID | Category | Grade | Items | Plain meaning |
|---|---|---|---|---|
| A | Visual Design & Theme Cohesion | B+ | 0 | A deliberate, consistent visual identity |
| B | Layout, Information Architecture & Navigation | B | 1 | Clear destinations; model choices need better guidance |
| C | Interaction Design & Workflow Quality | B+ | 1 | Native dictation/paste works in the tested guest; profiles need polish |
| D | Accessibility & Inclusive UX | B−, provisional | 1 | Useful semantics and keyboard support; faint timer and untested VoiceOver |
| E | Responsive & Cross-State Experience | B, provisional | 0 | Minimum window and full-screen recorder demonstrated; broader displays untested |
| F | Frontend Code & Design System Health | B | 0 | Shared components and observable session state support consistent screens |
| G | UI Performance & Asset Efficiency | B, provisional | 1 | Bounded list/animation work; large export still runs on the UI actor |
| H | Data Linkages & State Reliability | B+ | 0 | Readiness, failures, retries and history invalidation have meaningful coverage |
| I | Polish, Delight & Product Feel | B | 0 | Much clearer shortcut/setup copy; technical model/profile language remains |
| **Overall** | | **B** | **4** | A good native preview, with guidance and accessibility work still visible |

**Ranked improvements:** **B1 → C1 → G1 → D1**. VoiceOver, physical hold,
Sonoma/multiple-display/device checks and fresh performance measurement are
acceptance work, listed separately below rather than invented visual defects.

## Evidence limits

This pass inspected actual native screenshots and current source. The latest
[VM captures](ui-ux-audit/2026-10-04-vm/README.md) establish the recorder,
Preferences at minimum size, native paste and full-screen behavior. The binary
was built from `77d85cd` plus the implementation subsequently committed in
`187eacd`; the source/binary provenance is in [VM validation](macos-vm-validation.md).
The guest is macOS 26.6.2 with a 1024×768-point display at 2× scale. It uses
virtual audio and synthetic guest OS input, not physical host microphone/keys.

Older [native regrade screenshots](ui-ux-audit/2026-10-04-regrade/README.md)
show Models, Writing, Library-off and dark appearance at `f0cc89a`. Those
screenshots are labeled historical; current source was checked for relevant
changes. They do not establish the newest sidebar copy or a newly exercised
current Writing/profile workflow. No mockup is presented as app evidence.

The latest implementation pass includes ten cancel cycles, actual Whisper
speech inference, exactly-once native paste, guest OS global-shortcut dispatch,
consent continuity across signed replacements, and Preferences/recorder
full-screen isolation. Those saved runs were reviewed, not repeated in this
grading turn. Physical modifier hold remains incomplete because the guest
remote input omits device-specific bits. VoiceOver, multiple displays, Sonoma
14, physical sleep/disconnect, native populated profile mappings and current
startup/frame/large-library measurements remain unperformed. No WCAG contrast
failure or notarized public-release certification is claimed.

## A — Visual Design & Theme Cohesion — B+

The shared paper/ink/rust palette, serif page headings and recurring section
cards give the app a clear identity (`Sources/Rebuild/RebuildWorkspace.swift:5`,
`:97`, `:109`). The latest Preferences capture is readable and consistent with
the workspace rather than looking like an unrelated utility panel. The dark
Models capture supports the historical theme presentation; it is not a fresh
contrast certification. No additional visual defect was established here.

## B — Layout, Information Architecture & Navigation — B

Five sidebar destinations separate the primary Record action from optional
Library, Models, Writing and Preferences (`RebuildWorkspace.swift:16`). Setup
clearly names two essentials instead of treating every convenience as a
requirement (`RebuildModelsView.swift:15`). The current minimum-size Preferences
capture supports a usable native layout. The remaining information-design
weakness is choosing among technically named models without English-focused
advice.

#### B1 — Explain which model to choose for English

- **Where:** `Sources/Rebuild/RebuildModelsView.swift:36`, `Sources/Rebuild/RebuildWritingView.swift:29`, `Sources/Services/MLXModelManager.swift:58`, historical native `ui-ux-audit/2026-10-04-regrade/models-ready.png` and `writing.png`.
- **Evidence:** The rebuilt picker offers “v3 · 25 languages” and “v2 · English.” Writing uses repository labels although the model manager already stores human descriptions. Current source confirms this presentation; [model research](model-review-2026-10-04.md) supplies a provisional English recommendation.
- **Layman's term:** The app asks you to choose the engine without explaining which one suits you.
- **What's wrong:** Version/repository names substitute for quality, language and resource guidance. Static model-size labels are not measured Core ML install sizes or peak RAM.
- **Impact:** Moderate — users can make a less suitable choice or expect the wrong download/resource cost.
- **Significance:** High — model selection determines the core dictation experience.
- **Difficulty:** M.
- **Fix:** Show a recommended English choice and brief reason, with multilingual alternatives retained. Display existing writing descriptions, distinguish estimated download size from measured RAM, and base future default changes on shared-audio benchmarks.
- **Grade lift:** B → B+, by making setup a guided decision. Corresponds to codebase C1.

## C — Interaction Design & Workflow Quality — B+

The latest guest evidence demonstrates start/cancel, stop/transcribe and native
Smart Paste into a captured destination exactly once. The recorder no longer
collapses or hides under the Dock, and it remains usable above full-screen
TextEdit while Preferences stays on the desktop. Shared admission rules and
owned retry audio protect recovery (`RebuildSession.swift:289`, `:354`). App-aware
writing still exposes technical identifiers and stale choices; successful
cleanup also lacks a restore-original action, tracked as codebase B3.

#### C1 — Make app-aware writing mappings readable and current

- **Where:** `Sources/Rebuild/RebuildWritingView.swift:111`, `:125`, `:141`, `Sources/Managers/AppCategoryManager.swift:74`.
- **Evidence:** The mapping list uses `Text(id)` and repeats the bundle ID in accessibility labels. `.task` takes one running-app snapshot; there is no launch/termination refresh or Refresh button. A populated native mapping was not exercised in this audit.
- **Layman's term:** It shows names like `com.apple.mail` instead of Mail, and a newly opened app may not appear yet.
- **What's wrong:** Internal identifiers and a stale running-app list add unnecessary friction to an existing profile workflow.
- **Impact:** Moderate — selecting and confirming the right destination/profile is harder than needed.
- **Significance:** Medium — this affects optional app-specific writing, not basic recording.
- **Difficulty:** S.
- **Fix:** Resolve friendly names/icons with a bundle-ID fallback and update the list when applications launch/terminate or on explicit refresh. Use friendly accessibility action labels.
- **Grade lift:** B+ → A− for this workflow, by removing avoidable selection friction. Corresponds to codebase C2.

## D — Accessibility & Inclusive UX — B−, provisional

Repeated profile controls have contextual accessibility labels
(`RebuildWritingView.swift:98`, `:104`), navigation exposes selection semantics,
and Escape/cancel plus Reduce Motion behavior are connected to actual actions.
These are useful source/test observations, but full VoiceOver traversal and
keyboard focus order have not been demonstrated. The latest native HUD also
shows a visibly faint small elapsed timer; its readability can improve without
claiming an unmeasured compliance failure.

#### D1 — Increase recording-timer legibility

- **Where:** `Sources/Views/Components/Waveform/WaveformContainer.swift:297`, `Sources/Views/Components/Waveform/WaveformSubviews.swift:67`, current `ui-ux-audit/2026-10-04-vm/overlay-over-fullscreen.png` and `recording-visible.png`.
- **Evidence:** The elapsed label is 11-point monospaced text inheriting white at 32% opacity. It is visibly faint in the native screenshot over a bright full-screen document. No contrast-ratio measurement was made.
- **Layman's term:** The recording time is harder to read than it needs to be.
- **What's wrong:** Low emphasis works against a useful live status value on a translucent surface.
- **Impact:** Minor — users must look harder to check how long they have been recording.
- **Significance:** Medium — it is visible during the primary workflow.
- **Difficulty:** XS.
- **Fix:** Use a stronger foreground/surface combination. Inspect bright/dark destinations and macOS Increased Contrast/Reduce Transparency; measure the final contrast before making a compliance claim.
- **Grade lift:** B− → B for this specific readability issue; VoiceOver/focus validation remains necessary.

## E — Responsive & Cross-State Experience — B, provisional

The latest HUD has fixed 380×230-point content and whole-frame display
containment (`Sources/Rebuild/RebuildWorkspace.swift:275`,
`Sources/Rebuild/RebuildApp.swift:130`,
`Sources/Views/Components/RecordingWindowComponents.swift:5`).
The minimum workspace capture demonstrates scrollable Preferences, while native
desktop/full-screen checks establish distinct normal-window and recorder
behavior. Failure, verification, retry and optional history-off states have
source and earlier runtime evidence. Multi-display layouts, long-content stress
and Sonoma native behavior remain unverified rather than presumed broken.

## F — Frontend Code & Design System Health — B

Shared headings/sections and theme tokens keep polish changes centralized
(`RebuildWorkspace.swift:97`, `:109`). Purpose-specific views consume one
observable session, and Library revision/request checks fence stale reloads
(`RebuildLibraryView.swift:75`, `:107`). The running-app snapshot problem is
addressed by C1; no additional current design-system defect was established.
Dormant legacy app assembly remains codebase A2, not a justification for a new
UI rewrite.

## G — UI Performance & Asset Efficiency — B, provisional

Library uses bounded pages, lazy rows and debounced search; timers/waveform work
stop outside their visible active states (`RebuildLibraryView.swift:107`,
`WaveformSubviews.swift:67`, `FrameTimer.swift`). These are useful implementation
properties, not fresh frame-time measurements. Large Library export still
performs non-suspending work on the UI actor, so its responsiveness needs a
targeted measurement and fix.

#### G1 — Keep Library export responsive

- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:140`, `Sources/Stores/DataManager+Fetching.swift:42`, `Sources/Stores/DataManager.swift:114`.
- **Evidence:** The main-actor export pages through all records without suspension and performs formatting, file writes and synchronization there. Paging bounds memory but does not yield to UI input. No stall duration was measured in this audit.
- **Layman's term:** Saving a big transcript library can make the window stop responding for a while.
- **What's wrong:** Potentially substantial export work shares the UI execution context despite the asynchronous function label.
- **Impact:** Moderate — input/progress feedback can be delayed during a large export.
- **Significance:** Medium — this affects an optional history workflow.
- **Difficulty:** M.
- **Fix:** Stream transferable records through an isolated model/worker path, with cancellation and write-error handling. Keep the save panel/status on the UI actor and measure a large disposable library before/after.
- **Grade lift:** B → B+, by making existing bounded export responsive. Corresponds to codebase G1.

## H — Data Linkages & State Reliability — B+

Readiness incorporates model-load outcomes instead of only checking file
presence (`RebuildModelVerification.swift:15`, `RebuildSession.swift:368`). Session
IDs fence stale delivery, Library observes completed mutations, and native
paste/permission continuity are demonstrated in the guest. These support UI
truth and recovery. This grade does not certify textual fidelity: the cleaner
and long-correction integrity defects are explicitly tracked as codebase B1/B2.

## I — Polish, Delight & Product Feel — B

Current Preferences clearly says “Enable recording shortcut,” and Record/menu
guidance reflects the configured shortcut or disabled/unassigned state
(`RebuildPreferencesView.swift`, `RebuildWorkspace.swift:130`, `RebuildStatusController.swift`).
Optional local storage and local processing are explained in product language,
and the sidebar's preview jargon was reduced. Model/profile technical labels
remain the clearest unfinished product details, already addressed by B1/C1.

## Acceptance work kept separate from defects

1. Complete VoiceOver and keyboard-only navigation/record/cancel/model/profile/Library journeys.
2. Complete physical left/right modifier hold/release; guest logical modifier events are insufficient proof.
3. Run Sonoma 14, multiple-display/full-screen placement, physical input switch/disconnect and sleep/wake.
4. Measure startup, first useful action, large-Library search/export and animation/frame behavior on specified hardware.

The completed recorder-collapse, off-screen placement and full-screen eligibility
bugs are recorded as fixes in [VM validation](macos-vm-validation.md); they are
not reopened as current findings in this report.
