# UI/UX Grade Report — f30c081

**Project:** AudioWhisper Rebuild
**Audited:** 2026-10-06
**Code:** `f30c081ed0bc324bf29c882052a6033d7028783b` on `rebuild/native-v2`, clean when inspected.
**Stack:** Native macOS AppKit window management, SwiftUI workspace/HUD, Observation session state, local SwiftData history and Python MLX inference.
**Runtime evidence:** Fresh native Tahoe 26.6.2 Record, populated Library, Models, Writing, Preferences, recording HUD and actual Smart Paste screenshots; the immediately preceding integration run also supplies model-menu/relaunch evidence. Fresh desktop acceptance passed ten shortcut/start/cancel cycles and one fixture-driven Whisper transcription/paste. No generated UI or browser simulation.
**Artifacts:** `.Codex/ui-ux-audit/2026-10-06-f30c081/` and `.Codex/bench/2026-10-06-qwen-integration/vm-ui/`; historical artifacts are explicitly identified below.

IDs belong to **f30c081 UI**; use “UI E1” for this report.
The [codebase report](grade-report-f30c081.md) has a separate ID namespace.
This original pass changed audit documentation/evidence only.

**Remediation, 2026-10-06:** UI C1 and UI E1 are complete; five items remain.
[Subsequent fixes and native evidence](fixes-next5-2026-10-06/README.md) are
separate from the baseline letter grades below.

## Summary

| ID | Category | Grade | Items | Plain meaning |
|---|---|---|---:|---|
| A | Visual Design & Theme Cohesion | B+ | 0 | Distinctive, consistent, restrained native utility design |
| B | Layout, Information Architecture & Navigation | B+ | 1 | Cleanup choices now explained; voice choices could be equally clear |
| C | Interaction Design & Workflow Quality | B | 2 | Good controls/recovery; corrected text needs an escape hatch and installs need progress |
| D | Accessibility & Inclusive UX | B-, provisional | 1 | Useful labels and keyboard actions; faint recording timer and no full VoiceOver proof |
| E | Responsive & Cross-State Experience | C+ | 0 | Populated Library makes the native window taller than its display |
| F | Frontend Code & Design System Health | B+ | 0 | Shared view primitives, small purpose-specific views and observable state |
| G | UI Performance & Asset Efficiency | B, provisional | 1 | Bounded rows and stopped timers; large exports still share the UI actor |
| H | Data Linkages & State Reliability | B+ | 0 | Readiness/retry/invalidation have real coverage; semantic trust remains a separate weakness |
| I | Polish, Delight & Product Feel | B+ | 0 | Considered copy/model guidance; unfinished details are concentrated in optional workflows |
| **Overall** | | **B** | **5** | Good native core workflow, with confirmed Library layout and cleanup-control gaps |

**Remaining priorities:** UI C2 → UI G1 → UI C3 → UI B1 → UI D1.

## Evidence limits

The root agent obtained fresh 2026-10-06 native screenshots and unattended desktop acceptance, which this delegated pass inspected. `identity.json` establishes exact host/guest executable identity at source `f30c081ed0bc324bf29c882052a6033d7028783b` (SHA-256 `e322ec9b139c8f120dbd85f0cfeb704f22f6535bb336670a2be1ae4ef450e2e6`). `desktop/report.json` records ten real guest shortcut/start/cancel cycles, a fixture-driven Whisper transcription and exactly one observed native Smart Paste into TextEdit; signature verification passed. This is synthetic guest key/virtual microphone evidence, not physical host hardware or notarized release acceptance. No new permission prompts were reported by the root runner.

The immediately preceding model integration screenshots additionally demonstrate all five cleanup choices, recommended Qwen3.5 guidance, separate download/memory estimates and persisted Qwen3.8 selection. The integration report records 128 physical-Mac production edits and packaged-daemon checks. Neither run supplies new startup/frame-time measurements. A recaptured `library.png` was inspected and confirms the actual populated Library, including the fresh fixture transcript. Its overflow was then reproduced twice and measured with native window geometry in `library-sizing.json`; it is a confirmed app defect, not a screenshot framing artifact. The guest menu bar displays October 7 because its clock is UTC; this audit ran October 6 in the host's Pacific timezone.

