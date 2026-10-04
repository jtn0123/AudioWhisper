# Codebase Grade Report

**Project:** AudioWhisper
**Audited:** 2026-08-25 (full re-audit)
**Graded:** `grade-fixes-top15` @ `53c585e` — 14 commits ahead of `master`, all committed
**Stack:** macOS 14+ menu-bar app — Swift 5.9 tools / SwiftUI + AppKit, AVFoundation + Accelerate audio, SwiftData persistence, WhisperKit (argmax-oss-swift) + Parakeet-MLX transcription, embedded uv-managed Python for MLX correction
**Previous report:** `.claude/grade-report-2026-08-25-preregrade.md` (overall B−, pre-work)

> This is a **fresh audit with fresh item IDs**, not the previous report with
> items struck through. Grades were re-derived from the measurements below.
> IDs from the earlier report (A1, D2, J1 …) no longer apply.

## Verified on this machine

| Measure | Result | Previous |
|---|---|---|
| Build | clean, **0 warnings** | 0 warnings |
| Tests | **2,890 / 2,890 pass**, `--parallel` | 2,839 |
| Line coverage (`Sources/` only) | **30.74%** (10,466 / 34,046) | 28.33% |
| SwiftLint `--strict` | **0 violations** in 369 files | 0 in 355 |
| `TODO` / `FIXME` | **0** | 0 |
| `try!` / `as!` | **0 / 0** | 0 / 0 |
| `fatalError` | 2 (both inside `#Preview`) | 2 |
| `URLSession` in `Sources/` | **0** (local-only by design) | 0 |
| `static let shared` | 17 | 17 |
| Accessibility modifiers | **135** across **31 / 70** view files | 92 across 25 / 70 |

### Coverage by layer

| Directory | Coverage | Covered / Total | Previous |
|---|---|---|---|
| Extensions | 100.0% | 11 / 11 | 100.0% |
| Models | 92.0% | 448 / 487 | 92.0% |
| Stores | 76.8% | 1,029 / 1,339 | 72.0% |
| Utilities | 74.3% | 570 / 767 | 72.4% |
| ViewModels | 68.3% | 797 / 1,167 | 59.0% |
| Services | 51.6% | 2,284 / 4,427 | 48.1% |
| Managers | 46.6% | 1,371 / 2,939 | 44.8% |
| App | 39.5% | 508 / 1,287 | 39.5% |
| **Views** | **15.9%** | **3,448 / 21,622** | 15.3% |
| **TOTAL** | **30.74%** | **10,466 / 34,046** | 28.33% |

Views are 63% of instrumented lines at 15.9%, and that single fact still sets the
headline number. What changed is *what* is untested: the app's primary flow, its
subprocess launching, and its provider routing have all moved out of the view
layer and are now covered. What remains in Views is much closer to actual SwiftUI
body code.

---

## Summary

| ID | Category | Grade | Prev | Items |
|----|----------|-------|------|-------|
| A | Architecture & Design | B+ | B− | 4 |
| B | Backend Quality | B+ | B | 3 |
| C | Frontend Quality | B− | C+ | 4 |
| D | Testing & Reliability | B− | C | 5 |
| E | Security | B | B− | 3 |
| F | Dependencies & Tech Currency | A− | B+ | 2 |
| G | Performance & Scalability | A− | B | 2 |
| H | Documentation & Onboarding | A− | B− | 3 |
| I | Developer Experience & Tooling | A | A− | 2 |
| **Overall** | | **B+** | **B−** | **28** |

**Top 5 highest-leverage fixes:** D1, C1, A1, E1, B1

### The one-paragraph read

The structural defects the last audit found are gone: no live implementation
shadowed by a dead tested one, no dead subsystem, no layer duplicated across View
and ViewModel. Hygiene remains close to spotless — zero warnings, zero lint
violations across 369 files, zero TODOs, zero force unwraps — and the tooling is
genuinely best-in-class, every CI gate carrying a written account of the failure
that motivated it. What holds the project at B+ is concentrated in two places,
both clearly visible now that everything around them is clean: **the SwiftUI view
layer is 63% of the codebase at 15.9% coverage** (D1/C1), and
**`ModelIntegrity.knownHashes` is still empty**, so the pinned-hash control ADR
0006 describes does not run (E1) — now honestly documented rather than
overstated, which improves integrity but not enforcement.

---

## A — Architecture & Design — B+ *(was B−)*

The defect that defined the last audit is resolved. `RecordingViewModel` and
`TranscriptionCoordinator` are the live orchestration path rather than a
tested-but-uncalled copy, and the three transcription entry points share one body
([RecordingViewModel+Transcription.swift](Sources/ViewModels/RecordingViewModel+Transcription.swift)).
The paste layer, which had *two live* implementations reached by different
triggers, is collapsed onto one. `KeychainService` — 194 lines nothing called —
is gone. Subprocess verification moved out of two view files into
[ModelVerificationService.swift](Sources/Services/ModelVerificationService.swift),
and the Core Audio HAL is separated from the volume policy built on it.

