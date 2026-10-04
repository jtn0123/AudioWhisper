# UI/UX Grade Report

**Project:** AudioWhisper
**Audited:** 2026-10-03
**Stack:** macOS 14+ utility using SwiftUI, AppKit, AVFoundation, SwiftData, WhisperKit, and an embedded Python/MLX runtime
**Baseline:** `f3adb17` on `master`; all file/line evidence below refers to this commit, before the current polish work
**Runtime evidence:** User-reported core recording failure; source tracing; limited native-app inventory and process sampling. Checked-in snapshot inspection did not supply usable primary-screen visual evidence.
**Artifacts:** No fresh native workflow screenshot, recording, or timing capture. New [Setup layout previews](ui-ux-audit/README.md) were generated with ImageRenderer and inspected in light/dark; they show the polishing branch's new view and are not baseline runtime proof. Existing snapshots under `Tests/__Snapshots__/` are not treated as current runtime proof.

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Visual Design & Theme Cohesion | B− provisional | 1 |
| B | Layout, Information Architecture & Navigation | C | 1 |
| C | Interaction Design & Workflow Quality | D+ | 2 |
| D | Accessibility & Inclusive UX | C provisional | 2 |
| E | Responsive & Cross-State Experience | C− provisional | 1 |
| F | Frontend Code & Design System Health | B− | 1 |
| G | UI Performance & Asset Efficiency | C+ provisional | 1 |
| H | Data Linkages & State Reliability | D+ | 3 |
| I | Polish, Delight & Product Feel | C− | 3 |
| **Overall** | | **C− provisional** | **15** |

**Top 5 highest-leverage fixes:** H1, C1, B1, D1, C2

The first priority is a dependable path from opening the app to completing one recording. The user's observed sequence—“Ready,” recording shortcut, at least five permission asks, then a voice-model-not-installed error behind the dialogs—is a serious workflow failure. The source independently confirms incomplete readiness checks and competing permission/error presentations; it does not establish that five separate macOS microphone authorization requests were issued.

---

## Evidence Limits

The audit is deliberately tied to baseline `f3adb17`; implementation work in the current checkout does not raise the baseline grades. Native UI inspection was attempted through the available computer-use interface. App selection by name, bundle identifier, and application path timed out on each attempt, while surface inventory worked. A process sample of the idle app did not show a freeze; that is neither an interaction-performance measurement nor evidence that the reported workflow works.

The parent audit inspected `Tests/__Snapshots__/DashboardView-light.png`, `DashboardProvidersView-local-selected.png`, and `WaveformContainer-ready.png`. The overview and waveform images contain yellow “cannot render” placeholders, so they cannot substantiate composition, legibility, or aesthetic quality. No new native screenshots were captured. New Setup-only ImageRenderer previews do not establish the baseline app's runtime behavior. Visual/theme, keyboard/focus, VoiceOver, resizing, light/dark rendering, and performance judgments remain provisional until native rendered evidence is collected. No build or test was run by this report-writing pass.

Code-derived contradictions are stronger evidence: the menu command invokes a window toggle; readiness omits the selected model; Retry discards its retry target; processing clicks can start a recording; the duration timestamp is cleared before success. These findings do not require guessing how an unobserved screen looks. The arbitrary paste fallback and activation timeout are unsafe code contracts, with native failure reproduction still outstanding.

---

## A — Visual Design & Theme Cohesion — B− provisional

The source has an appropriate restrained direction for a desktop transcription utility: adaptive AppKit surface/text colors, a coral accent, a spacing scale, and separate typography roles in `Sources/Views/Dashboard/DashboardView.swift:19-107`. Overview and Visuals cards use the shared radius scale, while Input and Categories still use local two-point card radii. Aesthetic quality cannot be confirmed from placeholder snapshots, so this is a code-informed provisional grade.