The fresh HUD screenshot confirms the faint timer on a bright desktop document. Historical 2026-10-04 VM screenshots additionally show minimum-size Preferences and the recorder above a full-screen document. The affected layout sources are unchanged since `187eacd`; historical visual provenance remains explicit. The older dark Library/model screenshots are corroborating theme evidence, not current settings screenshots. No host UI fallback or permission interaction was used. VoiceOver, keyboard-only complete journeys, Increased Contrast/Reduce Transparency, multi-display/Sonoma, physical hold/disconnect/sleep, large-library stall duration and fresh startup/frame times are unverified, not presumed broken.

## A — Visual Design & Theme Cohesion — B+

1. All five fresh workspace screens have a coherent paper/ink/rust palette, serif page title, consistent section cards and strong selected-navigation state (`Sources/Rebuild/RebuildWorkspace.swift:5`, `:57`, `:97`, `:109`; `.Codex/ui-ux-audit/2026-10-06-f30c081/{record,library,models,writing,preferences}.png`).
2. New model descriptions and memory guidance fit the existing visual hierarchy rather than becoming another disconnected setup panel. Native controls are conventional and recognizable.
3. Historical dark-theme screenshots corroborate a consistent alternate appearance; no fresh dark-mode contrast certification is implied. No current additional visual defect was established.

## B — Layout, Information Architecture & Navigation — B+

1. Record, Library, Models & setup, Writing profiles and Preferences separate the core workflow from optional configuration (`RebuildWorkspace.swift:36`). Setup names its two essentials explicitly (`RebuildModelsView.swift:15`).
2. Current Writing UI fixes the old cleanup-model guidance finding: friendly names, recommended badge, measured speed/memory and separate download size are rendered (`RebuildWritingView.swift:30`; `vm-ui/model-options.png`, `qwen38-relaunched.png`).
3. Voice selection remains version/language-led rather than explaining the English recommendation.

#### UI B1 — Explain the English voice choice

- **Where:** `Sources/Rebuild/RebuildModelsView.swift:37-54`, `Sources/Services/MLXModelManager.swift:56-86`; historical native `.Codex/ui-ux-audit/2026-10-04-regrade/models-ready.png`.
- **Evidence:** Current source still labels Parakeet as “fast & multilingual” and its options only “v3 · 25 languages” / “v2 · English.” Unlike cleanup selection, it gives no recommended English choice or brief quality/speed reason. The voice picker source is unchanged since the prior report.
- **Layman's term:** Explain which voice engine most English speakers should pick.
- **What's wrong:** The app now guides cleanup selection well but leaves the corresponding voice choice comparatively technical.
- **Impact:** Minor — users may assume the higher version is automatically better for English.
- **Significance:** Medium — selection affects dictation, although the English default already reduces the risk.
- **Difficulty:** S
- **Fix:** Label v2 as the recommended English option and retain v3 for multilingual use; add a brief benchmark-grounded reason and hardware scope, without presenting local samples as universal accuracy guarantees.
- **Grade lift:** B+ → A- for model-choice clarity, subject to full setup usability validation.

## C — Interaction Design & Workflow Quality — B

1. Recording controls, admission guards and retry preservation are explicit and meaningfully tested (`RebuildSession.swift:210`, `:342`, `:365`; `Tests/RebuildStartupTests.swift`, `Tests/RebuildSessionTests.swift`). Fresh native guest acceptance establishes ten shortcut/start/cancel cycles and actual Whisper transcription/Smart Paste; `desktop/recording-visible.png` shows accessible Cancel/Finish controls. Session IDs fence stale delivery and normal controls remain cancellable.
2. Successful cleanup replaces the only transcript exposed to the workspace; there is no compare/restore-original workflow. Actual production edits still sometimes omit meaning according to `.Codex/bench/2026-10-06-qwen-integration/README.md`.
3. Correction downloads now reach 6.0/12.7 GB, but Writing offers only generic install feedback. App-specific mappings also expose identifiers and stale running-app choices.

#### ~~UI C1~~ ✓ done 2026-10-06 — Let users compare and restore the original transcript