Layering is clean: `App` / `Views` / `ViewModels` / `Services` / `Stores` /
`Managers` / `Models` / `Utilities`, with large types split across focused
extension files. Concurrency primitives are custom and correct — `VenvSerializer`
chains tasks to survive `await` points inside the critical section;
`DiskMutationSerializer` clears failed entries synchronously so a failure is never
re-served. Six ADRs document the load-bearing calls.

B+ rather than A− because 17 singletons remain, the App and window-management
layer has no injection seams at all (39.5% coverage is largely that), and the
view layer still holds more than presentation.

#### A1 — The App and window-management layer has no test seams
- **Where:** [AudioWhisperApp.swift](Sources/App/AudioWhisperApp.swift) (0.0%, 72 missed), [MenuBarIcon.swift](Sources/App/MenuBarIcon.swift) (0.0%, 197), [AppDelegate+Lifecycle.swift](Sources/App/AppDelegate+Lifecycle.swift) (13.1%, 119), [WindowManager.swift](Sources/Managers/Windows/WindowManager.swift) (15.4%, 143), [WindowController.swift](Sources/Managers/Windows/WindowController.swift) (21.1%, 168), [WelcomeWindow.swift](Sources/Managers/Windows/WelcomeWindow.swift) (0.0%, 60)
- **What's wrong:** Every one reaches `NSApp` / `NSApplication.shared` / `NSWorkspace.shared` directly. `WindowController.storedTargetApp` is a static, and the window managers are singletons built at first use. Nothing can be substituted, so App sits at 39.5% and the window managers at 15–21%. This is the same class of problem the `SpeechToTextService` seam solved last round, not yet applied here — and it is now the largest untested *non-view* surface.
- **Fix:** Introduce a narrow `WindowHosting` protocol covering only what these use (`windows(matching:)`, `activate`, `orderOut`, `frontmostApplication`), default it to an `NSApp`-backed implementation, inject it. Start with `WindowController`, since `RecordingViewModel+Paste` depends on its static and that dependency is what makes paste tests awkward.
- **Effort:** M
- **Grade lift:** B+ → A− (removes the last layer with no seam at all)

#### A2 — 17 singletons, and the remaining ones have no injection seam
- **Where:** `static let shared` across 17 types — notably [ModelManager.swift](Sources/Services/ModelManager.swift), [MLXModelManager.swift](Sources/Services/MLXModelManager.swift), [MLDaemonManager.swift](Sources/Managers/MLDaemonManager.swift), [UvBootstrap.swift](Sources/Services/UvBootstrap.swift), [PermissionManager.swift](Sources/Managers/PermissionManager.swift)
- **What's wrong:** Several are defensible — one WhisperKit cache, one Python daemon. But `SpeechToTextService`, `MicrophoneVolumeManager` and `DataManager` were each given seams last round and their coverage moved to 86.7%, 100% and 76.8%. That demonstrates the pattern works and shows what the untouched ones cost. `MLXModelManager+Downloads` at 9.0% is the clearest case.
- **Fix:** Apply the established pattern — a protocol covering only what callers use, a `.shared` default, injection for tests. `MLXModelManager` first, since it owns the download path B1 also touches.
- **Effort:** M
- **Grade lift:** B+ → A− (compounds with A1)

#### A3 — Two bundled Python scripts are shipped but never invoked
- **Where:** `Sources/parakeet_transcribe_pcm.py`, `Sources/mlx_semantic_correct.py`; bundled by [Package.swift:35-36](Package.swift:35) and [scripts/build.sh:191](scripts/build.sh:191)
- **What's wrong:** `ResourceLocator.pythonScriptURL` is the only runtime script lookup and is called for exactly three names — `ml_daemon`, `verify_parakeet`, `verify_mlx`. These two ship in the bundle and are never executed: Parakeet transcription and MLX correction both route through `MLDaemonManager` → `ml_daemon.py` → `ml/rpc.py`. Roughly 300 lines of dead Python in the shipped product.
- **Fix:** Confirm once more against the daemon path, then remove both from `Package.swift` resources and `build.sh`, update [CLAUDE.md:132-133](CLAUDE.md:132) which still presents them as the transcription entry points, and fix the two `build.sh` warnings claiming "Parakeet functionality will not work" if absent — now false and actively misleading during a build failure. `Tests/Utilities/ResourceLocatorTests` and `Tests/MLXScriptTests` reference them and need updating.
- **Effort:** S
- **Grade lift:** B+ → B+ (removes dead shipped code and a misleading build warning)

