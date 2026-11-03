# UI/UX Grade Report — independent Opus 5.5 review

**Project:** AudioWhisper (native macOS SwiftUI/AppKit local dictation utility)
**Audited:** 2026-11-02, Claude Opus 5.5 (medium effort), UI/UX only
**Source:** `b98045bd7e8ffe20a55f735bcc43676ed31bc039` (master merge of #49). `Sources/` was unchanged against the pin during the audit.
**App under test:** `/tmp/audiowhisper-ui-review-20261102/AudioWhisper.app` (`com.audiowhisper.rebuild` 2.0.0, locally signed). The user's legacy October 3 `com.audiowhisper.app` was neither graded nor touched.
**Evidence:** [README](README.md), with seven native window captures of every page in the isolated **first-run / setup-needed / dark** state. This is a separate report. The October 18 B grades in `.Codex/ui-ux-grade-report.md` are not inherited.

## Evidence confidence

| Area | Evidence | Confidence |
|---|---|---|
| Page layout, copy, setup gating, empty states (dark, first run) | **Native** screenshots of the real app | High |
| Light mode | 2026-10-19 offscreen render only (cached header layers can be missing, so those gaps are not counted as defects) | Low–medium |
| Recording HUD, processing, cancel/retry, delivery, populated library, mode editor, meeting capture | Source review only. Not exercised natively. | Medium (code) / none (runtime) |
| Accessibility tree, keyboard traversal, VoiceOver | REA AX capture failed (`window-mismatch`). Labels were reviewed in source only. | Low |
| Small window (min 870 × 620) | Source constant plus the offscreen render | Low |
| Performance | No measurement taken. Page switches looked instant in captures taken 2 s apart, which is not a measurement. | Not graded |

Diagnostics (which currently keep only the last session's timings) are being reworked by the parent task. This report does not grade them.

## Summary

**Overall UI/UX: B-, provisional (medium confidence).** The interface looks calm and native, and it fits a private utility. The setup-needed state is honest and blocks unsafe actions correctly. Empty states are written well. The grade sits below B because of three things seen in the first-run journey: first-run gating is inconsistent (Meetings can start without a model, and the global shortcut is off by default and missing from setup), the setup instruction repeats with an unclear name for the next step, and the internal "Rebuild" name shows in the window and menu bar. Recording, HUD and accessibility claims could not be verified at runtime, which keeps C and D provisional.

| ID | Category | Grade | Items |
|---|---|---|---|
| A | Visual Design & Theme Cohesion | B | 1 |
| B | Layout, IA & Navigation | B- | 2 |
| C | Interaction Design & Workflow | B- provisional | 3 |
| D | Accessibility & Inclusive UX | B- provisional (unverified) | 1 |
| E | Responsive & Cross-State | B- | 1 |
| F | Frontend Code & Design System | B (limited sample) | 0 |
| G | UI Performance | Not graded (no measurement) | 0 |
| H | Data Linkages & State Reliability | B | (see C1) |
| I | Polish, Delight & Product Feel | B- | 1 |
| **Overall** | | **B-, provisional** | **9** |

**Blocker:** none found. Every confirmed defect is recoverable, and no data is lost.

**Top fixes:** C1 (gate Meetings on installed models), C2 (bring the recording shortcut into first-run setup), B1 (one setup message with correct names), I1 (remove "Rebuild" from user-facing names), C3 (make Esc cancel reach the HUD, or stop promising it).

---

## A — Visual Design & Theme Cohesion — B

A dark slate sidebar, teal accent, a serif wordmark and cards keep a consistent style across all six native pages. Status colors carry meaning: amber means setup, green means granted. Grey disabled buttons (`Transcribe a file…`, `Record a practice sentence`, `Export all modes…`) are legible and read as disabled. On an 870 × 1084 window, most pages leave over half the height as empty canvas (Record, Library, Models). That is acceptable for a utility, but Record could use the space for recent results or a shortcut primer.

#### A1 — Disabled and selected segment states read alike
- **Where:** `Sources/Rebuild/RebuildModelsView.swift:85-90`; `Sources/Rebuild/RebuildVocabularyEditor.swift` entry-type picker; screenshots `native-models-dark.png`, `native-writing-dark.png`
- **Evidence:** In dark mode, the selected `Parakeet · Apple Silicon` and `Word or name` segments use a lighter grey fill with dimmer text, while the unselected segment has brighter text. The selected option looks the least active.
- **Layman's term:** You can't tell at a glance which engine is chosen.
- **What's wrong:** The system segmented style combines with the custom dark tokens and the inactive window state, which weakens the selection signal.
- **Impact:** Minor. Users may misread the active engine or entry type.
- **Significance:** Medium
- **Difficulty:** S
- **Fix:** Check the key-window dark state, then tint the selected segment (`.tint(RebuildTheme.accent)`) or switch to radio rows to match the Model row. Add a dark key/non-key snapshot.
- **Grade lift:** B → B (refinement)

## B — Layout, Information Architecture & Navigation — B-

Six clear destinations with ⌘1–⌘6 help tooltips (`RebuildWorkspace.swift:171`) and a persistent status footer work well. The problems are naming drift and repetition.

#### B1 — The setup step is repeated four times and points to a page that doesn't exist
- **Where:** `Sources/Rebuild/RebuildReadiness.swift:17`, `Sources/Rebuild/RebuildSessionSetup.swift:65-79`, `Sources/Rebuild/RebuildWorkspace.swift:191,281-289,379-388`, `Sources/Rebuild/RebuildModelsView.swift:196-230`; `native-record-setup-needed-dark.png`, `native-models-dark.png`
- **Evidence:** On first run, Record shows "Install the local runtime" as the banner title, the hero title, the footer note ("…in Voice Models.") and the sidebar status. The banner body says "Recording needs microphone access and an installed voice model", even though the microphone was already granted. The footer sends users to **"Voice Models"**, but the sidebar page is **"Models & setup"**. Models & setup then shows the same title a fifth time, with a "Finish setup" button below an "Install runtime & voice model" button that does the same job.
- **Layman's term:** The app repeats one instruction everywhere and calls the place to fix it by the wrong name.
- **What's wrong:** Readiness copy is reused for title, body and hint without differentiation. "Local runtime" is an implementation term, and the banner body doesn't match the actual missing step.
- **Impact:** Moderate. First-run users take longer to find the one action that unblocks recording.
- **Significance:** High (first-run is the gate to every workflow)
- **Difficulty:** S
- **Fix:** Show one banner with a specific body ("Download the Parakeet voice model (≈2.5 GB) to start dictating") and one primary button. Give the hero a neutral "Setup needed" title. Rename "Voice Models" to "Models & setup" in `RebuildSessionSetup.swift`. Remove the duplicate "Finish setup" when the install button is already visible. Phrase the step for users ("Download voice model") rather than naming the runtime.
- **Grade lift:** B- → B

#### B2 — Preferences is one long scroll with a cross-reference you must hunt for
- **Where:** `Sources/Rebuild/RebuildPreferencesView.swift:48,140,175,188,256`; `native-preferences-dark.png`
- **Evidence:** One page holds Dictation modes, App rules, Recording, Microphone & feedback, Delivery, Library & privacy, Appearance & startup and Advanced & support. At 1084 pt tall the window shows only through Delivery. "Set fallback order in Advanced & support." is plain text, not a link, and the target is at the bottom.
- **Layman's term:** Settings is a long list, and one note says "see below" without taking you there.
- **What's wrong:** Mode management and app rules are workflow features, not preferences. With them on top, everyday toggles such as shortcut and Smart Paste sit lower on the page.
- **Impact:** Minor to moderate. Settings take longer to find.
- **Significance:** Medium
- **Difficulty:** M
- **Fix:** Make the cross-reference a link that scrolls to the section (`ScrollViewReader`). Consider moving Dictation modes and App rules to their own "Modes" page, and put Recording/Delivery first.
- **Grade lift:** B- → B

## C — Interaction Design & Workflow Quality — B- provisional

Setup gating on Record is correct. Record and file import are disabled until ready, practice is gated, and the microphone is requested only by explicit click (stated in copy). The Library-off and Meetings-empty states explain the consequence clearly. Recording, processing, cancel and retry exist in source with Esc wiring on the workspace (`RebuildWorkspace.swift:428-433`), but the HUD paths were not exercised.

#### C1 — Meetings can start with no Whisper model installed (confirmed defect)
- **Where:** `Sources/Rebuild/RebuildMeetingSession.swift:40-43,81-92`, `Sources/Rebuild/RebuildMeetingsView.swift:41,53-57`; `native-meetings-dark.png`
- **Evidence:** In the native first-run state the sidebar reads "Install the local runtime", yet **Start meeting** is the enabled, prominent button. `canStart` checks only busy/source/install-in-progress flags, not model readiness. The Whisper picker lists every `WhisperModel.allCases` ("base" was shown) while its caption says "Uses an already installed Whisper model". System audio is checked by default, so Start also leads to a Screen & System Audio Recording permission request.
- **Layman's term:** The app lets you record a 30-minute meeting it can't transcribe, and you only find out afterwards.
- **What's wrong:** Meeting readiness is not linked to model inventory. The failure appears at Process time, after capture. Audio is kept, so nothing is lost, but the time is.
- **Impact:** Moderate. A meeting can't be re-run, so a late failure is costly.
- **Significance:** High (P5 headline workflow)
- **Difficulty:** S–M
- **Fix:** List only installed Whisper models (disable or label the rest "Not installed"). Fold `modelInstalled` into `canStart`, with an inline callout and an "Open Models & setup" button. Consider leaving System audio unchecked until the user opts in. Add a state test that `canStart == false` with no installed model.
- **Grade lift:** B- → B (also lifts H)

#### C2 — The core global shortcut is off on a fresh install and missing from setup
- **Where:** `Sources/Rebuild/RebuildPreferencesView.swift:18,100-104`, `Sources/Rebuild/RebuildApp.swift:150-153`, `Sources/Rebuild/RebuildModelsView.swift:60,83`, `Sources/Rebuild/RebuildPracticeView.swift:17`; `native-preferences-dark.png`, `native-record-setup-needed-dark.png`
- **Evidence:** `rebuild.shortcutEnabled` defaults to `false`. Preferences shows the ⇧⌘Space key cap next to an **unchecked** "Enable recording shortcut", so a shortcut appears to exist but does nothing. The three setup steps (Microphone, Voice model, Try your first dictation) never mention the shortcut. Record shows only a small "Recording shortcut is off. Set up" line.
- **Layman's term:** The main way to use a dictation app ("press a key anywhere") is off, and setup never tells you.
- **What's wrong:** Leaving it off avoids key conflicts, which is a sensible default, but users have to discover it themselves. The Preferences control also shows two different states at once.
- **Impact:** Moderate. New users may think dictation only works from the window.
- **Significance:** High
- **Difficulty:** S
- **Fix:** Add a fourth setup step, "Choose a recording shortcut", with the recorder and a conflict hint, marked done when enabled. In Preferences, dim the key cap or show "Off" when disabled, or merge both controls into one recorder with a clear button.
- **Grade lift:** B- → B

#### C3 — "Cancel (Esc)" on the recorder HUD probably doesn't respond to Esc (plausible, runtime-unverified)
- **Where:** `Sources/Rebuild/RebuildRecorderView.swift:49,70-72`, `Sources/Rebuild/RebuildApp.swift:121-128`, `Sources/Views/Components/RecordingWindowComponents.swift:5-16`
- **Evidence:** The HUD is a `.nonactivatingPanel` with `becomesKeyOnlyIfNeeded`, and it is shown with `orderFrontRegardless()`, never made key. Its only Esc handler is SwiftUI `.onExitCommand`, which needs key focus. No global Esc or cancel monitor exists in `configureShortcuts()`. While dictating into another app, Esc goes to that app.
- **Layman's term:** The tooltip says Esc cancels, but pressing Esc while dictating into Mail probably affects Mail instead.
- **What's wrong:** The keyboard-cancel promise is not backed for the main hands-on-keyboard flow.
- **Impact:** Moderate if confirmed. A mistaken recording can only be cancelled with the mouse, and Esc may act in the target app.
- **Significance:** High (cancel/recovery is a core state)
- **Difficulty:** S–M
- **Fix:** Confirm with a hardware run under R2. Then either register a temporary Esc global hotkey only while `phase.isBusy` (released afterwards), or offer a configurable cancel shortcut. Otherwise change the help text to "Cancel".
- **Grade lift:** B- → B

## D — Accessibility & Inclusive UX — B- provisional

The source has 48 explicit accessibility labels/elements in `Sources/Rebuild`, labelled sidebar items and status, a "Final transcription in progress" spinner label, a combined live-draft element, session announcements (October D1) and semantic contrast tokens. None of this was verified at runtime. REA could not bind the window's AX tree, and VoiceOver and keyboard-only paths remain R4.

#### D1 — Key HUD state cues lack accessible equivalents (source review, unverified)
- **Where:** `Sources/Rebuild/RebuildRecorderView.swift:52-60,20-27`
- **Evidence:** The status dot is `accessibilityHidden`. Its meaning (recording vs silent-input warning) is also given in the title text, which is fine. The microphone/destination labels are clipped to one line with middle truncation and carry no accessibility value for the full name. The elapsed timer has no label (its reading cadence is unknown). Esc cancel is affected by C3.
- **Layman's term:** A screen-reader user may not hear which app the text will go to.
- **What's wrong:** Destination and timing are visual-first.
- **Impact:** Minor to moderate
- **Significance:** Medium
- **Difficulty:** S
- **Fix:** Add `.accessibilityLabel("Recording into \(destination) with \(mic)")` on the HUD container. Label the elapsed timer as "Elapsed" with update frequency limited. Run the R4 VoiceOver pass and record results.
- **Grade lift:** B- provisional → B once R4 evidence exists

## E — Responsive & Cross-State Experience — B-

The setup-needed, library-off, no-vocabulary, no-correction-model and no-meetings states are all designed (native). Light mode (offscreen) keeps the dark sidebar with a light canvas, a deliberate brand choice. The 870 pt minimum width is generous. Small-height behavior is unverified.

#### E1 — Meeting capture has no elapsed or remaining time and no level feedback (source)
- **Where:** `Sources/Rebuild/RebuildMeetingSession.swift:108`, `Sources/Rebuild/RebuildMeetingsView.swift:14-16,40-46`
- **Evidence:** During capture the only feedback is the static string "Recording meeting audio · 30 minute limit" plus a "Stop & keep audio" button. Dictation shows a timer and waveform, but Meetings shows neither, and there is no warning before the 30-minute auto-stop.
- **Layman's term:** During a meeting you can't see whether it's hearing anything or how long is left.
- **Impact:** Moderate. Silent capture or an unexpected stop at 30:00 goes unnoticed.
- **Significance:** Medium–High
- **Difficulty:** S
- **Fix:** Reuse `RebuildElapsedTime` and per-source level meters. Show "mm:ss of 30:00" and a callout at 25 minutes. Announce the auto-stop.
- **Grade lift:** B- → B

## F — Frontend Code & Design System Health — B (limited sample)

Centralized tokens (`RebuildDesign.swift`), reusable `RebuildSection`/`RebuildFormRow`/`RebuildCallout`/`RebuildStepHeader` and pure readiness/state types are healthy. Not deep-audited here. The duplication behind B1 (one `nextStep` string reused in four slots) is the main design-system smell.

## G — UI Performance — Not graded

No startup, render, Stop-to-paste or memory measurement was taken. Matched competitor performance is still open (roadmap G1/I1). No speed claim is made.

## H — Data Linkages & State Reliability — B

Record, Models, footer and practice derive from one readiness source and agreed in every native capture. Meetings is the exception (C1). The correction-model caption hard-codes figures for one machine ("about 0.4s … on M5 Pro", `Sources/Services/MLXModelManager.swift:77,83`), which is accurate as a benchmark note but is shown to every user as if it applied to them (see I1).

## I — Polish, Delight & Product Feel — B-

The copy is restrained and trustworthy ("On your Mac", "A little less typing.", "Nothing is requested automatically.").

#### I1 — Internal names and machine-specific figures show in the product
- **Where:** `Sources/Rebuild/RebuildWindowFactory.swift:12`, `Sources/Rebuild/RebuildApp.swift:15`, `Sources/Rebuild/RebuildStatusController.swift:15-16`, `Sources/Rebuild/RebuildStatusMenu.swift:22`, `Sources/Services/MLXModelManager.swift:77,83`; every native screenshot title bar
- **Evidence:** The window title, menu-bar tooltip and accessibility description, and the status-menu item "Open AudioWhisper Rebuild" all say **Rebuild**, while the sidebar wordmark says "AudioWhisper / Private dictation". The correction model descriptions cite "on M5 Pro".
- **Layman's term:** The app still carries its development codename.
- **Impact:** Minor. It reduces trust and polish, and VoiceOver reads "Rebuild".
- **Significance:** Medium (visible on every screen)
- **Difficulty:** XS
- **Fix:** Use "AudioWhisper" for user-facing strings. Keep `RebuildStorage.directoryName` as is to avoid a data migration. Rephrase timings as "≈0.4 s per short edit on a recent Apple Silicon Mac (measured on M5 Pro)" or show measured local timings after first use.
- **Grade lift:** B- → B

---

## Confirmed vs suggested vs unverified

- **Confirmed defects (native and source):** C1, C2 (default-off plus dual-state control), B1 (repetition and wrong page name), I1.
- **Plausible, needs a hardware check:** C3 (Esc on HUD), D1.
- **Suggestions:** A1, B2, E1.
- **Unverified states:** recording/processing/cancel/retry HUD, delivery outcomes, mode editor, populated Library/versions, meeting capture/processing, light mode native, small window, VoiceOver/keyboard, all performance.