#### A1 — Apply the shared card tokens consistently
- **Where:** `Sources/Views/Dashboard/DashboardView.swift:93-107`; `Sources/Views/Dashboard/DashboardRecordingView.swift:260-273`; `Sources/Views/Dashboard/DashboardCategoriesView.swift:218-230`; `Sources/Views/Dashboard/DashboardHome+Sections.swift:39-47`.
- **Evidence:** The shared medium card radius is 10 points; Overview uses it, but Input and Categories each define a private `cardStyle()` with a two-point radius and repeated border/shadow literals.
- **Layman's term:** Some settings pages use a different card shape from the rest of the app.
- **What's wrong:** Existing local styles bypass the app's own card tokens. The inconsistency is in source; its visual severity requires valid native screenshots.
- **Impact:** Minor — uneven finishing and more work to keep settings pages visually consistent.
- **Significance:** Low — follow core recording repairs rather than changing the visual direction.
- **Difficulty:** S
- **Fix:** Share a Dashboard card modifier using the existing radius, surface, border, and shadow choices. Apply it to these duplicate styles and compare native light/dark screenshots before calling the visual result verified.
- **Grade lift:** B− → B provisional (removes demonstrated token drift while preserving the established identity).

---

## B — Layout, Information Architecture & Navigation — C

The sidebar has clear named destinations and accessible selected-state semantics in `DashboardView.swift:128-149,254-286`. However, first-run navigation goes from a visual-style welcome to Overview while essential setup is split among Input, Models, and Permissions. Users must infer the route to a usable recording before the app offers recording commands.

#### B1 — Guide first run through microphone and selected-model setup
- **Where:** `Sources/Views/WelcomeView.swift:92-175,205-242`; `Sources/Managers/Windows/WelcomeWindow.swift:46-58`; `Sources/Views/Dashboard/DashboardView.swift:157,184-188,429-439`; `Sources/Views/Dashboard/DashboardPermissionsView.swift:46-79`; `Sources/Views/Dashboard/DashboardProviders+LocalWhisper.swift:83-145`.
- **Evidence:** Welcome primarily renders a waveform preview and eight visual-style choices. Get started calls `WelcomeWindow.finish()`, which marks welcome complete and opens the Dashboard. Dashboard's initial selection is Overview; microphone permission and selected-model installation are separate destinations. The user's reported model-missing failure occurred after attempting to record.
- **Layman's term:** The app lets you choose its appearance before it helps you make your first recording.
- **What's wrong:** The mandatory setup path is not action-guided. The completion CTA records that welcome was seen rather than that recording prerequisites are satisfied.
- **Impact:** Major — new or incomplete installations can reach a recording command without knowing which required setup remains.
- **Significance:** High — first successful transcription is the product's central onboarding outcome.
- **Difficulty:** M
- **Fix:** Add a focused recording-setup page showing microphone status, engine selection, the selected model's installation/progress, and one next action. Route first-run completion and unmet recording prerequisites there. Keep visual customization available after mandatory setup and make optional Smart Paste permission a separate step.
- **Grade lift:** C → B− (makes the next required action explicit and shortens the route to one successful recording).

---

## C — Interaction Design & Workflow Quality — D+

The core workflow has multiple competing entry points and inconsistent transition guards. The user reported repeated permission asks followed by a hidden missing-model error, and the source permits reentrant permission presentation and overlapping recording/processing actions. Hotkeys already block during transcription, but mouse recording does not follow that same contract.