#### A4 — Paste-target resolution still reaches global AppKit state
- **Where:** [RecordingViewModel+Paste.swift:78](Sources/ViewModels/RecordingViewModel+Paste.swift:78) reads `WindowController.storedTargetApp` (a static) and `NSWorkspace.shared`
- **What's wrong:** The duplication is fixed, but the surviving implementation still reaches globals, so `findValidTargetApp` and `performUserTriggeredPaste` remain hard to test — existing tests can only assert the nil and terminated branches. This is A1 seen from the paste side.
- **Fix:** Covered by A1's `WindowHosting` seam; no separate work if A1 lands first.
- **Effort:** S (after A1)
- **Grade lift:** B+ → B+ (unblocks meaningful paste tests)

---

## B — Backend Quality — B+ *(was B)*

The persistence layer is in good shape. Every fetch bounds itself — the
whole-history load that grew without limit under "forever" retention is replaced
by `forEachRecordPage` plus a bounded dashboard query
([DataManager+Fetching.swift](Sources/Stores/DataManager+Fetching.swift)) — and
`RebuildAccumulator` keeps the paged and array-taking rebuilds sharing one
definition of the arithmetic, which is how live and rebuilt totals stay in step.
Error types are rich and exhaustive; domain errors are deliberately preserved
rather than flattened. Subprocess invocation is injection-safe throughout:
`executableURL` plus an arguments array, never a shell, untrusted values as
`argv[n]`. Model-download outcome is decided by structured stdout JSON and the
exit code rather than by grepping `huggingface_hub`'s progress format.

Stores reached 76.8%. B+ rather than A− because Services sits at 51.6% and the
largest offender is the download path itself.

#### B1 — `MLXModelManager+Downloads` is 9.0% covered with 608 missed lines
- **Where:** [MLXModelManager+Downloads.swift](Sources/Services/MLXModelManager+Downloads.swift) (539 lines, 9.0%)
- **What's wrong:** Event parsing was extracted and is fully covered; everything around it is not. `performDownloadModel`'s venv bootstrap and error paths, `launchDownloadProcess`'s completion handling and pipe cleanup, `recordIntegrity`, and `isModelCachedOnDisk`'s hex-revision validation and snapshot-directory matching are all untested. That last one is security-relevant — it is what stops a crafted `refs/main` steering a path.
- **Fix:** `isModelCachedOnDisk` and `integrityFileURL` are pure filesystem logic, testable today against a fake HF cache tree (`MLXModelDownloadsCoverageTests.makeFakeHFCache` already builds one). Cover the revision-validation and snapshot-matching branches first; for the process paths, apply A2's seam.
- **Effort:** M
- **Grade lift:** B+ → A− (largest untested service, and part of it guards a path-traversal surface)

#### B2 — `UvBootstrap` is the other large untested service
- **Where:** [UvBootstrap.swift](Sources/Services/UvBootstrap.swift) (438 lines), [UvBootstrap+Process.swift](Sources/Services/UvBootstrap+Process.swift)
- **What's wrong:** It resolves `uv` across four candidate locations, compares versions, verifies the bundled binary's SHA-256, creates the venv and runs `uv sync --frozen`. Version comparison and bundled-binary verification are pure functions guarding a security boundary, and neither is directly tested.
- **Fix:** Extract `isVersion(_:greaterOrEqualThan:)` and the candidate-path resolution into testable helpers and cover them, including tampered-binary rejection with a fixture. Venv creation itself belongs to the nightly job.
- **Effort:** M
- **Grade lift:** B+ → A− (covers the integrity check on the one binary the app executes)

#### B3 — `AppDelegate` notification and lifecycle paths are 13% covered
- **Where:** [AppDelegate+Lifecycle.swift](Sources/App/AppDelegate+Lifecycle.swift) (13.1%, 119 missed), [AppDelegate+Notifications.swift](Sources/App/AppDelegate+Notifications.swift)
- **What's wrong:** Hotkey trigger routing, the `isTranscriptionProcessing` mirror that gates presses while a transcription is still running, and press-and-hold activation live here. The mirror is correctness-sensitive state kept in sync by notification.
- **Fix:** These are mostly pure state transitions on `AppDelegate` and can be driven by posting the notifications, without a window. Start with the `isTranscriptionProcessing` sync and the hotkey-ignored-while-processing branch.
- **Effort:** M
- **Grade lift:** B+ → B+ (covers the gate preventing overlapping transcriptions)

---

## C — Frontend Quality — B− *(was C+)*

The view layer is meaningfully better. It no longer owns the recording flow, the
paste flow, or subprocess launching. Accessibility went from 92 modifiers across
25 files to 135 across 31, and now covers the mandatory permission path and the
shared Dashboard settings rows, where `Toggle("") + .labelsHidden()` had left
VoiceOver announcing an unnamed switch. The design system, reduce-motion support,
the `ScrollableContent` workaround for `ImageRenderer`, and the snapshot
harness's blank-render guard were already good.

B− rather than B because 15.9% coverage across 63% of the codebase is still the
dominant fact, and the decomposition that would make it addressable has not
started.

