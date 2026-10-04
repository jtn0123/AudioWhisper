# Codebase Grade Report

**Project:** AudioWhisper
**Audited:** 2026-07-31
**Stack:** macOS 14+ menu-bar app — Swift 5.9 / SwiftUI + AppKit, AVFoundation audio, SwiftData persistence, WhisperKit (CoreML) + Parakeet-MLX transcription, embedded uv-managed Python for MLX semantic correction
**Previous report:** `.claude/grade-report-2026-05-16.md` (overall B, 43 items)

## Action Plan — Top 20 (approve by number)

Plain-language ranking. Say "do 1, 3, 7" and these map to the detailed items below.

| # | Fix | Maps to | Effort |
|---|-----|---------|--------|
| 1 | Rewrite README — describes removed cloud providers, links to upstream repo | H1 | half day |
| 2 | Ship the Python lockfile + `--frozen` (supply-chain hole) | E1, F5 | half day |
| 3 | Find and kill the flaky test | D1 | 1 day |
| 4 | Fix correction running Llama when UI recommends Qwen3 | B1 | 1–2 hrs |
| 5 | Raise `mlx-lm` / `parakeet-mlx` version caps | F3 | half day |
| 6 | Refresh the correction model catalog (benchmark first) | F4 | 1–2 days |
| 7 | Turn on `swiftlint analyze` so dead code gets caught | I2 | half day |
| 8 | Fix CI print() gate that can never fail | I1 | 30 min |
| 9 | Migrate WhisperKit 0.15 → Argmax OSS SDK 1.0 | F1 | 3+ days |
| 10 | Re-enable the 36 snapshot tests in CI | D2 | half day |
| 11 | Add nightly CI for the end-to-end transcription test | D3 | half day |
| 12 | Delete the 160-line unused DependencyContainer | A1 | 1 hr |
| 13 | Add accessibility labels (Dashboard + Welcome) | C1 | 1–2 days |
| 14 | Honor Reduce Motion for confetti/particles | C2 | 2 hrs |
| 15 | Fix invisible sidebar hover/selection in dark mode | C4 | 30 min |
| 16 | Stop logging Python stderr (can contain transcripts) | E2 | 30 min |
| 17 | Finish test isolation so tests can run in parallel | D4 | 1–2 days |
| 18 | Delete leftover OpenAI/Gemini code | A4 | 1–2 hrs |
| 19 | Fix 3 always-on timers burning idle CPU | C3, G1 | 1 hr |
| 20 | Stop loading full history into memory on delete | B5, G2 | half day |

---

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Architecture & Design | B | 5 |
| B | Service & Data Layer Quality | B | 6 |
| C | Frontend / SwiftUI Quality | C+ | 6 |
| D | Testing & Reliability | C+ | 5 |
| E | Security | B− | 4 |
| F | Dependencies & Tech Currency | C− | 5 |
| G | Performance & Scalability | B | 3 |
| H | Documentation & Onboarding | C− | 4 |
| I | Developer Experience & Tooling | B | 4 |
| **Overall** | | **B−** | **42** |

**Top 5 highest-leverage fixes:** H1, F1, E1, D1, F2

### Verification performed for this audit

| Check | Result |
|---|---|
| `swift build` | Clean, 0 warnings, 35.8s |
| `swift test --no-parallel` ×5 full runs | 2805 tests, 37 skipped. **4 runs green, 1 run had 3 failures** |
| SwiftLint config | strict in CI; analyzer rules configured but never executed |
| Force unwraps / `try!` / `as!` / TODO / FIXME | 3 / 0 / 0 / 0 / 0 — exceptionally clean |
| Dependency currency | 4 of 6 dependencies significantly behind (see F) |

### What changed since the May audit

Genuine progress: the previous report's C1/A2/B1/B2 items landed (TranscriptionCoordinator extracted, correction ownership consolidated into `TranscriptionPipeline`, outcome-aware correction API, `FrameTimer` lifecycle fix). Two bug-hunt sweeps closed ~50 numbered defects. Views→store `.shared` references dropped from ~16 to 10.

Not addressed, and now worse: `DependencyContainer.swift` (old item A1) is still 160 lines with **zero** call sites. Dependency currency degraded from B+ to C− — WhisperKit shipped a 1.0 rename, KeyboardShortcuts shipped two majors, and both Python pins are now hard-capped below current. The README has drifted from stale to actively wrong.

---

## A — Architecture & Design — B

The `Sources/` taxonomy (App / Services / Stores / Managers / Models / ViewModels / Views / Utilities / Design / Extensions) is real and mostly respected. Layering flows Views → ViewModels → Coordinator → Pipeline → Services, with `RecordingViewModel` taking constructor-injected dependencies (`RecordingViewModel.swift:107-128`) and `TranscriptionCoordinator` correctly owning the post-transcription tail. No god objects — largest file is 555 lines. `AppDelegate` is split across 6 focused extensions and the ADRs in `docs/adr/` document the load-bearing decisions.

What holds it at B: two View files spawn `Process()` subprocesses directly, bypassing the entire service layer; a 160-line DI container ships with zero call sites; the same Python capability probe is copy-pasted in three places; and dead cloud-provider code is scattered across setup, theming, and error mapping after those providers were removed.

#### A1 — Delete the fully-dead DependencyContainer
- **Where:** `Sources/Utilities/DependencyContainer.swift` (160 lines). `grep -rn 'DependencyContainer\|@Injected' Sources/` excluding the file itself returns **zero** matches.
- **What's wrong:** A complete DI container plus an `@Injected` property wrapper compile and ship in the binary with no consumers. The previous audit (item A1, 2026-05-16) flagged this as "adopted in only one file each"; adoption has since gone to zero. It advertises a testability story the codebase does not use, and gives new contributors two competing DI models to choose between.
- **Fix:** Delete `Sources/Utilities/DependencyContainer.swift` and any test file that only exercises it. Standardize on the constructor injection `RecordingViewModel` and `TranscriptionPipeline` already use. Re-run `swift build && swift test` to confirm nothing referenced it.
- **Effort:** S
- **Grade lift:** B → B+ (removes the largest piece of dead architecture and settles the DI story)

#### A2 — Views launch subprocesses directly
- **Where:** `Sources/Views/Dashboard/DashboardCorrection+Verify.swift:98-100,141-142`; `Sources/Views/Dashboard/DashboardProviders+Parakeet.swift:235-237,277-278`
- **What's wrong:** Four `Process()` launches live in SwiftUI view files. These views run Python, parse stdout, and handle exit codes — work that belongs in `PythonDetector`/`MLXModelManager`. The verification logic cannot be unit-tested without instantiating a view, and it duplicates `PythonDetector.swift:52-54`.
- **Fix:** Move both verification flows into `PythonDetector` (or a new `MLXEnvironmentVerifier` service) exposing `func verifyMLX() async throws -> VerificationResult` and `func verifyParakeet() async throws -> VerificationResult`. Views call the service and render the result. Add unit tests against the service.
- **Effort:** M
- **Grade lift:** B → B+ (restores the service boundary and makes verification testable)

#### A3 — Triplicated `import mlx_lm` capability probe
- **Where:** `Sources/Services/PythonDetector.swift:54`, `Sources/Views/Dashboard/DashboardCorrection+Verify.swift:100`, `Sources/Views/Dashboard/DashboardProviders+Parakeet.swift:237` — all three run `["-c", "import mlx_lm; print('OK')"]`.
- **What's wrong:** The same environment probe is copy-pasted three times. Note the Parakeet path probes for `mlx_lm` rather than `parakeet_mlx` — a Parakeet-only environment would fail this check even when Parakeet works, and vice versa. Changing the probe requires finding all three.
- **Fix:** Extract a single `PythonDetector.probeModule(_ name: String, python: String) async -> Bool`. Call it with `"mlx_lm"` from the correction path and `"parakeet_mlx"` from the Parakeet path. Fold in as part of A2.
- **Effort:** S
- **Grade lift:** B → B (removes duplication and fixes a probe that checks the wrong module)