- **Where:** `Sources/Services/TranscriptionPipeline.swift:9-16`, `Sources/Services/SemanticCorrectionService.swift:12-25`, `Sources/Rebuild/RebuildSession.swift:296-310`, `Sources/Rebuild/RebuildWorkspace.swift:221-242`; `.Codex/bench/2026-10-06-qwen-integration/README.md`.
- **Evidence:** The result exposes final text plus a correction outcome whose successful value contains only corrected text. Session assigns `result.text`, copies/saves it, and the workspace displays one editor with Copy. Original text is surfaced only on correction failure, despite recorded successful edits with unwanted omissions/formatting.
- **Layman's term:** If cleanup changes what you meant, let you get your own words back.
- **What's wrong:** Recovery covers a failing model but not a model that successfully returns an undesirable rewrite. Disabling cleanup afterward cannot recover the prior source.
- **Impact:** Major — a cleaned transcript can lose a meaningful detail without a simple way to inspect or restore it.
- **Significance:** High — preserving dictated intent is central to this product.
- **Difficulty:** M
- **Fix:** Carry raw text and applied profile/model alongside the final text; offer Original/Cleaned comparison and Use original/Copy original actions. Keep auto-delivery configurable and ensure restore does not produce an unexpected second paste. Add meaningful pipeline/session recovery tests.
- **Grade lift:** B → B+, by restoring user control over uncertain edits; model-fidelity improvements remain separately necessary.

**UI C1 validation:** Original/final propagation, restore/copy without a second delivery, history-off privacy, disk round-trip and legacy schema migration pass. Native Library compare/copy visuals are checked with the final package; these recovery controls complement the semantic guards and do not prove all model wording is correct.

#### UI C2 — Show correction-install progress and allow cancellation

- **Where:** `Sources/Rebuild/RebuildWritingView.swift:54-77`, `:92`, `Sources/Services/MLXModelManager+Downloads.swift:21-82`, `:105-117`, `Sources/Rebuild/RebuildSession.swift:365-382`.
- **Evidence:** Writing changes a button to “Installing…” and sets maintenance state, but never reads the existing `downloadProgress[repo]`. It exposes neither stages/bytes nor cancellation. Failures collapse into “Check your connection and retry” even though the model manager stores specific failure information. Maintenance blocks recording/import until completion.
- **Layman's term:** A large download should show that it is moving and let you stop it.
- **What's wrong:** A potentially lengthy optional install offers little feedback and occupies the recording admission gate. This is confirmed code-path behavior; no fresh slow-network download duration was measured.
- **Impact:** Moderate — users cannot distinguish slow progress from a stuck install, and cannot resume dictation by cancelling it.
- **Significance:** High — this is the entry path for the newly recommended cleanup models.
- **Difficulty:** M
- **Fix:** Display the structured stage/progress already available, propagate actionable errors, and add owned process/task cancellation that actually releases maintenance after subprocess termination. Preserve resumable partial downloads and test cancel/retry on a tiny disposable fixture.
- **Grade lift:** B → B+, by making optional setup understandable and recoverable.

#### UI C3 — Use friendly app mappings and refresh running apps

- **Where:** `Sources/Rebuild/RebuildWritingView.swift:118-151`, `Sources/Managers/AppCategoryManager.swift:74`.
- **Evidence:** The assignment picker resolves running-app names, but persisted mapping rows and Reset accessibility labels use raw bundle IDs. The running-app list is populated only by `.task`; no launch/termination observer or explicit Refresh action exists.
- **Layman's term:** Show “Mail,” and notice an app you just opened.
- **What's wrong:** Internal identifiers make confirmation harder, and a newly launched target may not appear until the view is recreated. Populated mappings were not exercised in this delegated runtime pass.
- **Impact:** Moderate — avoidable friction choosing and confirming an app-specific writing profile.
- **Significance:** Medium — optional contextual writing workflow.
- **Difficulty:** S
- **Fix:** Resolve display names/icons with bundle-ID fallback, update running apps from workspace notifications or Refresh, and use the friendly name in accessibility actions. Retain the ID as optional secondary technical detail.
- **Grade lift:** B → B+ for the profile workflow, by removing stale choices and technical labels.

## D — Accessibility & Inclusive UX — B-, provisional

1. Main recording/transcript controls have explicit accessibility labels; repeated profile/history actions carry context; navigation exposes selection (`RebuildWorkspace.swift:79`, `:165`, `:235`; `RebuildWritingView.swift:104`; `RebuildLibraryView.swift:70`).
2. Escape/cancel/default actions and Reduce Motion are connected to actual behaviors, and particle decoration is hidden from accessibility. These are source observations, not a completed VoiceOver journey.
3. Fresh native HUD rendering confirms timer text remains unnecessarily faint in the unchanged path.

#### UI D1 — Make recording time easier to read