#### C1 — Six Dashboard files hold ~4,700 uncovered lines
- **Where:** [DashboardHome+Sections.swift](Sources/Views/Dashboard/DashboardHome+Sections.swift) (0.0%, 886 missed), [DashboardCorrection+ModelPicker.swift](Sources/Views/Dashboard/DashboardCorrection+ModelPicker.swift) (0.0%, 857), [DashboardProviders+Correction.swift](Sources/Views/Dashboard/DashboardProviders+Correction.swift) (0.0%, 829), [DashboardVisualsView.swift](Sources/Views/Dashboard/DashboardVisualsView.swift) (1.0%, 798), [DashboardRecordingView.swift](Sources/Views/Dashboard/DashboardRecordingView.swift) (1.1%, 742), [DashboardProviders+LocalWhisper.swift](Sources/Views/Dashboard/DashboardProviders+LocalWhisper.swift) (0.0%, 621)
- **What's wrong:** Each holds several independent sections in one `body`, so there is no seam to render a piece in isolation. The subprocess logic has already been lifted out; what remains is genuinely view code, but *undecomposed* view code, which is why even a render-based test cannot reach most of it.
- **Fix:** Continue the pattern the codebase already established with `DashboardHome+Sections` and `CategoryEditorSheet+Sections` — pull each logical section into its own small `View` struct renderable standalone. Prioritise the model-picker and provider files, which carry the most branching (availability, download state, selection).
- **Effort:** L
- **Grade lift:** B− → B+ (the only route to moving the headline coverage number)

#### C2 — Accessibility still absent from 39 of 70 view files
- **Where:** no accessibility modifiers in e.g. [MLXModelManagementView.swift](Sources/Views/Dashboard/MLXModelManagementView.swift), [DashboardCategoriesView.swift](Sources/Views/Dashboard/DashboardCategoriesView.swift), [CategoryEditorSheet.swift](Sources/Views/Dashboard/CategoryEditorSheet.swift), [TranscriptionSearchBar.swift](Sources/Views/Transcription/TranscriptionSearchBar.swift)
- **What's wrong:** The permission path and shared settings rows are covered, which was the blocking case. What remains is model management and category editing — usable-but-awkward rather than blocking — plus the transcript search bar, which is a plain unlabelled field.
- **Fix:** Work outward from the shared components (`UnifiedModelRow`, `TranscriptionSearchBar`) since they are reused, then the category editor. Extend the existing `DashboardSettingsCardsAccessibilityTests` pattern.
- **Effort:** M
- **Grade lift:** B− → B (completes VoiceOver support beyond onboarding)

#### C3 — Oversized view files
- **Where:** [WaveformContainer.swift](Sources/Views/Components/Waveform/WaveformContainer.swift) (563), [DashboardHomeView.swift](Sources/Views/Dashboard/DashboardHomeView.swift) (519), [DashboardView.swift](Sources/Views/Dashboard/DashboardView.swift) (455), [CategoryEditorSheet.swift](Sources/Views/Dashboard/CategoryEditorSheet.swift) (373)
- **What's wrong:** All pass lint (`file_length` warns at 600) but each holds several independent subviews — the same root cause as C1 seen per-file. `WaveformContainer` is the notable one: real layout and animation logic, not just composition, sitting at 2.4%.
- **Fix:** Same treatment as C1. `WaveformContainer` first, since its logic is the most testable once separated.
- **Effort:** M
- **Grade lift:** B− → B (creates the seams C1 needs)

#### C4 — `@State` holding process-wide singletons
- **Where:** [DashboardView.swift:158](Sources/Views/Dashboard/DashboardView.swift:158) (`@State private var metricsStore = UsageMetricsStore.shared`) and similar across the 114 `@State` declarations in `Sources/Views`
- **What's wrong:** `@State` declares view-owned value state. Assigning a singleton works under `@Observable` but misstates ownership and re-evaluates the initializer on every `View` init. With only 11 `@Binding` against 114 `@State`, shared state is reached through singletons rather than passed — the view-side face of A2.
- **Fix:** Use `@Environment` injection registered at the window root, or a plain `let` referencing `.shared`, reserving `@State` for genuinely view-owned state.
- **Effort:** S
- **Grade lift:** B− → B− (correct SwiftUI semantics; enables injecting fakes)

---

## D — Testing & Reliability — B− *(was C)*

The suite is now substantially honest. The tautological tests are gone — four
files' worth that asserted on locally-declared variables, including one that set
a `Bool` to `true` and asserted it was `true`, and one that imported a module
which had not existed for some time and silently fell back to testing its own
mock. The app's primary flow went from 0.0% to 88.5%. Nine new suites cover the
LRU policy, the sample ring buffer, history paging, download events, model
verification, provider routing, the volume state machine and real audio decoding
— each written against extracted production logic rather than a restatement of it.

Infrastructure was always strong: per-process `UserDefaults` isolation keyed on
pid makes `--parallel` genuinely safe, `IsolatedXCTestCase` offers a strict mode,
the coverage gate measures `Sources/` only and enforces a ratchet taken from CI's
own baseline, and the nightly job runs the true end-to-end path.