#### A4 — Dead cloud-provider surface after providers were removed
- **Where:** `Sources/App/AppSetupHelper.swift:203-205` (writes `cloud_openai_prompt.txt` + `cloud_gemini_prompt.txt` on every launch); `Sources/Views/Dashboard/DashboardHomeView.swift:310-311,320-321,356-357`; `Sources/Views/Dashboard/DashboardView.swift:53-54`; `Sources/Views/Components/MenuPopupViews.swift:81-82`; `Sources/Models/TranscriptionError.swift:123,264-267`; `Sources/Services/KeychainService.swift:122-132`
- **What's wrong:** `TranscriptionProvider` has exactly two cases (`.local`, `.parakeet` — `TranscriptionTypes.swift:14-26`), but branches for `"openai"` and `"gemini"` remain across theming, icons, display names, and error mapping. `AppSetupHelper` still writes two prompt files into `~/Library/Application Support/AudioWhisper/prompts/` that nothing reads. `KeychainService` still logs about "API key" length for accounts that are never written.
- **Fix:** Delete the two cloud prompt entries from `AppSetupHelper.swift:204-205`. Remove the `"openai"`/`"gemini"` cases from the four view/model switches and the two `DashboardTheme` provider colors. Simplify the `KeychainService` length-heuristic logging. Grep `-riE 'openai|gemini'` over `Sources/` afterwards — only the WhisperKit CoreML model names (`openai_whisper-*`) in `WhisperModel+WhisperKit.swift` should survive.
- **Effort:** S
- **Grade lift:** B → B+ (removes a whole phantom feature from the codebase)

#### A5 — 48 test-only symbols compiled into the shipping app
- **Where:** 34 `testable*` declarations (9 in `DashboardCorrectionView.swift`, 7 in `CategoryEditorSheet.swift`, 4 each in `DashboardProvidersView.swift` / `DashboardPreferencesView.swift` / `DashboardHomeView.swift`, more across Dashboard) plus 14 `*ForTesting` methods (`MLDaemonManager.swift:298-348`, `UvBootstrap.swift:346-353`, others).
- **What's wrong:** Test scaffolding ships in the release binary. Worse, several `testable*` helpers **duplicate production logic rather than exercising it** — e.g. `DashboardCorrectionView.testableDefaultModelRepo()` hardcodes `"mlx-community/Qwen3-1.7B-4bit"` as its own copy of a default that lives in `AppDefaults+Settings.swift:64`. A test asserting against that helper passes even if production drifts (see B1, where production has in fact drifted).
- **Fix:** For pure-logic helpers, wrap in `#if DEBUG` at minimum. Better: delete the `testable*` copies and have tests call the real production symbols via `@testable import` (already used throughout `Tests/`). Prioritize the ones that duplicate constants — those are actively lying to the test suite.
- **Effort:** M
- **Grade lift:** B → B+ (smaller binary; tests that verify production behaviour instead of a parallel copy)

---

## B — Service & Data Layer Quality — B

This is the strongest layer. Error modeling is genuinely good: every service defines a domain `Error` enum with `LocalizedError` conformance and specific cases, and error preservation is careful — `SpeechToTextService.swift:109-115` and `:153-164` explicitly re-throw domain errors instead of flattening them. Concurrency is disciplined: `VenvSerializer` (`UvBootstrap.swift:32-81`) uses a task-chain rather than a plain actor precisely because a plain actor admits re-entry at the first `await`, and the comment explains why. `MLDaemonManager` handles the hard cases — pending-request registration before stdin write, off-actor writes to avoid pipe deadlock, deadline sweeping, crash-loop counters.

What holds it at B: a user-visible default-model mismatch, and four pieces of dead or misleading code inside `SemanticCorrectionService` alone.

#### B1 — Correction runs a different model than the UI recommends and downloads
- **Where:** `Sources/Services/SemanticCorrectionService.swift:125-127`; `Sources/Services/SpeechToTextService.swift:139-141`; vs `Sources/Stores/AppDefaults+Settings.swift:64` and `Sources/Views/Dashboard/DashboardCorrectionView.swift:143` (`testableIsRecommended` → `Qwen3-1.7B-4bit`)
- **What's wrong:** When the user has never explicitly picked a correction model, `AppDefaults.semanticCorrectionModelRepo` returns `mlx-community/Qwen3-1.7B-4bit` — which is what the Dashboard displays and badges **RECOMMENDED**. But both correction call sites bypass that default with `AppDefaults.hasValue(for:) ? AppDefaults.semanticCorrectionModelRepo : "mlx-community/Llama-3.2-1B-Instruct-4bit"`. A fresh user therefore sees Qwen3 recommended, may download Qwen3 (1.0 GB), and then correction silently downloads and runs Llama-3.2-1B (0.6 GB) instead. The daemon warmup in `SpeechToTextService` warms the same wrong model, so the warmup optimization is also wasted.
- **Fix:** Pick one default. Recommended: delete the `hasValue` special-case at both sites and read `AppDefaults.semanticCorrectionModelRepo` directly, so `Qwen3-1.7B-4bit` is genuinely the default. Add a one-time migration that writes the key explicitly for existing installs that were silently on Llama-3.2 (read the HuggingFace cache to detect which model is actually present). Add a test asserting the model used by `correctLocallyWithMLXThrowing` equals the model shown as recommended.
- **Effort:** S
- **Grade lift:** B → B+ (removes a real user-visible correctness bug and a wasted download)

#### B2 — Chunking constants document behaviour that does not exist
- **Where:** `Sources/Services/SemanticCorrectionService.swift:36-40`
- **What's wrong:** `chunkSizeWords = 6000` and `overlapSizeWords = 200` are declared with a comment describing a 32k-context chunking strategy. Neither constant is referenced anywhere (`grep chunkSizeWords Sources/` → one hit, the declaration). No chunking exists: `correctLocallyWithMLXThrowing` passes the full transcript to `mlxService.correct(...)` in one shot. A long dictation therefore overflows a 1.7B model's context and correction degrades or fails — and the failure is swallowed into `.failed(error, fallback: text)`, so the user just silently gets uncorrected text.
- **Fix:** Either implement the chunking the comment describes (split at `chunkSizeWords` with `overlapSizeWords` overlap, correct each chunk, stitch on the overlap) or delete both constants and the comment, and add an explicit length guard that skips correction with a clear `.failed` reason above a documented threshold. Do not leave the constants asserting a feature that isn't there.
- **Effort:** M (implement) / S (delete + guard)
- **Grade lift:** B → B+ (either fixes long-transcript correction or stops the code from lying about it)

#### B3 — Two dead private methods in SemanticCorrectionService
- **Where:** `Sources/Services/SemanticCorrectionService.swift:108-115` (`correctLocallyWithMLX`), `:187-192` (`readPromptFile`)
- **What's wrong:** Neither is called from anywhere in `Sources/` or `Tests/`. `correctLocallyWithMLX` is a non-throwing wrapper superseded when `correctWithOutcome` began calling `correctLocallyWithMLXThrowing` directly; its 8-line doc comment still describes it as the live path, which actively misleads. These survive because SwiftLint's `unused_declaration` analyzer rule is configured but never runs in CI (see I2).
- **Fix:** Delete both methods and the stale doc comment on the first. Then fix I2 so this class of rot is caught automatically.
- **Effort:** S
- **Grade lift:** B → B (removes misleading dead code)

#### B4 — Dead `keychainService` init parameters kept "for API compatibility"
- **Where:** `Sources/Services/SpeechToTextService.swift:41-43`, `Sources/Services/SemanticCorrectionService.swift:48-50`
- **What's wrong:** Both initializers take a `KeychainServiceProtocol` and discard it, with a comment saying it's kept for API compatibility. There are no cloud providers left, so no caller needs it. The parameter forces `KeychainService.shared` to be evaluated as a default argument at every construction site for nothing, and it implies these services touch credentials when they do not.
- **Fix:** Remove the parameter from both initializers. Update construction sites (`RecordingViewModel.swift:133,135`, `TranscriptionPipeline.swift:31-32`, and test files) — the compiler will find them all.
- **Effort:** S
- **Grade lift:** B → B (removes a misleading credential-shaped dependency)