#### C1 — Present one permission request at a time
- **Where:** `Sources/Managers/PermissionManager.swift:94-135,157-183`; `Sources/Views/ContentView.swift:101-140`; `Sources/Views/Dashboard/DashboardPermissionsView.swift:61-67`; `Sources/Views/ContentView+Lifecycle.swift:35-49`.
- **Evidence:** The user reports at least five permission asks after pressing the recording key. Baseline permission orchestration owns three independent presentation booleans; `proceedWithPermissionRequest()` has no reentry guard and schedules optional Accessibility presentation after 300 ms without awaiting microphone completion. The recovery check tests its presentation flag before a delayed 500 ms task sets it. The microphone API call itself does check `needsRequest`, so five simultaneous native microphone requests are not proven by source.
- **Layman's term:** One recording attempt can turn into several competing permission dialogs.
- **What's wrong:** Permission requests are not a single serialized interaction. Repeated actions can queue stale optional-permission or recovery presentations while another prompt remains unresolved.
- **Impact:** Major — users are blocked by dialogs and can lose the main error or next required action behind them.
- **Significance:** High — permission completion is mandatory for the first recording.
- **Difficulty:** M
- **Fix:** Track one active permission presentation and one in-flight request. Ignore repeated request actions until that request finishes; wait for the microphone response before considering optional Accessibility. Cancel or invalidate delayed presentation tasks on completion/dismissal. Disable Request Access while requesting. Inject microphone authorization/request closures so tests can hold the completion and prove repeated actions yield one request and one presentation.
- **Grade lift:** D+ → C+ (removes the user-reported dialog cascade's demonstrated orchestration causes).

#### C2 — Reject recording actions during processing and isolate each run
- **Where:** `Sources/Views/ContentView.swift:64-78`; `Sources/ViewModels/RecordingViewModel.swift:202-223,280-313`; `Sources/ViewModels/RecordingViewModel+Transcription.swift:41,220-269,308-315`; `Sources/App/AppDelegate+Hotkeys.swift:112-118`.
- **Evidence:** Mouse taps start recording whenever the recorder is stopped and success is not visible, even if transcription is processing. The view model's start method also lacks a processing guard. Replacing a task cancels its predecessor, whose cancellation tail can still clear shared processing state; delayed success/paste callbacks are not tied to a run identifier. The hotkey path already explicitly ignores processing-time presses.
- **Layman's term:** Clicking the busy recorder can start another session, and the old session can interfere with the new one.
- **What's wrong:** Entry points disagree about whether recording is allowed during processing. Completion, cancellation, and delayed presentation callbacks lack a current-session check.
- **Impact:** Major — overlapping sessions can produce incorrect progress, unexpected microphone activity, or late paste/window actions.
- **Significance:** High — this affects repeated everyday recording.
- **Difficulty:** M
- **Fix:** Enforce the busy guard in the view model and reflect it in the primary control. Associate each run and delayed callback with a session identifier; only current callbacks may mutate state. Add production-path tests for clicking during a withheld transcription and cancelling/replacing a run before the old task finishes.
- **Grade lift:** D+ → C+ (makes repeated recording and cancellation predictable).

---

## D — Accessibility & Inclusive UX — C provisional

Sidebar navigation and category editing include useful labels and selected/category traits, and permission rows expose their state in text (`DashboardView.swift:280-286`, `DashboardCategoriesView.swift:139-146`, `DashboardPermissionsView.swift:171-180`). The primary recording control instead collapses most states into “Idle,” while Whisper selection is a gesture-based row. Reduce Motion is read centrally but does not reach the processing shimmer; actual VoiceOver, keyboard, and contrast verification remains outstanding.

#### D1 — Describe the primary control's action and full state
- **Where:** `Sources/Views/Components/Waveform/WaveformContainer.swift:70-120,142-144`; `Sources/Views/Dashboard/DashboardProviders+LocalWhisper.swift:83-145,168-175`; `Sources/Views/Components/UnifiedModelRow.swift:81-91,189-198`.
- **Evidence:** The active recording button's accessible label is fixed to “Recording waveform,” with value “Active” or “Idle.” Processing, success, permission, and error states therefore share “Idle.” Whisper selection is an `HStack.onTapGesture`; its icon-only trash action lacks a model-specific label. The reusable correction-model row already demonstrates explicit accessible selection and download/delete labels.
- **Layman's term:** A screen reader does not clearly tell you what the record control will do or which model an action affects.
- **What's wrong:** Essential controls do not expose action-specific labels and complete status. Whisper's custom model selection does not use the accessible control pattern already present elsewhere.
- **Impact:** Major — assistive-technology users lack dependable guidance for recording and model setup.
- **Significance:** High — these are required product actions.
- **Difficulty:** S
- **Fix:** Map recording states to clear labels, values, hints, and disabled behavior; use the same busy rules as C2. Convert Whisper selection to an accessible selection button with separate explicitly labeled model actions. Verify keyboard focus and VoiceOver in the native app, including processing and missing-model states.
- **Grade lift:** C → B− provisional (aligns essential controls with the stronger accessible patterns already in the app).

#### D2 — Respect Reduce Motion in processing feedback
- **Where:** `Sources/Views/Components/Waveform/WaveformContainer.swift:45-49,163-168`; `Sources/Views/Components/Waveform/WaveformSubviews.swift:19-46`.
- **Evidence:** `WaveformContainer` reads `accessibilityReduceMotion`, but passes only `processingAnimated` to `ProcessingShimmerView`. That child starts a repeating 1.6-second animation whenever its `animated` flag is true.
- **Layman's term:** The busy indicator keeps moving even when the user has asked macOS to reduce motion.
- **What's wrong:** The centrally available accessibility preference does not govern this decorative animation.
- **Impact:** Moderate — motion-sensitive users retain unnecessary repeating animation during every transcription.
- **Significance:** Medium — frequent core-workflow feedback should honor platform preferences.
- **Difficulty:** XS
- **Fix:** Disable shimmer animation when Reduce Motion is enabled and retain a clear static processing indicator. Verify the live preference and deterministic nonanimated render.
- **Grade lift:** C → C+ provisional (closes a specific reduced-motion gap).

---

## E — Responsive & Cross-State Experience — C− provisional

History has dedicated loading/empty/error handling and a debounced paginated view model (`TranscriptionHistoryView.swift:38-83`, `TranscriptionHistoryViewModel.swift:57-135`). Recording setup lacks an equivalent coherent cross-state surface: readiness, permission sheets, missing-model redirection, and unattached errors compete. Native resizing, long-content behavior, full-screen focus, and light/dark rendering could not be verified, so those portions remain provisional; C1 and H1 own the primary permission/readiness repairs.

#### E1 — Keep recording errors attached to an actionable setup state
- **Where:** `Sources/Views/ContentView.swift:53-55,101-140,160-164`; `Sources/Utilities/ErrorPresenter.swift:60-72,145-181`; `Sources/ViewModels/TranscriptionCoordinator.swift:180-199`; `Sources/Views/Dashboard/DashboardView.swift:157,429-439`.
- **Evidence:** The user reports a missing-model error behind permission dialogs. The recording view schedules a standalone error presenter and immediately clears its error flag; the presenter uses an unattached `NSAlert.runModal()`. Missing-model handling also opens the Dashboard, whose default navigation destination is Overview. There is no single state transition that resolves permissions and then shows the relevant model action.
- **Layman's term:** The error can disappear behind other windows, and the page it opens does not immediately show the fix.
- **What's wrong:** Error visibility and recovery destinations are not coordinated with permission/setup presentation. A modal dialog adds another competing surface rather than keeping the problem and next action together.
- **Impact:** Major — users can be blocked without a visible recovery step.
- **Significance:** High — missing prerequisites are common first-run and reinstall states.
- **Difficulty:** M
- **Fix:** Present unmet prerequisites inline on B1's setup page, select that destination explicitly, and reserve attached window alerts for unexpected failures. Serialize remaining alerts with C1's presentation state. Verify denied permission, missing model, download failure, cancellation, and retry in native UI.
- **Grade lift:** C− → C+ provisional (turns failure states into reachable next actions).

---

## F — Frontend Code & Design System Health — B−

The code has useful theme tokens and leaf waveform components, with transcription logic delegated away from the SwiftUI view. `ProviderSettingsState` provides observable settings state, but readiness and some model-state work remain duplicated in view extensions. These copies directly contribute to misleading UI truth; A1 covers card-token reuse, while H1 owns the readiness behavior itself.

#### F1 — Centralize the setup contract instead of copying readiness predicates
- **Where:** `Sources/Stores/ProviderSettingsState.swift:45-51,69-74`; `Sources/Views/Dashboard/DashboardProviders+EngineSelector.swift:159-165`; `Sources/Views/Dashboard/DashboardProviders+LocalWhisper.swift:254-269`; `Sources/App/AppStatus.swift:84-104`; `Sources/Views/ContentView+Status.swift:6-14`.
- **Evidence:** Provider readiness predicates are repeated in the view and settings-state container; the recording status owner separately infers Ready only from microphone permission. The view extension also maintains cached downloaded/model-state arrays alongside the manager's observable download state.
- **Layman's term:** Different screens calculate “ready” in different ways, so one fix does not automatically fix them all.
- **What's wrong:** There is no shared setup result consumed by menu, recorder, onboarding, and model settings. Keeping copies synchronized makes production polish fragile.
- **Impact:** Moderate — setup fixes can diverge again between recording entry points and settings.
- **Significance:** High — a single truthful contract supports the highest-priority fixes H1 and B1.
- **Difficulty:** M
- **Fix:** Define a small shared recording-setup state with explicit prerequisite reasons, using existing model and permission owners as inputs. Consume it across entry points and status presentation; remove copied readiness formulas rather than adding another calculation. Add tests to the shared production helper and its entry-point callers.
- **Grade lift:** B− → B (makes readiness corrections durable without a broad frontend rewrite).

---

## G — UI Performance & Asset Efficiency — C+ provisional

The source includes important bounded work: history uses page-size-limited fetches and a lazy stack, and the recent-menu cache fetches only ten records (`TranscriptionHistoryViewModel.swift:41,108-128`, `TranscriptionRecordsList.swift:16-35`, `DashboardWindowManager.swift:38-57`). Waveform frame timers can stop on view disappearance, but live preview rendering runs continuously at about 30 FPS and is not tied to native window occlusion. No startup, input-latency, frame-time, or repeated-navigation measurements were collected; the idle sample alone does not justify a higher confidence grade.

#### G1 — Suspend live previews when their native window is not visible
- **Where:** `Sources/Views/Components/Waveform/WaveformPreviewHelpers.swift:16-44,75-105`; `Sources/Views/Dashboard/DashboardVisualsView.swift:10-35,59-75`; `Sources/Views/WelcomeView.swift:83-87,163-175`; `Sources/Views/Components/Waveform/FrameTimer.swift:28-38`.
- **Evidence:** The shared sampler publishes synthetic audio data on a main-thread timer every 0.033 seconds; Visuals renders eight animated tiles plus a large preview. Start/stop is bound to SwiftUI appearance/disappearance, with no explicit minimized/occluded-window or inactive-app signal. This is a code-observed work pattern; excess CPU, battery loss, or visible jank has not been measured.
- **Layman's term:** The visual gallery can keep drawing animation when its window is hidden behind other work.
- **What's wrong:** View lifetime is used as a proxy for whether a preview is visible to the user. Native window visibility/occlusion and Reduce Motion are not part of the preview sampler's policy.
- **Impact:** Moderate — unnecessary animation work is possible during long sessions, with actual cost still unmeasured.
- **Significance:** Medium — utility settings should remain cheap while the user records or works in another app.
- **Difficulty:** S
- **Fix:** Add a native window-visibility/occlusion signal to preview animation policy and suspend decorative sampling when the window is minimized, fully occluded, or Reduce Motion is enabled. Measure CPU/frame behavior for visible versus minimized Visuals and collect recording-input latency before claiming an optimization.
- **Grade lift:** C+ → B− provisional (avoids an identified unnecessary-work path once native measurements confirm the result).

---

## H — Data Linkages & State Reliability — D+

The app's most serious trust gap is that Ready does not mean the selected recording stack is usable. The source also proves a nonworking retry contract and an unsafe paste-target fallback. The user-reported first-recording failure strengthens this category's grade; B1 and C1 address presentation and sequencing, while the following items address the underlying state contracts.

#### H1 — Make Ready mean the selected recording stack is usable
- **Where:** `Sources/App/AppStatus.swift:81-104`; `Sources/Views/ContentView+Status.swift:6-14`; `Sources/Views/Dashboard/DashboardProviders+EngineSelector.swift:159-165`; `Sources/Stores/ProviderSettingsState.swift:45-51`; `Sources/Services/LocalWhisperService.swift:25-27`.
- **Evidence:** The recorder initializes to `.ready`, and later sets Ready from microphone permission alone. Whisper's engine badge says Ready when any model is installed, even if the selected model is absent; transcription explicitly rejects that absent selected model. Parakeet's badge uses Python environment readiness without checking the selected model. The user reports Ready immediately preceding permission prompts and a missing-model error.
- **Layman's term:** The app says it is ready before it has what it needs to transcribe.
- **What's wrong:** UI readiness omits required selected-model and environment state and does not drive a shared gate at every recording entry point. Optional Smart Paste permission is mixed into mandatory recording permission orchestration.
- **Impact:** Major — the main status misleads users into a recording attempt that can fail after they have spoken.
- **Significance:** High — dependable readiness is essential to trusting a transcription tool.
- **Difficulty:** M
- **Fix:** Build the shared setup contract described in F1, with microphone, selected-engine/model, environment, and hardware readiness. Default to checking/setup rather than Ready until inputs are known. Gate menu, hotkey, press-and-hold, and view-model recording through it; render the first unmet prerequisite and route to B1's setup action. Test an installed nonselected Whisper model, no selected model, pending/denied permission, and supported/unsupported engines.
- **Grade lift:** D+ → C+ (removes the central mismatch behind the reported failed recording).

#### H2 — Require the intended app to be active before automatic paste
- **Where:** `Sources/ViewModels/RecordingViewModel+Paste.swift:78-122,153-237`; `Sources/Managers/Windows/WindowController.swift:128-164`; `Sources/Managers/PasteManager.swift:229-232`.
- **Evidence:** Missing or terminated targets fall back to the first regular running application, arbitrarily excluding Slack and Cron. Activation waiting resumes normally after 500 ms without requiring target activation. The eventual synthetic paste is posted to the system session, so the foreground app receives it. This is an unsafe source contract; a native wrong-app paste was not reproduced in this audit.
- **Layman's term:** If the original app is unavailable or does not activate, text can be pasted somewhere else.
- **What's wrong:** Automatic paste does not preserve and verify the session's intended destination. Timeout is treated as success rather than a failed activation.
- **Impact:** Major — unexpected text insertion or disclosure to an unrelated app.
- **Significance:** High — Smart Paste is a principal productivity feature and must be predictable.
- **Difficulty:** M
- **Fix:** Capture a per-session target, remove arbitrary automatic fallback, and confirm target activation immediately before sending paste events. On missing target or activation failure, retain the text on the clipboard and show manual-paste feedback. Inject activation/paste interfaces for deterministic target-loss and timeout tests, then verify native focus return.
- **Grade lift:** D+ → C+ (protects the automatic-paste destination).

#### H3 — Preserve the failed model as the Retry target
- **Where:** `Sources/Views/Dashboard/DashboardProviders+LocalWhisper.swift:61-71,225-237`; `Sources/Stores/ProviderSettingsState.swift:24-29`; `Tests/Views/Dashboard/DashboardProvidersLocalWhisperTests.swift:79-117`.
- **Evidence:** Retry picks the newest `downloadStartTime` entry, but the failure path removes the failed model's entry. With no active downloads, Retry only clears the error; with another active download, it chooses that other model. Existing tests manually mutate local dictionaries and do not invoke production Retry behavior.
- **Layman's term:** Pressing Retry can dismiss the error without retrying, or choose a different model.
- **What's wrong:** Active download timing is incorrectly used as failed-action identity. The retry target does not survive the error it is meant to recover from.
- **Impact:** Moderate — model setup recovery cannot be trusted.
- **Significance:** High — users need a working recovery action for large model downloads.
- **Difficulty:** S
- **Fix:** Store the failed model and error together, separately from active download timing. Have Retry invoke that exact model and test the production action with and without another download in progress.
- **Grade lift:** D+ → C− (restores a specific setup recovery path).

---

## I — Polish, Delight & Product Feel — C−

The app has a distinctive waveform surface and completion feedback rather than a generic utility shell, but visible copy and recap details contradict behavior. “Start Recording” toggles visibility, duration is ordinarily zero, and configurable shortcut hints remain hardcoded. These are concrete finishing defects; reliability work in H1, C1, and C2 remains more valuable than additional effects.

#### I1 — Make the primary menu command do what its name promises
- **Where:** `Sources/App/AppDelegate+Menu.swift:37-42`; `Sources/App/AppDelegate+RecordingWindow.swift:7-12`; `Sources/Managers/Windows/WindowController.swift:54-59`; `Sources/App/AppDelegate+Hotkeys.swift:102-125`.
- **Evidence:** The menu labels its action Start Recording but selects `toggleRecordWindow`. That action only creates/toggles the overlay; a visible overlay is hidden rather than starting or stopping the recorder.
- **Layman's term:** You click Start Recording and get a window toggle instead.
- **What's wrong:** Primary command copy and behavior disagree. The menu does not expose recording/processing state through its title or availability.
- **Impact:** Moderate — a common first action feels broken and may remove recording feedback.
- **Significance:** High — menu recording is an advertised entry point.
- **Difficulty:** S
- **Fix:** Route the menu through a direct recording action using H1's setup gate and C2's busy rules. Make titles and enabled states reflect idle, recording, and processing. Verify menu-started recording captures the original app and behaves consistently with the configured shortcut.
- **Grade lift:** C− → C+ (makes the main menu action predictable).

#### I2 — Show the configured shortcut everywhere
- **Where:** `Sources/Views/Components/Waveform/WaveformSubviews.swift:100-114`; `Sources/Views/WelcomeView.swift:118-145`; `Sources/App/AppDelegate+Menu.swift:37-42`; `Sources/Views/Dashboard/DashboardRecordingView.swift:96-104`.
- **Evidence:** Input stores and displays the configured `globalHotkey`, while the ready overlay and welcome preview hardcode Command Shift Space. The menu also fixes its recording key equivalent to that default.
- **Layman's term:** Changing the shortcut leaves other parts of the app showing the old keys.
- **What's wrong:** Shortcut feedback is not derived from the same setting that drives configuration.
- **Impact:** Moderate — users can follow instructions that no longer match their chosen recording trigger.
- **Significance:** Medium — keyboard recording is the product's fastest routine path.
- **Difficulty:** S
- **Fix:** Use a shared display/parsed-shortcut representation for Input, overlay, welcome accessibility copy, and menu equivalent; clarify when the configured trigger opens the overlay rather than recording immediately. Verify a nondefault shortcut across all surfaces.
- **Grade lift:** C− → C+ (keeps instructions aligned with user configuration).

#### I3 — Display the actual completed recording duration
- **Where:** `Sources/Views/Components/Waveform/WaveformContainer.swift:127-134,294-301`; `Sources/Views/Components/Waveform/WaveformSubviews.swift:121-135`; `Sources/ViewModels/RecordingViewModel+Transcription.swift:60-62`.
- **Evidence:** Leaving recording for processing clears `recordingStartedAt` because the new state is not success. The later success recap receives nil and renders a zero duration. Retaining a start timestamp alone would also include processing time rather than capture duration.
- **Layman's term:** A successful recording can say it lasted 0.0 seconds.
- **What's wrong:** The recap's data is discarded before success, and the widget derives elapsed wall time instead of using the recorder's completed duration.
- **Impact:** Minor — inaccurate confirmation makes the app feel unfinished.
- **Significance:** Medium — the completion surface appears after every recording.
- **Difficulty:** S
- **Fix:** Pass the recorder's completed session duration into success presentation and keep it stable through processing. Use an explicit absence state for imported files or unavailable duration rather than inventing zero. Check recording → processing → success and cancellation transitions.
- **Grade lift:** C− → C (repairs misleading completion detail).

---

## Implemented Polish — Native Verification Still Open

The baseline grades above remain unchanged. The first batch is implemented with automated regression evidence:

- **H1/B1:** A focused Setup destination owns microphone and selected-model readiness. First-run completion and unmet recording prerequisites select it explicitly. Ready requires microphone authorization and the selected Whisper model, or Parakeet environment plus the selected cached model. Checking is the initial status. Install state survives navigation, install targets are captured, and refreshes coalesce when selection changes.
- **C1:** Permission interactions have one presentation owner and a synchronous single-flight request. Optional Accessibility waits for the microphone outcome; Setup requests microphone only. Launch no longer automatically prompts behind Welcome. Three baseline-compatible regressions failed before the change; repeated requests plus success/denial cases now pass.
- **H3:** Whisper Retry retains and retries the failed model even when another download is active.
- **I1:** Start/Stop Recording in the menu invokes recording actions with the same prerequisites; headless source/test checks are complete, native recording/focus proof remains open.
- **C2 partial:** Processing-time recording actions are ignored and the primary control disabled. Session identifiers, stale cancellation cleanup and delayed callback ownership remain open.
- **D1 partial:** Primary record-control labels expose action/status. Whisper selection/delete accessibility and native keyboard/VoiceOver checks remain open.
- **E1 partial:** Known unmet prerequisites are prevented before recording and shown inline in Setup. Unexpected alert ownership and import-path recovery remain open.

The full Swift suite passed on the latest source (2,946 discovered tests), and 171 focused checks passed. Strict lint, Python typing, and the universal arm64/x86_64 local app build passed. Attachment to the rebuilt app also timed out; the running app was not restarted and no native permission journey is claimed. The [light](ui-ux-audit/setup-preview-light.png) and [dark](ui-ux-audit/setup-preview-dark.png) Setup layout previews were inspected: required steps, picker controls, installation action and next-step guidance are readable. These previews use forced incomplete setup in an isolated test process; they do not prove permission dialogs, downloads, resizing, keyboard focus, VoiceOver, or actual recording/paste behavior.

Native verification must still cover clean/incomplete setup, repeated permission actions, denied permission, missing selected model, failed installation/retry, processing clicks, menu recording, and focus/paste behavior. App attachment timeouts remain the concrete blocker. Capture native light/dark and error-state screenshots before regrading visual categories.