B− rather than B because 30.74% is still low, the view layer is essentially
unmeasured, and one known flake is unresolved.

#### D1 — The view layer is 63% of the code at 15.9% coverage `[FE]`
- **Where:** `Sources/Views/` — 21,622 instrumented lines, 3,448 covered
- **What's wrong:** This is now the entire gap between 30.74% and a respectable number. Unlike last time it is no longer hiding orchestration or subprocess logic — the remaining lines really are SwiftUI bodies. But "we don't test SwiftUI" has a consequence: a view that stops rendering, a binding that stops propagating, or a state branch that never fires is caught by nothing except the local-only snapshot suite.
- **Fix:** Two tracks, in order. (1) Decompose per C1/C3 so sections render standalone. (2) Extend the existing render-based harnesses (`WaveformViewTests`, `DashboardViewTests`) to assert on the decomposed pieces. Treat 40% overall as the next ratchet target rather than chasing the number directly.
- **Effort:** L
- **Grade lift:** B− → B+ (the dominant remaining coverage fact)

#### D2 — `testConcurrentDuplicateEventsAreHandledCorrectly` is flaky `[both]`
- **Where:** [PressAndHoldKeyMonitorTests+DuplicateEvents.swift:141](Tests/PressAndHoldKeyMonitorTests+DuplicateEvents.swift:141)
- **What's wrong:** Failed once during a full `--parallel` run (`downCount` 2, expected 1), then passed 5/5 in isolation and again on two subsequent full runs. It fires 10 concurrent `processTransition(isKeyDownEvent:)` calls from `DispatchQueue.global()` and asserts the handler ran exactly once; under the load of 2,890 tests across parallel processes the dedup race can lose. Nothing in the recent 14 commits touches this code.
- **Fix:** Determine first whether this is a *test* race or a real one in `processTransition`'s dedup guard — the assertion may be catching a genuine bug. Do not loosen it to make CI green; that discards the only signal. If the guard is sound, the test needs a deterministic barrier rather than `RunLoop.run(until:)`.
- **Effort:** S
- **Grade lift:** B− → B (an ignored flake is how a real failure gets dismissed later)

#### D3 — Snapshot suite is local-only, so 35 baselines are unenforced `[FE]`
- **Where:** `Tests/__Snapshots__` (35 PNG baselines), gated behind `SNAPSHOT_TESTS=1`; rationale in [ci.yml](.github/workflows/ci.yml)
- **What's wrong:** The reasoning for excluding it is sound and documented — a GitHub runner has no usable WindowServer and produced 19–100% pixel divergence across all 34 renders measured. But the consequence stands, and given D1 it is the *only* view-layer safety net, running solely when a developer remembers.
- **Fix:** Do not put it in CI. Add a `make snapshot-check` target wrapping the documented invocation, reference it in the CONTRIBUTING pre-PR checklist, and have `.githooks/pre-commit` print a reminder when `Sources/Views/**` is staged. Converts "remember to" into a prompt.
- **Effort:** S
- **Grade lift:** B− → B− (no coverage change; stops the view-layer net depending on memory)

#### D4 — Python has one test file and no coverage gate `[BE]`
- **Where:** [Tests/test_correction_sanitize.py](Tests/test_correction_sanitize.py) is the only Python test; `Sources/ml/` is 870 lines
- **What's wrong:** `ml/correction.py` (228 lines) is covered around 31%; `ml/rpc.py`, `ml/loader.py` and `ml/parakeet.py` have no direct tests. `rpc.py` is the daemon protocol every transcription and correction crosses. The SonarCloud job uploads Python coverage now, but nothing gates on it.
- **Fix:** `rpc.py`'s framing and dispatch are pure and importable without mlx (the mlx imports in `correction.py` are already lazy). Add a test module for it alongside the sanitize tests in the existing CI step, then consider a Python coverage floor once there is a real number.
- **Effort:** M
- **Grade lift:** B− → B (covers the daemon protocol crossing every ML call)

#### D5 — Test-file naming still overstates coverage in places `[FE]`
- **Where:** `MLXModelManagementViewTests` → subject 0.0% (585 missed); `DashboardPermissionsViewTests` → 0.0% (407); `WaveformViewTests` → 0.0% (336); `CelebrationEffectsTests` → 1.0% (601); `DashboardVisualsViewTests` → 1.0% (798)
- **What's wrong:** Much better than last time — the two non-view offenders (`MicrophoneVolumeManager`, `AudioProcessor`) are now at 100% and covered. What remains is view files whose named tests assert on constants and enum cases rather than rendered behaviour, so a reviewer scanning `Tests/` still concludes more is covered than is.
- **Fix:** After C1/C3 decomposition, extend these to render the extracted sections. Where a test genuinely only checks constants, rename it (`…ViewConstantsTests`) so the naming stops overclaiming.
- **Effort:** M
- **Grade lift:** B− → B (aligns apparent coverage with real coverage)