#### B5 — `deleteAllRecords` and post-delete rebuild load the entire history into memory
- **Where:** `Sources/Stores/DataManager.swift:345-371` (fetch-all then delete in a loop), `:335-339` (fetch-all to rebuild usage stats after a single-record delete)
- **What's wrong:** `deleteAllRecords` fetches every `TranscriptionRecord` and deletes them one at a time. `deleteRecord` — after successfully deleting one row — fetches **all** remaining records purely to hand them to `UsageMetricsStore.rebuild` and `SourceUsageStore.rebuild`. For a user with months of history at the "Forever" retention setting, deleting one transcript triggers a full-table load on the main actor. The rest of the file is careful about this (pagination via `fetchRecords(limit:offset:search:)`, documented "reserved for export" on `fetchAllRecords`), which makes these two the outliers.
- **Fix:** For `deleteAllRecords`, use `context.delete(model: TranscriptionRecord.self)` (SwiftData batch delete) instead of the fetch-and-loop. For `deleteRecord`, apply an incremental decrement to the two stores (`UsageMetricsStore.remove(record:)`) instead of a full rebuild; keep the rebuild path only for the explicit "Rebuild from history" dashboard action.
- **Effort:** M
- **Grade lift:** B → B+ (removes the only unbounded main-actor fetches in the data layer)

#### B6 — `ggerganov/whisper.cpp` download URLs on a WhisperKit-only path
- **Where:** `Sources/Models/TranscriptionTypes.swift:64-82` — `downloadURL` / `getDownloadURL()` build `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<model>.bin`
- **What's wrong:** Local transcription runs through WhisperKit, which downloads CoreML models from `argmaxinc/whisperkit-coreml` (`Sources/Services/WhisperKitStorage.swift:7`) using its own naming (`openai_whisper-large-v3_turbo`, per `WhisperModel+WhisperKit.swift:7-13`). The `ggml-*.bin` URLs are from the whisper.cpp era and point at a completely different artifact format. Anything that calls `downloadURL` would fetch a file WhisperKit cannot load.
- **Fix:** Confirm no live call sites remain (`grep -rn 'downloadURL\|getDownloadURL' Sources/`), then delete both computed properties, `WhisperModelError`, and the `fileName` property that only exists to build them. If a call site does exist, that is a bug — reroute it to `WhisperKitStorage`.
- **Effort:** S
- **Grade lift:** B → B (removes a broken legacy download path)

---

## C — Frontend / SwiftUI Quality — C+

Structure is good: 69 view files with sensible decomposition (Dashboard split into ~15 focused files, waveform styles isolated per-file), a coherent `DashboardTheme` token system built on semantic `Color(nsColor:)` values so light/dark mostly works for free, and a purpose-built `FrameTimer` (`FrameTimer.swift`) whose doc comment shows real understanding of why `Timer.publish(...).autoconnect()` in a grid of 8 animated tiles is a problem.

The grade is held down by accessibility, which is close to absent for an app this animation-heavy, and by three inconsistencies where the good patterns established elsewhere aren't applied.

#### C1 — Accessibility annotations exist in 12 of 69 view files
- **Where:** 52 total `accessibility*` calls, concentrated in `PermissionModals.swift` (9), `RecordingButton.swift` (4), and the Transcription views. The entire Dashboard — ~15 files, the app's largest UI surface — has **2**, both in `DashboardProvidersView.swift`. `WelcomeView.swift` (first-run onboarding) has zero.
- **What's wrong:** VoiceOver users get raw or missing labels across settings, model management, category editing, and first-run onboarding. Icon-only controls (the sidebar nav, model download buttons, waveform style pickers) announce as unlabeled buttons. For a dictation/accessibility-adjacent utility, this is a poor look.
- **Fix:** Work outside-in. First `WelcomeView.swift` and `DashboardView.swift` sidebar navigation (`accessibilityLabel` + `accessibilityAddTraits(.isSelected)`), then icon-only buttons in `DashboardProviders*`/`DashboardCorrection*` (label + hint), then `MLXModelManagementView` download rows (`accessibilityValue` for progress). Add an `accessibilityElement(children: .combine)` to the stat tiles in `DashboardHomeView`. Enable Accessibility Inspector's audit on the Dashboard window and drive the remaining list from it.
- **Effort:** M
- **Grade lift:** C+ → B (closes the largest UX-quality gap in the app)

#### C2 — Zero reduce-motion support in an animation-heavy app
- **Where:** `grep -riE 'reduceMotion|accessibilityDisplayShould' Sources/` → **zero matches**. Meanwhile: `CelebrationEffects.swift` (350 lines, confetti particle bursts, 2 `TimelineView(.animation)`), `StateTransitionEffects.swift` (347 lines), `ParticleSystem.swift` (50-particle system on `TimelineView(.animation)`), `InkRippleView.swift` (297 lines), and 8 continuously-animating waveform styles.
- **What's wrong:** Users who enable System Settings → Accessibility → Display → Reduce Motion get the full confetti-and-particles treatment anyway. For motion-sensitive users this is exactly the setting that exists to prevent this, and macOS exposes it — the app just never asks.
- **Fix:** Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to `CelebrationEffects`, `StateTransitionEffects`, `ParticleSystem`, and `InkRippleView`. When true, skip particle emission entirely and replace transitions with a plain `.opacity` crossfade. For the waveform views, fall back to a static level bar. One shared `ViewModifier` (`.respectingReduceMotion()`) keeps this to a handful of touch points.
- **Effort:** S
- **Grade lift:** C+ → B− (a first-class macOS accessibility setting goes from ignored to honored)

#### C3 — Three timers bypass the FrameTimer pattern built to replace them
- **Where:** `Sources/Views/Components/WaveformView.swift:171` (every 0.05s), `Sources/Views/Components/InkRippleView.swift:60` (every 0.05s), `Sources/Views/Components/Waveform/WaveformContainer.swift:473` (every 0.5s) — all raw `Timer.publish(...).autoconnect()`. Nine other waveform views correctly use `frameTimer.publisher`.
- **What's wrong:** `FrameTimer` exists specifically because `.autoconnect()` "runs forever the moment a view is created — even for waveform tiles that are off-screen." These three views reintroduce exactly that: two fire 20×/second on the main thread for the lifetime of the view regardless of visibility. The inconsistency also means a future reader can't tell which pattern is correct.
- **Fix:** Convert all three to `FrameTimer`, driven from `onAppear`/`onDisappear` like `ClassicWaveformView.swift:49` and its siblings. Then add a SwiftLint `custom_rules` entry banning `Timer.publish` outside `FrameTimer.swift` so it can't regress.
- **Effort:** S
- **Grade lift:** C+ → B− (removes always-on main-thread timers and makes the pattern enforceable)

#### C4 — Sidebar hover/active states use hardcoded black and vanish in dark mode
- **Where:** `Sources/Views/Dashboard/DashboardView.swift:33-34` — `sidebarHover = Color.black.opacity(0.04)`, `sidebarActive = Color.black.opacity(0.07)`
- **What's wrong:** Every other token in `DashboardTheme` uses semantic `Color(nsColor:)` values that adapt automatically. These two are literal black at 4% and 7%, layered over an `NSVisualEffectView` `.sidebar` material that is *dark* in dark mode. Black-on-dark at 4% opacity is effectively invisible — dark-mode users get no hover feedback and a barely-perceptible selection indicator in the app's primary navigation. (The other 15 hardcoded `Color.white/.black.opacity` uses sit on deliberately dark surfaces — waveform, welcome — and are fine.)
- **Fix:** Replace with `Color(nsColor: .quaternaryLabelColor)` / `Color(nsColor: .tertiaryLabelColor)`, or use `Color.primary.opacity(0.04)` / `.opacity(0.07)` which inverts correctly. Verify against the `DashboardView-dark` snapshot baseline once D2 re-enables snapshot testing.
- **Effort:** S
- **Grade lift:** C+ → C+ (fixes a visible dark-mode defect in primary navigation)