- **Where:** `Sources/Views/Components/Waveform/WaveformContainer.swift:297-310`, `Sources/Views/Components/Waveform/WaveformSubviews.swift:67-85`; fresh `.Codex/ui-ux-audit/2026-10-06-f30c081/desktop/recording-visible.png`, historical `.Codex/ui-ux-audit/2026-10-04-vm/overlay-over-fullscreen.png`.
- **Evidence:** The timer is 11-point monospaced text inheriting white at 32% opacity. Fresh native rendering shows a visibly faint `00:00` over a bright TextEdit document; the historical full-screen capture corroborates that presentation. No numeric contrast measurement was performed.
- **Layman's term:** You should not have to squint to see how long you have recorded.
- **What's wrong:** Weak emphasis on a translucent surface reduces live-status legibility.
- **Impact:** Minor — checking recording duration requires more effort.
- **Significance:** Medium — visible during the core workflow.
- **Difficulty:** XS
- **Fix:** Strengthen timer foreground/surface contrast; verify above bright/dark windows with Increased Contrast and Reduce Transparency, and measure contrast before making a compliance claim.
- **Grade lift:** B- → B for timer legibility; VoiceOver/focus validation remains required.

## E — Responsive & Cross-State Experience — C+

1. ScrollViews, shared headings and fixed vertical text sizing support minimum native window dimensions. Current Writing screenshots contain the longer Qwen names and wrapped explanatory copy without clipping (`RebuildWritingView.swift:21-39`; `vm-ui/writing-page.png`).
2. The recorder has a bounded 380×230-point layout and whole-window visible-frame placement coverage (`RebuildWorkspace.swift:275`; `Tests/RebuildRecorderLayoutTests.swift`). Fresh desktop acceptance records that frame size across ten cycles and renders visible controls; earlier native full-screen evidence distinguishes normal preferences from the permitted recording HUD.
3. Fresh populated Library navigation twice grows the native window from 870×620 to 870×1179 points on a 1024×768 display, clipping its lower content. Empty/off-library, no-search-results, disabled model and failure/retry states have explicit implementations, but this confirmed populated-state failure lowers the category. Multiple displays, longer-content stress and native Sonoma checks remain additional acceptance gaps.

#### ~~UI E1~~ ✓ done 2026-10-06 — Keep populated Library within the user's window

- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:23-88`, `Sources/Rebuild/RebuildWorkspace.swift:35-46`, `Sources/Rebuild/RebuildApp.swift:109-120`, `Sources/Managers/Windows/StandardWindow.swift:18-31`; `.Codex/ui-ux-audit/2026-10-06-f30c081/library-sizing.json`, `library-overflow-1.png`, `library-overflow-2.png`.
- **Evidence:** Twice, the root runner reset Record to 870×620 points and selected the observed Library sidebar action. Native probes then measured the same window at 870×1179 points, beyond the guest's 768-point display/681-point usable height; both screenshots visibly clip the window below the display. The enlarged frame persisted across navigation until resized. There is no explicit page-change frame mutation. The outer Library VStack and unconfigured NSHostingController sizing provide a likely content-to-window sizing path; that exact mechanism is an inference pending focused hosting verification.
- **Layman's term:** Opening your saved transcripts makes the app grow off the bottom of the screen.
- **What's wrong:** The populated Library fails to use the available window as its viewport. A list that should scroll instead changes native window geometry, making lower content harder to reach and disturbing other pages.
- **Impact:** Moderate — history navigation unexpectedly changes the user's window and clips its content.
- **Significance:** High — a top-level destination should reliably fit a supported desktop window.
- **Difficulty:** M
- **Fix:** Give the workspace a deliberate window-owned hosting-size policy and the Library a finite scroll viewport. Verify which intrinsic/minimum/preferred sizing contribution causes growth rather than merely clamping a symptom. Add native hosting regression coverage for every page at 870×620 with empty, loading and populated Library states, and repeat the two guest repro cycles.
- **Grade lift:** C+ → B, by repairing a confirmed native layout failure; broader display/accessibility checks remain.

**UI E1 validation:** Default hosting propagated a 1153-point content minimum and grew the native test window to 870×1185. Turning off content-driven sizing keeps the native window at 870×620 through populated/empty Library and every workspace page. The final package repeats the original guest reproduction with actual native bounds and screenshots.

## F — Frontend Code & Design System Health — B+

1. Theme tokens and page/section primitives centralize the recognizable visual system (`RebuildWorkspace.swift:5`, `:97`, `:109`). Purpose-specific files keep ownership comprehensible.
2. The observable session controls admission/delivery rather than individual buttons implementing competing recording state machines. Library load requests include search, enabled state and committed history revision (`RebuildLibraryView.swift:6`, `:89`, `:133`).
3. Migration/catalog tests protect the latest default and existing explicit preferences. The progress-linkage omission is tracked as UI C2; no additional structural frontend defect was established that warrants a rewrite.

## G — UI Performance & Asset Efficiency — B, provisional

1. Library loads 50-record pages into lazy rows and debounces searches; transcript exports stream pages rather than building the entire table in memory (`RebuildLibraryView.swift:59`, `:93`, `:131`, `:155`).
2. Timer/waveform animation work is scoped to visible/active states (`WaveformSubviews.swift:48`, `:86-90`; `FrameTimer.swift`), and current model guidance exposes physical-Mac memory costs instead of hiding them.
3. Paging alone does not isolate synchronous export work from the UI actor. Fresh frame/startup/export timings are not established by the model benchmark.

#### UI G1 — Keep large Library export responsive

- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:140-170`, `Sources/Stores/DataManager+Fetching.swift:42-65`, `Sources/Stores/DataManager.swift:114`.
- **Evidence:** Export invokes a main-actor paging loop that does not suspend between fetch/format/write iterations, then synchronizes/replaces the output file. The `async` method label does not move this work off the UI actor. No stall duration was measured here.
- **Layman's term:** Saving many transcripts should not freeze the app window.
- **What's wrong:** Bounded memory does not ensure responsiveness; non-suspending data formatting and disk writes share the UI execution context.
- **Impact:** Moderate — large history exports can delay input and progress rendering.
- **Significance:** Medium — optional but legitimate retained-history workflow.
- **Difficulty:** M
- **Fix:** Stream immutable record values from an isolated SwiftData worker into a cancellable file writer; retain save-panel/status work on the main actor. Measure input responsiveness with a large disposable library and handle write errors without iterating uselessly through remaining pages.
- **Grade lift:** B → B+, by removing the identified large-library responsiveness risk.