---

## E — Security — B *(was B−)*

Fundamentals remain strong and two process gaps closed. Every `Process` uses
`executableURL` plus an arguments array — no shell anywhere — and untrusted
values like model repo names are passed as `argv[n]` rather than interpolated,
with the reasoning written at the call site. Subprocesses get a minimal
environment allowlist rather than the inherited environment. The bundled `uv` is
SHA-256 verified at runtime against a build-time stamp. Error messages are
redacted before display. Hardened runtime, notarization, three entitlements.
CodeQL covers Swift and Python. Local-only removes the exfiltration surface
entirely — zero `URLSession` in `Sources/`.

New: Dependabot watches the Python ecosystem, so the native scientific stack
finally generates advisories; integrity records moved out of the model directory
into app-owned storage, removing the trivial rewrite-both-files bypass;
`SECURITY.md` establishes a private disclosure path; and ADR 0006 states plainly
which half of it runs.

B rather than B+ because the flagship control still does not execute.

#### E1 — `ModelIntegrity.knownHashes` is still empty
- **Where:** [DiskMutationSerializer.swift:97](Sources/Utilities/DiskMutationSerializer.swift:97) — `static let knownHashes: [String: String] = [:]`
- **What's wrong:** `knownHash(for:)` returns `nil` for every model, so `verify` always takes the trust-on-first-use branch — including for app-shipped models on a first download, the exact case ADR 0006 exists to cover. It is now *documented* accurately rather than overstated, a genuine improvement in integrity, but the enforcement gap is unchanged. Deferred deliberately: populating the table needs a release build's cached download of every shipped model (~7 GB) and the audit machine had 4.7 GiB free.
- **Fix:** On a machine with space, download each shipped model via a release build and hash the representative file each caller passes — `config.json` via `ModelManager.representativeFileURL` for WhisperKit, `refs/main` via `MLXModelManager.integrityFileURL` for MLX/Parakeet. Add a test that a corrupted fixture throws `.pinnedMismatch`, and remove the `>>> ACTION REQUIRED <<<` marker and the ADR's *Implementation status* caveat in the same change. The failure mode is closed — a wrong pin rejects every legitimate download — so verify against two independent machines before shipping.
- **Effort:** M
- **Grade lift:** B → B+ (turns the documented control into an enforced one)

#### E2 — Model cache path validation is untested
- **Where:** [MLXModelManager+Downloads.swift](Sources/Services/MLXModelManager+Downloads.swift) — `isModelCachedOnDisk`, which reads `refs/main`, requires pure hex, then matches against the actual `snapshots/` directory listing rather than interpolating into a path
- **What's wrong:** The defence is correct and its comment explains exactly why the path is built only from a filesystem-returned name. But it is untested, in a file at 9.0% coverage, and it is what stands between a crafted `refs/main` and a path outside the cache.
- **Fix:** `makeFakeHFCache` already builds a cache tree. Add cases for a non-hex revision, an empty `refs/main`, a revision containing path separators, and a revision naming a nonexistent snapshot — asserting each is rejected.
- **Effort:** S
- **Grade lift:** B → B+ (locks in a path-traversal defence currently relying on nobody editing it)

#### E3 — Trust-on-first-use remains fundamentally limited
- **Where:** [DiskMutationSerializer.swift](Sources/Utilities/DiskMutationSerializer.swift) — records now under `~/Library/Application Support/AudioWhisper/model-integrity/`
- **What's wrong:** The record moved out of the model directory, removing the trivial bypass, and the doc comment now states honestly what each mode does and does not deliver. But a local process running as the user can still reach both model and record. The app is unsandboxed by design (ADR 0001), so no boundary at this layer fixes it.
- **Fix:** Nothing further at this layer; E1 is the real answer for shipped models. Worth surfacing the TOFU boundary in the UI when a user adds a custom repo, which ADR 0006 lists as an open consequence and which remains undone.
- **Effort:** S
- **Grade lift:** B → B (user-facing honesty about a limitation that cannot be engineered away)

---

## F — Dependencies & Tech Currency — A− *(was B+)*

Managed with real deliberation. Three pinned dependencies, all current:
`argmax-oss-swift` 1.0.0, `KeyboardShortcuts` 3.0.1, `swift-argument-parser`
1.8.2. Both recent moves were made for stated, verified reasons — the
`KeyboardShortcuts` 3.x bump after retesting the belief that it needed Swift 6
language mode, and the WhisperKit migration after discovering an `upToNextMinor`
pin had silently skipped four releases. `Package.resolved` is committed;
`uv.lock` is committed *and* verified against `pyproject.toml` in CI with
`uv lock --check`, because `uv sync --frozen` does not detect drift itself. The
Python pins carry exclusive upper bounds and a four-step bump checklist naming
the exact API surface to re-verify.

Dependabot now covers all three ecosystems — swift, github-actions and uv —
closing the hole where the native scientific stack generated no advisories.
`CLAUDE.md` no longer lists three libraries that do not exist.