#### C5 — Test scaffolding embedded in view files
- **Where:** `DashboardCorrectionView.swift` (9 `testable*` members), `CategoryEditorSheet.swift` (7), `DashboardProvidersView.swift`, `DashboardPreferencesView.swift`, `DashboardHomeView.swift` (4 each), `DashboardCategoriesView.swift` (3), `DashboardVisualsView.swift`, `DashboardRecordingView.swift` (2 each)
- **What's wrong:** These view files carry a parallel `testable*` API — mock structs (`TestableModelEntry`), duplicated constants, and re-implementations of display logic — inline with the SwiftUI body. It inflates the files, obscures the actual view code, and (per A5) some of them duplicate rather than delegate to production logic.
- **Fix:** Move the pure-logic helpers into the corresponding ViewModel or a `*Presentation` type that both the view and tests consume. Delete the duplicating ones. This is the view-layer half of A5; do them together.
- **Effort:** M
- **Grade lift:** C+ → B− (view files return to being view files)

#### C6 — GCD `asyncAfter` mixed into `@MainActor` async code
- **Where:** `Sources/ViewModels/RecordingViewModel.swift:373,378`; 24 `DispatchQueue.main.asyncAfter` sites total across `Sources/`, against 27 `Task.sleep` sites
- **What's wrong:** `RecordingViewModel` is `@MainActor @Observable` and uses structured concurrency throughout, then drops to `DispatchQueue.main.asyncAfter` with `[weak self]` for the paste delay and the fade-out delay. These delayed blocks are not attached to `processingTask`, so `cancelProcessing()` cannot cancel them — a paste can fire after the user has cancelled or dismissed the window. The codebase is split roughly 50/50 between the two idioms with no stated rule.
- **Fix:** Replace both sites with `Task { try? await Task.sleep(for: .milliseconds(700)); guard !Task.isCancelled else { return }; ... }` stored alongside `processingTask` so cancellation propagates. Sweep the remaining 22 sites opportunistically and note the preference in `CLAUDE.md`'s Code Patterns section.
- **Effort:** M
- **Grade lift:** C+ → B− (delayed UI work becomes cancellable; one concurrency idiom)

---

## D — Testing & Reliability — C+

Volume and infrastructure are strong: 2805 test functions across 194 files and ~40k lines, mirroring the `Sources/` tree; a 60% line-coverage gate enforced in CI (`ci.yml:97-121`); a bundle smoke test that verifies the built `.app` structure; an `IsolatedXCTestCase` base class for UserDefaults isolation; dedicated `Integration/`, `Performance/`, and `EdgeCases/` suites; and `ConcurrencyStressTests`.

The grade is C+ because the suite is not trustworthy as a gate. It is flaky, it must run sequentially, and two entire safety nets — 36 snapshot baselines and the only end-to-end transcription test — never execute in CI.

#### D1 — The suite is flaky: 3 failures in 1 of 5 identical runs
- **Where:** Whole-suite. Observed running `swift test --no-parallel -Xswiftc -DTESTING` five times on the same machine, same commit, no changes between runs: run 1 → `Executed 2805 tests, with 37 tests skipped and 3 failures`; runs 2–5 → `0 failures`.
- **What's wrong:** ~20% of clean runs go red for reasons unrelated to the code under test. That trains everyone to re-run CI instead of reading it, which is how a real regression eventually ships. I could not identify the three specific tests — the first run's output was captured through `tail -200`, which truncated the failure detail; four subsequent full-log runs did not reproduce.
- **Fix:** Run the suite in a loop capturing full logs until it reproduces: `for i in $(seq 1 20); do swift test --no-parallel -Xswiftc -DTESTING > run-$i.log 2>&1; grep -q "0 failures" run-$i.log || echo "FLAKE in run-$i"; done`. Prime suspects given the architecture: tests touching `MLDaemonManager` timing/restart counters, `AudioEngineRecorder` tap callbacks, and any test reading `UserDefaults.standard` without `IsolatedXCTestCase`. Once identified, fix the shared state — do not add retries.
- **Effort:** M
- **Grade lift:** C+ → B (the suite becomes a gate you can believe)

#### D2 — 36 snapshot baselines are committed but the snapshot suite never runs
- **Where:** `Tests/SnapshotTestCase.swift:18-26` skips unless `SNAPSHOT_TESTS=1` or `SNAPSHOT_RECORD=1`. Neither variable appears anywhere in `.github/workflows/`. `Tests/__Snapshots__/` holds 36 committed PNGs (`DashboardCorrectionView-dark.png`, `DashboardPreferencesView-light.png`, `CategoryEditorSheet-edit.png`, …).
- **What's wrong:** The visual-regression safety net is fully disabled in CI. The 36 baselines are dead weight that will silently rot as the UI changes, and the C4 dark-mode sidebar defect is precisely the class of bug these would have caught — there is even a `DashboardView-dark` baseline sitting unused.
- **Fix:** Add `SNAPSHOT_TESTS: "1"` to the `env:` block of the `Run Tests` step in `ci.yml`. Expect an initial batch of diffs from UI drift since the baselines were recorded — re-record with `SNAPSHOT_RECORD=1`, review the images by eye, and commit. If renderer differences between local and GitHub runners prove unstable, gate to a dedicated job on a pinned macOS image rather than leaving it off.
- **Effort:** M
- **Grade lift:** C+ → B− (36 baselines go from decorative to load-bearing)

#### D3 — The only end-to-end transcription test claims a nightly CI run that does not exist
- **Where:** `Tests/Integration/ParakeetEndToEndTests.swift:20` states "CI runs this nightly only; per-PR runs skip it via XCTSkip below", gated by `XCTSkipUnless(RUN_E2E == "1" || RUN_PARAKEET_E2E == "1")` at `:24-28`. The only `schedule:` trigger in the repo is `codeql.yml:8-9` (weekly CodeQL). No workflow sets `RUN_E2E` or `RUN_PARAKEET_E2E`.
- **What's wrong:** The comment asserts coverage that does not exist. The app's primary transcription path — download the Parakeet model, bootstrap the uv venv, run Python, get text back — is verified by **no** automated run, anywhere. Every other test mocks the daemon.
- **Fix:** Either add `.github/workflows/nightly.yml` (`schedule: cron: '0 7 * * *'`, `runs-on: macos-15`, `env: RUN_E2E: "1"`, generous timeout for the ~2.5 GB first-run model download, with HuggingFace cache restored via `actions/cache`) — or delete the false claim from the comment and state plainly that it is a manual local check. The first option is correct; the second is at least honest.
- **Effort:** M
- **Grade lift:** C+ → B− (the core user journey gets automated verification)

#### D4 — Tests cannot run in parallel because of UserDefaults leakage
- **Where:** `scripts/run-tests.sh:4-9` and `ci.yml:78-84` both force `--no-parallel`, documenting that "some tests still read/write `UserDefaults.standard` directly and fail nondeterministically under `--parallel`". `Tests/Utilities/IsolatedXCTestCase.swift` exists as the fix but the migration is incomplete.
- **What's wrong:** A 66-second sequential run that could be a fraction of that, and — more importantly — the same shared-state leakage that forces `--no-parallel` is the most likely root cause of D1. `CLAUDE.md` documents `swift test --parallel --enable-code-coverage` as the coverage command, which contradicts both scripts.
- **Fix:** Find the offenders: `grep -rn 'UserDefaults.standard' Tests/ | grep -v IsolatedXCTestCase`. Migrate each to `IsolatedXCTestCase` (or an injected suite-name `UserDefaults`). Flip the default in `run-tests.sh` and `ci.yml` once green across 10 consecutive parallel runs, and correct the command in `CLAUDE.md`.
- **Effort:** M
- **Grade lift:** C+ → B (likely fixes D1 at the root and speeds the loop)