## H — Data Linkages & State Reliability — B+

1. Readiness distinguishes prerequisites and failed model verification; blocked shortcut paths do not request consent or download automatically (`Tests/RebuildSetupTests.swift:42-66`, `:119-141`; `RebuildSession.swift:377-386`). This directly addresses earlier false-ready/permission-spam reports.
2. Session IDs fence stale results and paste validity; committed history mutations publish revisions checked by Library (`RebuildSession.swift:297`, `:322`; `Tests/RebuildLibraryInvalidationTests.swift:27-87`).
3. The integration evidence verifies real offline model switching and preserved preferences. Fresh `desktop/report.json` establishes native successful delivery, no duplicate pasted fixture text and valid package identity/signature. Successful textual correctness is not guaranteed by these state protections; compare/restore-original is UI C1 and semantic guard weaknesses belong in the service/backend assessment.

## I — Polish, Delight & Product Feel — B+

1. The restrained design, privacy explanation, optional-history language and useful empty state fit a local dictation utility rather than placing AI marketing above the user's job (`RebuildWorkspace.swift:89`, `:223`; `RebuildLibraryView.swift:27`).
2. Shortcut guidance names the configured keys or their disabled/unassigned state. New cleanup model labels explain practical cost in plain language while retaining advanced choices (`RebuildWorkspace.swift:130-139`; `MLXModelManager.swift:56-86`).
3. Remaining finishing details are specific: download feedback, app mapping readability and timer emphasis. These are already tracked rather than duplicated as separate cosmetic findings.

## Prior report findings verified against current code

| Prior `187eacd` UI item | Current outcome |
|---|---|
| B1 model guidance | Cleanup portion fixed and rendered; remaining minor voice guidance is new UI B1 |
| C1 app mappings | Still present; new UI C3 |
| D1 faint timer | Confirmed in fresh native HUD and current source; new UI D1 |
| G1 Library export | Source still contains non-suspending main-actor loop; new UI G1 |

## Codebase C — Frontend grade contribution — B

Shared theme/components, explicit observable session ownership, conventional native controls, bounded state-aware library fetching and meaningful preference/session/layout regressions are strong. The newly confirmed populated-Library native window growth demonstrates missing finite viewport/hosting-size integration and page-transition layout coverage, lowering the frontend contribution to B. Other clear implementation improvements are app-mapping naming/refresh (`RebuildWritingView.swift:131-151`) and correction-install progress/error linkage (`:54-77`); raw/cleaned recovery crosses the pipeline/UI boundary and belongs primarily with transcript integrity. Dormant legacy presentation debt should be graded under architecture rather than counted again as a reason to rewrite this frontend.