#### F1 — No dependency-review gate on PRs
- **Where:** `.github/workflows/` — CodeQL and Dependabot are configured; no `actions/dependency-review-action`
- **What's wrong:** Dependabot opens PRs and CodeQL scans code, but nothing fails a PR that *introduces* a dependency with a known advisory. For a project that executes downloaded model weights and a Python runtime, the introduction path is the one worth gating.
- **Fix:** Add `actions/dependency-review-action` to the PR workflow. A few lines, no secrets required.
- **Effort:** S
- **Grade lift:** A− → A (closes the introduce-a-vulnerable-dep path)

#### F2 — The Python bump checklist is documentation, not a check
- **Where:** [Sources/Resources/pyproject.toml](Sources/Resources/pyproject.toml) — the four-step checklist for raising `mlx-lm` / `parakeet-mlx`
- **What's wrong:** Step 3 says to re-verify the API surface `Sources/ml/` uses, naming six symbols, because these libraries break it across minors. Nothing enforces it: a bump satisfying `uv lock --check` can still break `parakeet_mlx.from_pretrained` at runtime, surfacing only in the nightly job.
- **Fix:** Add a small import-and-`getattr` smoke script asserting each named symbol exists, run in the nightly job *before* the end-to-end test so a break is attributed to the API change rather than the model.
- **Effort:** S
- **Grade lift:** A− → A (turns a checklist into a gate)

---

## G — Performance & Scalability — A− *(was B)*

Sampled the audio path, the hashing path and the data layer; all three are clean.
The realtime audio thread does no allocation in steady state —
`SampleRingBuffer` writes into preallocated storage, and the snapshot copy
happens only on the 60 Hz publish rather than on all ~94 callbacks per second.
FFT uses Accelerate/vDSP with a pre-computed Hann window and a single `fftSetup`.
SHA-256 streams in 64 KB chunks so gigabyte models do not blow up memory. Every
SwiftData fetch bounds itself and the aggregate paths page. Audio is validated
once per transcription rather than twice. The menu bar reads a cached snapshot.

#### G1 — 60 Hz `Task { @MainActor }` hop per publish
- **Where:** [AudioEngineRecorder.swift:409](Sources/Services/Audio/AudioEngineRecorder.swift:409)
- **What's wrong:** Each publish allocates a `Task` to hop to the main actor and assign three published properties — 60 task allocations plus three `@Observable` invalidations per second while recording. Not a correctness issue and not a dropout risk, since it is off the audio thread, but it is the largest remaining per-second allocation in the recording path.
- **Fix:** Measure first; this may be below the noise floor. If not, coalesce the three assignments into one value type so `@Observable` invalidates once, and consider an `AsyncStream` with `.bufferingNewest(1)` instead of a task per frame.
- **Effort:** S
- **Grade lift:** A− → A− (only if measurement justifies it — listed for completeness, not urgency)

#### G2 — `DashboardHomeView` scans the full history on every open
- **Where:** [DashboardHomeView.swift](Sources/Views/Dashboard/DashboardHomeView.swift) — `loadDashboardData` runs `forEachRecordPage` over every record to build provider stats and daily activity
- **What's wrong:** Memory is now bounded, which was the actual defect. But the *scan* is still O(total records) on every dashboard open, and daily activity only needs the last 28 days. With years of history that is a growing latency cost for a fixed-size display.
- **Fix:** Bound the daily-activity scan with a date predicate for the last 28 days. Provider stats genuinely need everything, so either accept that scan or maintain running per-provider counters in `UsageMetricsStore` the way session totals already are.
- **Effort:** S
- **Grade lift:** A− → A (removes the last unbounded-*work* path, as distinct from unbounded memory)

---

## H — Documentation & Onboarding — A− *(was B−)*

Where this repo's documentation is fresh it is exceptional, and it is now fresh
where it matters most. Comments explain *why*, and specifically which failure
motivated the code — the coverage gate records that it was reading the wrong
`awk` column and had therefore never enforced anything; the SwiftLint pin records
the 144-vs-46 finding swing between versions; the `print()` gate records that its
`exit 1` ran in a subshell and silently passed on every run; `run-tests.sh`
records that an EXIT-trap cleanup leaked 4,335 plists by racing `cfprefsd`.

The two entry-point documents are correct now. `CLAUDE.md` lists the actual
dependency set and documents the CLT/`actool` trap that makes bare `swift build`
fail with an error naming neither cause nor fix. `CONTRIBUTING.md` states the real
Xcode floor and no longer claims an internet connection is needed for
transcription. ADR 0001 and ADR 0006 are corrected — 0006 now states which half of
it actually runs. `SECURITY.md` establishes disclosure.