#### D5 — 1.66 assertions per test suggests shallow coverage behind the 60% number
- **Where:** 2807 `func test*` declarations against 4661 `XCTAssert*` calls across `Tests/`. Concentrated shallowness in the `testable*`-driven view tests (see A5) — e.g. tests asserting `testableDefaultModelRepo() == "mlx-community/Qwen3-1.7B-4bit"`, which is a test of a test helper's own literal.
- **What's wrong:** Line coverage counts a line as covered when it executes, not when its behaviour is verified. A large share of the Dashboard tests exercise `testable*` mirrors rather than production code paths, so the 60% gate overstates real protection. The B1 default-model bug is direct evidence: it lives in production, a `testable*` helper hardcodes the *correct* value, and nothing caught the divergence.
- **Fix:** After A5/C5 remove the `testable*` mirrors, re-run coverage and expect it to drop — that drop is the accurate number. Then raise assertion depth where it matters most: `TranscriptionPipeline` (correction outcomes and fallback paths), `SemanticCorrectionService.safeMerge` boundaries, `DataManager` retention/pagination edges, and `MLDaemonManager` restart/timeout state machine.
- **Effort:** L
- **Grade lift:** C+ → B (coverage number starts meaning something)

---

## E — Security — B−

For an unsandboxed app that spawns subprocesses, this is handled with real care. Command injection is explicitly defended and documented (`MLXModelManager+Downloads.swift:144-158` passes the repo name as `sys.argv[1]`, never interpolated into Python source). Subprocess environments use a minimal allowlist rather than inheriting the parent's, so HuggingFace tokens and proxy credentials don't leak into children. Path traversal is blocked twice over in `SemanticCorrectionService.loadPrompt` (`:157-176`) — character allowlist plus a resolved-path prefix check. The bundled `uv` binary is SHA-256 verified at runtime against a hash stamped at build time (`UvBootstrap.swift:221-250`), with tamper detection that resets its own flag so a reinstall re-verifies. Model caches get TOFU integrity sidecars. Keychain error handling distinguishes real auth failures from "not found" (`KeychainService.swift:14-17`). Hardened runtime, notarization, and CodeQL on both Swift and Python are all wired up, and ADR 0001 documents why sandboxing was rejected.

One real hole keeps this from a B+: the Python dependency chain is resolved live from PyPI with no lockfile, in an app that deliberately ships without the sandbox as a backstop.

#### E1 — Python dependencies resolve live from PyPI; the bundled lockfile is never shipped
- **Where:** `Sources/Services/UvBootstrap.swift:199-207` runs `uv sync` with no `--frozen`. `UvBootstrap.swift:283-300` (`copyProjectFilesIfNeeded`) copies **only** `pyproject.toml`, with the comment "We intentionally do NOT copy a bundled uv.lock to avoid mismatches." `scripts/build.sh:223-229` is titled "Bundle pyproject.toml and uv.lock if present" but its body copies only `pyproject.toml`. `Sources/Resources/uv.lock` (90 KB, last updated 2026-05-15) is therefore built, committed, and never used.
- **What's wrong:** On first launch — and again whenever `pyproject.toml` changes — the app resolves and installs `mlx-lm`, `parakeet-mlx`, `librosa`, `numba`, `llvmlite`, `numpy`, `scipy`, `scikit-learn` and their full transitive closure fresh from PyPI, subject only to range constraints like `numpy>=1.26,<3`. A compromised release of any package in that closure executes with the user's full privileges: the app is unsandboxed by design (ADR 0001), holds Accessibility permission for SmartPaste, and holds microphone access. This is the one place where the otherwise-careful security posture has no backstop. ADR 0001 itself flags "higher security responsibility: without the sandbox safety net, we must be careful about subprocess execution, file paths, and bundled binaries" — the Python supply chain is the gap in that list.
- **Fix:** Ship the lock and enforce it. (1) In `scripts/build.sh`, actually copy `Sources/Resources/uv.lock` into `AudioWhisper.app/Contents/Resources/` — the step already claims to. (2) In `UvBootstrap.copyProjectFilesIfNeeded`, copy `uv.lock` alongside `pyproject.toml` using the same `copyIfDifferent` content-hash path. (3) Change `runInDir(uv.path, ["sync"], ...)` to `["sync", "--frozen"]`. (4) Handle the "mismatch" the comment worried about explicitly: on `--frozen` failure, log the mismatch and retry once unlocked, so a stale user-side lock degrades rather than bricks. (5) Regenerate `uv.lock` in CI whenever `pyproject.toml` changes, and add a CI check that the two are consistent.
- **Effort:** M
- **Grade lift:** B− → B+ (closes the only unpinned code-execution path into an unsandboxed, Accessibility-privileged app)

#### E2 — Python daemon stderr is logged at `.public` and can contain transcript text
- **Where:** `Sources/Managers/MLDaemonManager+Process.swift:72` — `logger.error("ml_daemon stderr: \(message, privacy: .public)")`
- **What's wrong:** This is 1 of 29 explicit `.public` annotations (the codebase has zero `.private`; unannotated interpolations already default to private, so the `.public` marks are the entire disclosure surface). Most are benign — counts, request IDs, app names. This one is not: it forwards raw Python stderr, and `ml_daemon` handles the `correct` method whose parameters include the full transcript. A Python traceback from `mlx_lm` can embed the offending input in the exception message, which then lands in the unified log — persisted, readable by other admin-privileged processes, and swept up by `sysdiagnose`. The app's own README positions local modes as "audio stays on-device".
- **Fix:** Drop `privacy: .public` from that interpolation so it redacts by default, or truncate and sanitize before logging: log the exception type and first line only, never the payload. Audit the other 28 `.public` sites with the same question — `ErrorPresenter.swift:66,85` already sanitizes, which is the right model.
- **Effort:** S
- **Grade lift:** B− → B (removes a plausible transcript leak into system logs)

#### E3 — `codesign --deep` is deprecated and does not sign nested code correctly
- **Where:** `scripts/build.sh:343` — `codesign --force --deep --sign "$identity" --options runtime --entitlements AudioWhisper.entitlements AudioWhisper.app`
- **What's wrong:** Apple has deprecated `--deep` for signing; it applies the *same* entitlements to every nested binary and is documented as unsuitable for distribution signing. The script partly compensates by signing `Resources/bin/uv` separately first (`:340`), but then `--deep` re-signs it — with the app's full entitlements, including `com.apple.security.automation.apple-events`, granted to a general-purpose package manager binary.
- **Fix:** Replace with inside-out signing: sign each nested binary explicitly (`Resources/bin/uv` with no entitlements or a minimal set), then sign the outer bundle **without** `--deep`. Verify with `codesign --verify --deep --strict --verbose=2 AudioWhisper.app` (`--deep` is still correct for *verification*) and `spctl -a -vvv AudioWhisper.app`.
- **Effort:** S
- **Grade lift:** B− → B− (correct, non-deprecated signing; least-privilege for the bundled uv)

#### E4 — Model integrity is TOFU on a pointer file, not on the weights
- **Where:** `Sources/Services/MLXModelManager+Downloads.swift:304-338` and `ModelManager.swift:52-95` — `integrityFileURL` hashes `refs/main` (a single revision hash), explicitly because "hashing a full snapshot directory of multi-GB weights would block the [UI]"
- **What's wrong:** The sidecar detects local tampering with the *pointer* after first download, but nothing verifies the multi-GB weight files themselves, and nothing pins the expected revision against a known-good value — the first download is trusted unconditionally. A MITM or compromised mirror at first-download time is not detected. The tradeoff is deliberate and reasonably documented; the gap is that the revision is never pinned.
- **Fix:** Low-cost improvement: pin the expected HuggingFace revision hash per model in `ParakeetModel`/`MLXModel` and compare it to `refs/main` after download, rejecting a mismatch. That is an O(1) check that turns TOFU into pinning without hashing any weights. Optionally add opt-in background verification of `.safetensors` sizes against the HF API metadata.
- **Effort:** M
- **Grade lift:** B− → B (first-download trust becomes verifiable)

---

## F — Dependencies & Tech Currency — C−