#### H1 — `CLAUDE.md` lists two Python scripts that are never executed
- **Where:** [CLAUDE.md:132-133](CLAUDE.md:132)
- **What's wrong:** "Python Integration" presents `parakeet_transcribe_pcm.py` as "Parakeet transcription" and `mlx_semantic_correct.py` as "MLX semantic correction". Neither is invoked — both paths go through `ml_daemon.py`. This is the file that configures agent sessions, so it points future work at the wrong entry points.
- **Fix:** Bundled with A3. Describe the daemon path as the real one and either delete the two scripts or mark them explicitly unused.
- **Effort:** S
- **Grade lift:** A− → A (last inaccuracy in the highest-traffic document)

#### H2 — `build.sh` warns about consequences that no longer follow
- **Where:** [scripts/build.sh:195](scripts/build.sh:195), [:202](scripts/build.sh:202)
- **What's wrong:** "⚠️ parakeet_transcribe_pcm.py not found, Parakeet functionality will not work" — false, since the daemon handles transcription. A warning that misstates the consequence is worse than none during a build failure, because it sends the reader down the wrong path.
- **Fix:** Bundled with A3.
- **Effort:** S
- **Grade lift:** A− → A

#### H3 — No architecture overview for the ML subsystem
- **Where:** `docs/adr/` covers six decisions; nothing maps the Swift↔Python boundary end to end
- **What's wrong:** Transcription crosses `ParakeetService` → `MLDaemonManager` → a subprocess → `ml_daemon.py` → `ml/rpc.py` → `ml/parakeet.py`, with the venv bootstrapped by `UvBootstrap` and models fetched by `MLXModelManager`. Each piece is well commented; nothing states the shape. The evidence it is needed: two scripts sat in the bundle looking like entry points (A3/H1).
- **Fix:** One page in `docs/` with a sequence diagram for a single transcription and a note on which process owns what. It is the missing piece that would have made A3 obvious.
- **Effort:** S
- **Grade lift:** A− → A (makes the least-obvious subsystem legible)

---

## I — Developer Experience & Tooling — A *(was A−)*

The standout category, and it improved. Every CI gate carries a written diagnosis
of a time it was caught failing open, and each was repaired rather than removed.
Gate strictness is chosen deliberately: `unused_import` is enforced at zero
because the backlog was triaged by removing each import and letting the compiler
be the oracle, while `unused_declaration` is a ratchet because much of what
remains is structural. The coverage ratchet was set from CI's own measured
baseline, with the reason recorded — a dev box with cached models runs a
different test set than a clean runner. `scripts/lib/xcode-env.sh` fixes the CLT
trap per-process without `sudo`, and all three entry-point scripts source it.

New: the SonarCloud job no longer runs the suite a second time sequentially, and
an opt-in pre-commit hook shifts SwiftLint strict, the `print()` gate and
`uv lock --check` left. Measured: 0 warnings, 0 violations across 369 files,
2,890 green tests.

#### I1 — The suite still runs twice per PR
- **Where:** [ci.yml](.github/workflows/ci.yml) `build-and-test` and [sonarcloud.yml:71](.github/workflows/sonarcloud.yml:71)
- **What's wrong:** Both run `--parallel` now, which roughly halved the Sonar job, but it is still a second full execution of 2,890 tests on a separate macOS runner purely to produce a coverage artifact the first job already generated. With the `analyze` job's `xcodebuild build-for-testing` and `bundle-smoke-test`'s `make build`, a PR still pays for four builds.
- **Fix:** Have `build-and-test` upload its codecov JSON and `coverage.lcov` as artifacts, and have the Sonar job download and convert them. Removes the second run entirely and guarantees Sonar reports the same number the coverage gate enforced. Needs `workflow_run` plumbing or merging the workflows — a deliberate structural change, which is why it was left.
- **Effort:** M
- **Grade lift:** A → A (removes the largest remaining CI cost with no loss of signal)

#### I2 — The pre-commit hook is opt-in and undiscoverable
- **Where:** [.githooks/pre-commit](.githooks/pre-commit), documented in [CONTRIBUTING.md](CONTRIBUTING.md)
- **What's wrong:** It requires `git config core.hooksPath .githooks`, and nothing prompts for it. A contributor who does not read that section gets no benefit, which is most of them.
- **Fix:** Add a `make setup` target that sets `core.hooksPath`, installs the pinned SwiftLint version and prints the toolchain state; point at it from the CONTRIBUTING quick start. One command instead of a paragraph.
- **Effort:** S
- **Grade lift:** A → A (adoption, not capability)

---

## Appendix — how to use this report

Item IDs are stable for the lifetime of this file, and are **new** — the previous
report's IDs do not map onto these.

```bash
/grade-codebase D1 C1 A1
```

To re-grade one category after fixes:

```bash
/grade-codebase D
```

**Suggested sequencing.** Two things gate the overall grade: the view layer
(C1 → C3 → D1, in that order, since decomposition is what makes coverage
reachable) and E1. A1/A2 are the structural follow-through that would take
Architecture to A− and lift App, Managers and Services coverage with it.
Everything marked S is a day or less and independent.