This is where six months of not looking shows most, and it is the direct answer to "the models have advanced significantly." Four of six dependencies are materially behind, and — the important part — **three of the four are behind because of hard version caps in this repo, not because nothing was released.** Dependabot is configured (`.github/dependabot.yml`, weekly, Swift + Actions) but cannot cross a `<0.27.0` or `.upToNextMinor` boundary, so it has been silently unable to help.

| Dependency | Pinned here | Current | Gap |
|---|---|---|---|
| WhisperKit | `.upToNextMinor(from: "0.15.0")` → 0.15.0 | **1.0.0**, repo renamed to `argmaxinc/argmax-oss-swift` | 3 minors + a major, and the repo moved |
| KeyboardShortcuts | `.upToNextMajor(from: "1.10.0")` → 1.17.0 | **3.0.1** (Jun 17, 2026) | 2 majors |
| mlx-lm (Python) | `>=0.26.3, <0.27.0` | **0.31.3** | 5 minors, hard-capped |
| parakeet-mlx (Python) | `>=0.3.5, <0.4.0` | **0.5.2** (Jun 5, 2026) | 2 minors, hard-capped |
| ViewInspector | `.upToNextMinor(from: "0.10.0")` → 0.10.3 | current enough | — |
| swift-transformers / jinja / collections | transitive via WhisperKit | pinned by WhisperKit | moves with F1 |

#### F1 — WhisperKit 0.15 → Argmax OSS SDK 1.0 (package renamed and relocated)
- **Where:** `Package.swift:16` — `.package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMinor(from: "0.15.0"))`; consumed in `Sources/Services/LocalWhisperService.swift`, `Sources/Services/WhisperKitStorage.swift`, `Sources/Models/WhisperModel+WhisperKit.swift`
- **What's wrong:** WhisperKit reached **v1.0.0** and was restructured into the Argmax Open-Source SDK at `github.com/argmaxinc/argmax-oss-swift` (the old URL redirects; the CLI was renamed `whisperkit-cli` → `argmax-cli`). This repo is pinned to 0.15.0 with `.upToNextMinor`, which caps it at 0.15.x — so it missed 0.16, 0.17, 0.18, and 1.0 entirely, and Dependabot cannot propose the jump because the package identity changed. Beyond bug fixes and CoreML/ANE performance work, 1.0 adopts Swift 6 and ships **SpeakerKit** (pyannote diarization) and **TTSKit** (Qwen3-TTS) in the same package — speaker labels on multi-person recordings are a feature this app could offer essentially for free once migrated.
- **Fix:** Migrate deliberately, on a branch. Change `Package.swift` to `.package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0")`. Update the target dependency product name and the `import WhisperKit` sites (the umbrella is `import ArgmaxOSS`; check whether a `WhisperKit` product is still vended separately). Verify `WhisperKitStorage.swift:7`'s `argmaxinc/whisperkit-coreml` repo and the `openai_whisper-*` model naming in `WhisperModel+WhisperKit.swift:7-13` are unchanged in 1.0 — model-path changes are the likeliest breakage. Confirm the universal (arm64 + x86_64) release build still links, since 1.0 adopts Swift 6 and that is exactly the constraint that blocked F2.
- **Effort:** L
- **Grade lift:** C− → B− (back on a supported major; unlocks diarization and TTS)

#### F2 — KeyboardShortcuts stuck 2 majors back on a Swift-6-language-mode blocker
- **Where:** `Package.swift:11-15` with an explanatory comment: pinned below 2.0 because "KeyboardShortcuts 2.x requires Swift 6 language mode, which the universal release build (`swift build --arch arm64 --arch x86_64` via the Xcode build system) compiles as Swift 5." Resolved at 1.17.0; current is **3.0.1**.
- **What's wrong:** The reasoning is sound and well documented, but the cost compounds — two majors of fixes are now unavailable, including 3.0.1's "fix release build crash with Swift 6.3 compiler," which is precisely the kind of issue that bites when the toolchain moves. Since F1 pushes the project toward Swift 6 tooling anyway, the two blockers should be resolved together.
- **Fix:** Sequence after F1. Set `swiftLanguageVersions` / the per-target `swiftSettings: [.swiftLanguageMode(.v6)]` in `Package.swift`, then run the universal build (`scripts/build.sh`) to confirm the Xcode build system honours it for both arches — that is the specific claim to re-test, since it may simply have been fixed in a newer Xcode. If it holds, bump to `from: "3.0.0"`. If the universal build still forces Swift 5, document the retest date in the existing comment so the next person doesn't re-derive it.
- **Effort:** M
- **Grade lift:** C− → C+ (unblocks a dependency that has been frozen for two majors)

#### F3 — Python ML stack hard-capped below current, blocking newer models
- **Where:** `Sources/Resources/pyproject.toml:7-12` — `mlx-lm>=0.26.3, <0.27.0` and `parakeet-mlx>=0.3.5, <0.4.0`
- **What's wrong:** These are exclusive upper bounds, so `uv sync` can never pick up 0.27+ / 0.4+ no matter how long the app runs. Current releases are **mlx-lm 0.31.3** and **parakeet-mlx 0.5.2** (Jun 5, 2026). This is the mechanical reason "the models have advanced" hasn't reached the app: newer MLX model architectures require newer `mlx-lm` to load at all, so the correction model catalog (F4) is frozen by this pin as much as by the catalog itself. `parakeet-mlx` 0.4→0.5 similarly gates newer Parakeet checkpoints. Dependabot does not manage `pyproject.toml` — only Swift and GitHub Actions are configured — so nothing has been flagging this.
- **Fix:** Raise to `mlx-lm>=0.31,<0.32` and `parakeet-mlx>=0.5,<0.6`. Regenerate `Sources/Resources/uv.lock` (`uv lock` in a scratch project using the updated `pyproject.toml`). Verify against `Sources/ml/parakeet.py` — it calls `parakeet_mlx.audio.get_logmel`, `model.preprocessor_config`, and `model.generate(mel)`, all of which are plausible API-change surfaces across two minors; `extract_parakeet_text` already defends against several result shapes. Run `RUN_E2E=1 swift test --filter ParakeetEndToEndTests` to validate end to end. Add a `pip`/`uv` ecosystem entry to `.github/dependabot.yml` pointed at `Sources/Resources/` so this doesn't silently drift again. Do this **with** E1 — shipping the lockfile and raising the pins are the same change.
- **Effort:** M
- **Grade lift:** C− → C+ (unfreezes the ML runtime; prerequisite for F4)

#### F4 — Correction model catalog is frozen on 2024–early-2025 checkpoints
- **Where:** `Sources/Services/MLXModelManager.swift:43-65` — the four hardcoded `recommendedModels`: `Llama-3.2-1B-Instruct-4bit`, `gemma-3-1b-it-4bit`, `Qwen3-1.7B-4bit`, `Phi-3.5-mini-instruct-4bit`. Also `ParakeetModel` (`TranscriptionTypes.swift:98-123`) offers v2/v3 only.
- **What's wrong:** Llama 3.2 (Sep 2024) and Phi-3.5-mini (Aug 2024) are roughly two years old; gemma-3-1b and Qwen3-1.7B are from early 2025. The small-model tier has moved substantially since — Gemma 4 and Qwen 3.5 generations are current, and efficiency-focused families like LFM2 now cover the sub-2B slot that matters here. Because the list is a `static let` in Swift, refreshing it requires an app release, and F3's pin means newer architectures wouldn't load anyway. Note also that `Phi-3.5-mini-instruct-4bit` is labeled "Premium quality correction" at 2.4 GB — that's the largest download the app offers, spent on its oldest model.
- **Fix:** Sequence after F3. Benchmark 3–4 current sub-2B 4-bit MLX instruct models on this app's actual task (transcript cleanup against the category prompts in `~/Library/Application Support/AudioWhisper/prompts/`) using the `Tests/Resources/test_audio.wav` fixture plus a handful of real transcripts — pick on measured quality/latency, not release dates. Retire Phi-3.5-mini and Llama-3.2-1B if they lose. Longer term, move the catalog out of Swift: ship it as a JSON resource with a documented schema so a model refresh is a data change, and resolve B1's default from that single source.
- **Effort:** M
- **Grade lift:** C− → C+ (correction quality tracks the state of the art instead of a 2024 snapshot)

#### F5 — `Sources/Resources/uv.lock` is committed but never reaches users
- **Where:** `Sources/Resources/uv.lock` (90 KB, 2026-05-15); `scripts/build.sh:223-229`; `Package.swift:33` (`.copy("Resources")`)
- **What's wrong:** The lockfile is generated, committed, and bundled into the SPM resource copy — but `build.sh` never copies it into the `.app`, and `UvBootstrap` never copies it into the user's project dir. It contributes bundle weight and creates a false impression that Python deps are pinned. This is the artifact side of E1; listed separately because the cleanup is trivial even if E1's `--frozen` change is deferred.
- **Fix:** Resolved by E1 — start shipping and using it. If for some reason E1 is rejected, delete `Sources/Resources/uv.lock` and the misleading `build.sh` comment instead, so the repo stops claiming pinning it doesn't do. Do not leave it in the current middle state.
- **Effort:** S
- **Grade lift:** C− → C− (removes a misleading artifact; real lift comes with E1)

---

## G — Performance & Scalability — B

There is evident, deliberate performance work here, and most of it is the non-obvious kind. `FrameTimer` exists specifically to stop off-screen waveform tiles from driving hundreds of main-thread mutations per second. `SemanticCorrectionService.normalizedEditDistance` uses a two-row DP (O(min(m,n)) memory) with a hard `safeMergeLengthCap = 4000` above which it degrades to a length-ratio heuristic — with a comment explaining that a 30-minute transcript would otherwise stall the pipeline. `DiskMutationSerializer` streams SHA-256 in 64 KB chunks. `ModelManager` serializes per-model downloads so duplicate requests share one task while different models proceed in parallel. `MLDaemonManager` moves the blocking stdin write off the actor to avoid a pipe deadlock. History fetching is paginated with `fetchAllRecords` explicitly documented as export-only.

Three gaps keep it from B+, and two overlap with items already listed.

#### G1 — Three always-on main-thread timers (see C3)
- **Where:** `WaveformView.swift:171` (20 Hz), `InkRippleView.swift:60` (20 Hz), `WaveformContainer.swift:473` (2 Hz)
- **What's wrong:** Raw `Timer.publish(...).autoconnect()` fires for the view's entire lifetime regardless of visibility — the exact behaviour `FrameTimer` was written to eliminate. Two of the three run at 20 Hz on the main thread. In a menu-bar app that stays resident all day, this is continuous idle CPU.
- **Fix:** As C3 — convert to `FrameTimer` with `onAppear`/`onDisappear`, then add a SwiftLint `custom_rules` ban on `Timer.publish` outside `FrameTimer.swift`.
- **Effort:** S
- **Grade lift:** B → B+ (removes measurable idle CPU from a resident app)

#### G2 — Unbounded main-actor history fetches on delete (see B5)
- **Where:** `DataManager.swift:335-339` (fetch-all after a single delete, to rebuild stats), `:345-371` (fetch-all-then-loop for delete-all)
- **What's wrong:** Deleting one transcript triggers a full-table fetch on the `@MainActor`. At "Forever" retention with heavy daily use, this scales linearly with total history — the one place the otherwise well-paginated data layer doesn't bound its working set.
- **Fix:** As B5 — SwiftData batch delete for delete-all; incremental store updates instead of full rebuild for single deletes.
- **Effort:** M
- **Grade lift:** B → B+ (delete cost stops scaling with history size)

#### G3 — Long transcripts are sent to a 1.7B model in a single unchunked request (see B2)
- **Where:** `SemanticCorrectionService.swift:121-138`; the unused `chunkSizeWords`/`overlapSizeWords` at `:36-40`; the 1 MiB request cap at `MLDaemonManager.swift:57`
- **What's wrong:** No chunking exists. A long dictation goes to the model whole; it either overflows the context window (degrading output, which `safeMerge` then rejects — so the user silently gets uncorrected text) or, past 1 MiB, is rejected outright by `maxRequestBytes`. Either way the failure is invisible: `correctWithOutcome` returns `.failed(_, fallback: text)` and the UI shows a brief banner at most. Latency also grows superlinearly with input length on a 4-bit model.
- **Fix:** As B2 — implement chunk-and-stitch using the constants already declared, or delete them and add an explicit length guard with a user-visible reason. Measure first: correct a 5k-word transcript with the current build and record latency and `safeMerge` accept/reject, so the threshold is chosen from data.
- **Effort:** M
- **Grade lift:** B → B+ (long-transcript correction becomes reliable and bounded)

---

## H — Documentation & Onboarding — C−

The internal documentation is genuinely good — this grade is entirely about the front door. `docs/adr/` contains four well-written Nygard-format ADRs with real Context/Decision/Consequences (0001 on shipping unsandboxed is a model example, correctly anticipating the Accessibility-permission consequence). `CLAUDE.md` is accurate and useful. `CONTRIBUTING.md` and `Tests/README.md` exist. Inline documentation is unusually strong: comments explain *why* (`VenvSerializer`'s task-chain rationale, `FrameTimer`'s existence, `safeMergeLengthCap` marked "load-bearing"), and audit-item back-references make historical decisions traceable.

`README.md` — the file every new user and contributor reads first — describes a substantially different application than the one in this repository, and points at a different GitHub repo for every install path.

#### H1 — README describes removed cloud providers and links to the upstream repo throughout
- **Where:** `README.md` — cloud providers at lines 3, 12, 18, 34, 91-98, 124, 179-180, 208, 218, 244-245; upstream `mazdak/*` links at lines 6, 42, 56, 59, 66, 163
- **What's wrong:** Two distinct failures compounding.
  **(a) The app it describes no longer exists.** The README leads with "transcription using OpenAI Whisper, Google Gemini, Local WhisperKit, or Parakeet-MLX" and devotes a full setup section to obtaining OpenAI (`sk-`) and Gemini (`AIza`) API keys, custom Azure endpoints, and the Gemini Files API. `TranscriptionProvider` (`TranscriptionTypes.swift:14-26`) has exactly two cases: `.local` and `.parakeet`. There are no cloud API endpoints anywhere in `Sources/`. A new user follows the setup guide, cannot find where to paste an API key, and concludes the app is broken. The troubleshooting section ("API key problems") is advice for a feature that isn't there.
  **(b) Every install path points at the wrong repository.** `brew tap mazdak/tap`, `git clone https://github.com/mazdak/AudioWhisper.git` (twice), the Releases link, and the icon image all resolve to the upstream parent, not `jtn0123/AudioWhisper`. Users installing via the documented steps get upstream's build, not this one — which is a materially different app.
- **Fix:** Rewrite `README.md` against the shipping feature set. Delete the cloud provider sections wholesale (features, requirements, setup, troubleshooting, privacy) and replace the engine list with Local Whisper (WhisperKit/CoreML) + Parakeet-MLX. Strengthen the privacy section — with cloud gone, "audio never leaves your Mac" is now unconditionally true and is the app's best selling point. Replace all six `mazdak/*` links with `jtn0123/*` (verify the brew tap name against `scripts/update-brew-cask.sh` and `HOMEBREW.md`). Fix the icon `<img src>` to a path in this repo. Update "What's New Since v1.5.1" — `VERSION` says 2.0.0.
- **Effort:** M
- **Grade lift:** C− → B+ (the single highest-leverage fix in this report; the front door stops describing a different app)

#### H2 — Setup instructions understate the Xcode requirement
- **Where:** `README.md:35` and `CONTRIBUTING.md:19-21` both say "Swift 5.9+" / "Xcode 15.0+". `.github/workflows/ci.yml:22-31` selects Xcode 16 with the comment "Need Xcode 16+ (Swift 6 tooling): WhisperKit's transitive dependency swift-jinja 2.x declares swift-tools-version 6.0", and `codeql.yml` repeats it.
- **What's wrong:** A contributor on Xcode 15 follows the documented prerequisites and `swift build` fails to resolve `swift-jinja` 2.2.0. CI knows the real requirement and the docs don't. `CONTRIBUTING.md:29` also uses a `yourusername` clone-URL placeholder that was never filled in.
- **Fix:** Change both files to "Xcode 16.0+ (required — swift-jinja 2.x needs Swift 6 tooling)" with the same one-line rationale CI carries. Fix the `yourusername` placeholder to `jtn0123`. Re-verify after F1, which may raise the floor again.
- **Effort:** S
- **Grade lift:** C− → C (first-run build works from the documented steps)

#### H3 — ADR index is missing ADR 0004
- **Where:** `docs/adr/README.md` table lists 0001–0003. `docs/adr/0004-app-storage-migration.md` exists on disk.
- **What's wrong:** The index is the discovery mechanism for the ADR set; an unlisted ADR is effectively invisible. The README's own instructions ("update the table above") were not followed for the most recent entry — a small drift that undermines the whole convention.
- **Fix:** Add the 0004 row with its status. Consider a CI check comparing `ls docs/adr/*.md` against the table rows.
- **Effort:** S
- **Grade lift:** C− → C− (restores the index; trivial but the convention only works if it holds)

#### H4 — `CLAUDE.md` documents a test command the project cannot use
- **Where:** `CLAUDE.md` Build Commands: `swift test --parallel --enable-code-coverage`. Contradicted by `scripts/run-tests.sh:4-9` and `.github/workflows/ci.yml:78-84`, which both force `--no-parallel` and explain why (UserDefaults leakage).
- **What's wrong:** The documented coverage command produces the nondeterministic failures both scripts exist to avoid. Anyone following `CLAUDE.md` — human or agent — hits flaky results and has no reason to suspect the command itself.
- **Fix:** Change to `swift test --no-parallel --enable-code-coverage` with a one-line note pointing at `scripts/run-tests.sh` and the `IsolatedXCTestCase` migration. Revisit when D4 lands.
- **Effort:** S
- **Grade lift:** C− → C− (removes a documented instruction that reproduces a known failure mode)

---

## I — Developer Experience & Tooling — B

The tooling investment here is above average for a solo-maintained macOS app. Three CI workflows (build+test with a 60% coverage gate, CodeQL on Swift *and* Python with the macOS-runner constraint correctly handled, SonarCloud), a `bundle-smoke-test` job that validates the built `.app` structure and checks for unsubstituted version placeholders, Dependabot on Swift + Actions, a `.pre-commit-config.yaml`, SwiftLint in `--strict` mode with a thoughtful config (file/type/function length limits, cyclomatic complexity 15/25, a curated `identifier_name` allowlist), a `Makefile` with a real `help` target, and `scripts/run-tests.sh` that filters macOS framework noise. The build is clean — zero warnings.

Three defects, one of which means a CI gate has never actually gated anything.

#### I1 — The "No print() outside #if DEBUG" CI gate always passes
- **Where:** `.github/workflows/ci.yml:134-150`
- **What's wrong:** The check pipes `$violations` into `while IFS=: read -r file line _rest; do ... exit 1; done`. The pipeline runs the `while` body in a **subshell**, so `exit 1` terminates only that subshell — the step continues to `echo "No production print() found"` and exits 0. I verified this directly: a script with the same structure and a seeded violation prints its failure message and still exits 0. The gate has never been able to fail. (Fortunately there are currently no violations, so nothing has slipped through — but the protection is nominal.)
- **Fix:** Replace the pipe with a process-substitution loop (`while ... done < <(echo "$violations")`) so the loop runs in the current shell, or accumulate into a `failed=1` flag and `exit $failed` after the loop. Seed a deliberate `print()` in a scratch branch and confirm the job goes red before trusting it. The `.pre-commit-config.yaml` version of this check uses a different construction and does not share the bug.
- **Effort:** S
- **Grade lift:** B → B+ (a CI gate starts gating)

#### I2 — SwiftLint analyzer rules are configured but never run
- **Where:** `.swiftlint.yml:13-15` declares `analyzer_rules: [unused_import, unused_declaration]`. `.github/workflows/ci.yml:131` runs `swiftlint --strict`; `.pre-commit-config.yaml` runs `swiftlint lint --quiet`. Neither invokes `swiftlint analyze`.
- **What's wrong:** Analyzer rules only execute under `swiftlint analyze --compiler-log-path <log>`; `lint` silently ignores them. So the two rules that would catch dead code have never run — which is precisely why B3's two dead private methods, A1's 160-line unused container, B2's unused constants, and B6's orphaned URL builders all survive in a codebase that is otherwise scrupulously clean (0 TODOs, 0 `try!`, 0 `as!`, 3 force unwraps).
- **Fix:** Add a CI step after the build: capture the compiler log (`swift build 2>&1 | tee build.log`) then run `swiftlint analyze --strict --compiler-log-path build.log`. Expect an initial batch of findings — that batch *is* items A1, B2, B3, and B6. Keep it non-blocking for one PR, fix the backlog, then make it strict.
- **Effort:** M
- **Grade lift:** B → B+ (dead code becomes impossible to accumulate silently)

#### I3 — Tests forced sequential; documented commands disagree (see D4, H4)
- **Where:** `scripts/run-tests.sh:4-9`, `.github/workflows/ci.yml:78-84` (both `--no-parallel`) vs `CLAUDE.md` (`--parallel`)
- **What's wrong:** A 66-second sequential inner loop, and three sources of truth giving two different commands. The `run-tests.sh` header comment is honest about the cause and the intended fix (`IsolatedXCTestCase` migration), but the migration has stalled and nothing tracks it.
- **Fix:** As D4 — complete the `IsolatedXCTestCase` migration, flip both scripts to parallel, correct `CLAUDE.md`. Until then, add the remaining-migration count to `Tests/README.md` so the debt is visible.
- **Effort:** M
- **Grade lift:** B → B+ (faster loop, one documented command)

#### I4 — CI push triggers reference a stale one-off branch
- **Where:** `.github/workflows/ci.yml:4` — `branches: [ main, master, 'claude/**', 'grade-report-sweep' ]`
- **What's wrong:** `grade-report-sweep` was a one-off branch from the May audit and no longer exists. Harmless, but it is exactly the kind of leftover that makes the next reader unsure which patterns are load-bearing. `codeql.yml` and `sonarcloud.yml` trigger on `master` only, so the three workflows also disagree about which branches matter.
- **Fix:** Drop `grade-report-sweep`. Decide one convention across all three workflows — most likely `[master]` plus whatever working-branch glob you actually use — and apply it consistently.
- **Effort:** S
- **Grade lift:** B → B (removes stale config and aligns the three workflows)

---

## Suggested sequencing

These have real dependencies; running them in this order avoids rework.

1. **H1** — rewrite the README. Independent, highest user-facing impact, ~half a day.
2. **E1 + F3 + F5 together** — ship `uv.lock`, add `--frozen`, and raise the `mlx-lm`/`parakeet-mlx` caps in one change. They touch the same two files and the same regenerate-the-lock step; splitting them means locking twice.
3. **D1 + D4 together** — hunt the flake while completing the `IsolatedXCTestCase` migration. D4's shared-state leakage is the most likely root cause of D1, so fixing D4 may resolve D1 for free.
4. **A1 + B3 + B6 + I2** — enable `swiftlint analyze`, then delete what it finds. Turning on the tool first means the cleanup list is generated rather than hand-maintained.
5. **B1** — the default-model bug. Small, self-contained, user-visible; do it any time after the F3 pins land so testing happens on the runtime you're shipping.
6. **F1 → F2** — the WhisperKit 1.0 migration, then KeyboardShortcuts. Strictly ordered: F1 forces the Swift 6 tooling question that F2 is blocked on.
7. **C1 + C2** — accessibility and reduce-motion. Independent of everything above; good work to interleave.

**Do not start with F1.** It is the largest item here and the least reversible — a package rename plus a major version plus a Swift language-mode change, all landing in the transcription path. Get the test suite trustworthy (step 3) before attempting it, or you will not be able to tell a migration regression from an existing flake.
