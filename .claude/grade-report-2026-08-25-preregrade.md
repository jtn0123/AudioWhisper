# Codebase Grade Report

**Project:** AudioWhisper
**Audited:** 2026-08-24
**Graded:** `master` @ `8dee2a4` (synced with `origin/master`, 0 ahead / 0 behind, no open PRs)
**Stack:** macOS 14+ menu-bar app — Swift 5.9 tools / SwiftUI + AppKit, AVFoundation + Accelerate audio, SwiftData persistence, WhisperKit (argmax-oss-swift) + Parakeet-MLX transcription, embedded uv-managed Python for MLX semantic correction
**Previous report:** `.claude/grade-report-2026-08-03.md` (graded `master @ 47dc121` plus the then-open PR #27; both #27 and #28 have since merged, so that report describes a state that no longer exists)

## Verified on this machine

Everything below is measured, not estimated.

| Measure | Result |
|---|---|
| Build (`swift build`) | clean, **0 warnings** |
| Tests | **2,839 / 2,839 pass**, `--parallel`, exit 0 |
| Line coverage (`Sources/` only, via `scripts/coverage-gate.py`) | **28.33%** (9,742 / 34,390 across 156 files) |
| SwiftLint `--strict` | **0 violations, 0 serious** in 355 files |
| `TODO` / `FIXME` in `Sources/` | **0** |
| `try!` / `as!` / force-unwrap | **0 / 0 / 2** (the 2 are `fatalError` inside `#Preview` blocks) |

### Coverage by layer — this is the whole story

| Directory | Coverage | Covered / Total |
|---|---|---|
| Extensions | 100.0% | 11 / 11 |
| Models | 92.0% | 448 / 487 |
| Utilities | 72.4% | 513 / 709 |
| Stores | 72.0% | 899 / 1,249 |
| ViewModels | 59.0% | 473 / 802 |
| Services | 48.1% | 2,150 / 4,466 |
| Managers | 44.8% | 1,315 / 2,934 |
| App | 39.5% | 508 / 1,287 |
| **Views** | **15.3%** | **3,425 / 22,445** |
| **TOTAL** | **28.3%** | **9,742 / 34,390** |

Views are 65% of all instrumented lines and are covered at 15%. That single fact
sets the headline number. It would be a forgivable trade-off — except that the
app's *primary user flow* lives in a View extension (see A1/D1), so "we don't
test SwiftUI chrome" does not actually describe what is untested.

---

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Architecture & Design | B− | 5 |
| B | Backend Quality | B | 4 |
| C | Frontend Quality | C+ | 5 |
| D | Testing & Reliability | C | 5 |
| E | Security | B− | 4 |
| F | Dependencies & Tech Currency | B+ | 3 |
| G | Performance & Scalability | B | 3 |
| H | Documentation & Onboarding | B− | 4 |
| I | Developer Experience & Tooling | A− | 3 |
| **Overall** | | **B−** | **36** |

> **Status 2026-08-24:** 20 of 36 items executed on branch `grade-fixes-top15`
> (see the Execution log below). The grades in this table are the **pre-work**
> audit and are left as-is for comparison — run `/grade-codebase` for a fresh
> measurement. **33 of 37 items are now closed** across two execution passes
> (2026-08-24 and 2026-08-25). Still open: **E1** (needs ~7 GB of model
> downloads; skipped for disk space), **C3**, **C5**, **D4**, plus newly-found
> **K1** and **K2**.

**Top 5 highest-leverage fixes:** A1, D1, E1, D2, I1
*(A1, D1, D2, I1 done; E1 skipped by request.)*

### The one-paragraph read

This is a carefully maintained codebase with genuinely exceptional tooling
discipline — every CI gate carries a comment explaining the exact failure that
motivated it, and several of those gates were fixed after being caught silently
passing. Code hygiene is close to spotless: zero warnings, zero lint violations,
zero TODOs, zero force-unwraps. What holds it back is concentrated and
identifiable: a half-finished ViewModel migration left the app running an
*untested* copy of its core recording flow while the *tested* copy sits dead
(A1); a meaningful slice of the 2,839 tests assert on locally-constructed
variables rather than production code, under filenames that imply otherwise
(D2); and the model-integrity control that ADR 0006 documents as a hard fail is
inert because its hash table is empty (E1). Fix those three and this is a solid
B+/A− project.

---

## Execution log — 2026-08-24

**Branch:** `grade-fixes-top15` (not merged, not pushed). 43 files changed,
+720 / −1,783.

**Verified after the work:** build clean with **0 warnings** · **2,848 / 2,848
tests pass** (`--parallel`) · SwiftLint `--strict` **0 violations in 361 files** ·
line coverage **28.33% → 29.95%**.

The headline number understates it, because Views are 65% of instrumented lines
and were not the target. Where the work landed:

| File | Before | After |
|---|---|---|
| `RecordingViewModel+Transcription.swift` (the flow from `ContentView+Recording`) | **0.0%** | **88.5%** |
| `TranscriptionCoordinator.swift` (had no production callers) | 59% dead | **72.4%** live |
| `UsageMetricsStore.swift` | ~72% | **97.6%** |
| `LRUAccessTracker.swift` (extracted) | n/a | **100%** |
| `MLXDownloadEvent.swift` (extracted) | n/a | **100%** |
| `SampleRingBuffer.swift` (extracted) | n/a | **97.7%** |
| Stores (directory) | 72.0% | **76.8%** |
| ViewModels (directory) | 59.0% | **68.4%** |
| Services (directory) | 48.1% | **51.9%** |

`ContentView+Recording.swift` still reads 0%, but it is now 56 lines of pure
delegation rather than 292 lines of orchestration.

### Corrections to this report found during execution

Three claims above were wrong, and are corrected here rather than quietly fixed:

1. **I2 was half wrong.** The report said `scripts/build.sh` does not source
   `xcode-env.sh`. It does — lines 3–5, and has all along. My grep pattern only
   matched `DEVELOPER_DIR`/`xcode-select` literals and missed
   `ensure_xcode_toolchain`. All three scripts already self-heal; only the
   documentation half of I2 was real, and that is what was fixed.
2. **C2 overstated the gap.** `PermissionModals.swift` was described as having
   accessibility "entirely absent". It actually carries 12 accessibility
   modifiers for 6 controls — it was already good. The real gaps were
   `DashboardSettingsCards.swift` (**0** modifiers for 10 controls) and
   `DashboardPermissionsView.swift` (3 for 8), which is where the fix went. That
   turned out to be higher-leverage anyway: `SettingsToggleRow` renders
   `Toggle("")` + `.labelsHidden()`, leaving an unnamed switch, and it is a
   shared row used across every Dashboard settings screen.
3. **B2 was larger in the report than in reality.** The download script already
   emitted structured JSON on stdout and `launchDownloadProcess` already decided
   success from the exit code. The genuine defect was narrower: stderr was
   allowed to *set error state* by substring match. That is what changed.

### Scope discoveries

- **A2 cascaded well beyond its stated scope.** Deleting `KeychainService`
  removed ~20 further tests across 8 files — and every one of them was the same
  tautology as D2: they configured the *mock* to throw and asserted the *mock*
  threw. `ErrorPropagationLayerTests.testKeychainErrorPropagesToSpeechService`
  never touched the speech service at all. `Logger.keychain` went with it.
- **A fourth tautological test surfaced.** `LoggerCategoryTests.testExpectedCategories`
  declared a local array of category-name strings and asserted that array's own
  `count` — it never referenced `Logger`, and only broke because A2 changed a
  hardcoded literal. Removed.
- **`ContentView+Paste.swift` is a second parallel duplicate** of
  `RecordingViewModel+Paste.swift` — `currentSourceAppInfo` and
  `findFallbackTargetApp` exist in both, byte-identical. Unlike the recording
  layer, the View copy here is still live. **Not fixed** — outside the approved
  A1/A3 scope. Logged as a new item below.
- **D2's stated fix was not achievable.** The report proposed testing LRU
  eviction "through `LocalWhisperService`'s public surface". `WhisperKitCache`
  is a `private actor` holding real `WhisperKit` instances that need downloaded
  models, so there is no such surface. The policy was extracted into
  `LRUAccessTracker` and tested directly instead.
- **A4 moved a test seam.** `StubSpeechToTextService` overrode `transcribeRaw`;
  once the pipeline called `transcribeValidated` the stub stopped intercepting
  and a test attempted a real Parakeet transcription. Fixed, and
  `testPipelineUsesValidatedEntryPointSoAudioIsNotValidatedTwice` now guards it —
  double validation is invisible at runtime, so nothing else would catch a revert.
- **`DataManager` outgrew `type_body_length`** once paging was added. Split into
  `DataManager+Fetching.swift` rather than suppressing the rule.

### Known gaps left open

- **Clipboard delivery is untested.** A test asserting the final transcript
  reaches the clipboard is inherently flaky: `PasteManager.copyToClipboard`
  hardcodes `NSPasteboard.general`, a system-wide resource shared by every
  parallel `xctest` process, and a sibling test won the race on the first run.
  Removed rather than shipped flaky; needs an injectable pasteboard on
  `PasteManager`. Documented in `RecordingViewModelTranscriptionFlowTests`.
- **E1 skipped by request.** `ModelIntegrity.knownHashes` is still empty and
  ADR 0006 still describes an enforcement that does not run.
- **I1 done by halves.** The Sonar job now runs `--parallel` instead of
  `--no-parallel`, roughly halving it. Removing the second full test run
  entirely needs cross-workflow artifact plumbing; noted inline in the workflow.

### New item found during execution

#### ~~J1~~ ✓ done 2026-08-25 — `ContentView+Paste.swift` duplicates `RecordingViewModel+Paste.swift`
- **Where:** [ContentView+Paste.swift:76](Sources/Views/ContentView+Paste.swift:76) vs [RecordingViewModel+Paste.swift:88](Sources/ViewModels/RecordingViewModel+Paste.swift:88) (`findFallbackTargetApp`), and the `currentSourceAppInfo` pair
- **What's wrong:** The same defect A1 fixed for the recording layer, still present in the paste layer: two implementations of the same helpers, one on the `View` and one on the ViewModel. The View's copy is live (`performUserTriggeredPaste` is called from `ContentView`), so this is not dead code — it is an active fork that can diverge.
- **Fix:** Same shape as A1 — have `ContentView+Paste` delegate to the ViewModel's implementations and delete the View-side copies. Verify `findValidTargetApp` and `activateTargetAppAndPaste` have no View-only dependencies first.
- **Effort:** M
- **Grade lift:** A → A+ (removes the last live duplicated layer)

---

## Execution log — 2026-08-25 (remaining top 10)

**Branch:** `grade-fixes-top15` (continued; not committed, not pushed).

**Verified:** build clean, **0 warnings** · **2,890 / 2,890 tests pass**
(`--parallel`) · SwiftLint `--strict` **0 violations in 369 files** · coverage
**29.95% → 30.77%**.

Executed: J1, A5, C4, D3, B4, E3, D5, I3, E4, plus H3, H4, F3.
**E1 skipped** (see below). 33 of 37 items now closed.

| File | Before | After |
|---|---|---|
| `MicrophoneVolumeManager.swift` | 6.4% | **100%** |
| `SpeechToTextService.swift` | ~46% | **86.7%** |
| `DiskMutationSerializer.swift` | ~65% | **81.5%** |
| Managers (directory) | 44.8% | **46.6%** |
| Utilities (directory) | 73.3% | **74.3%** |

### E1 skipped — and nothing was downloaded

You pre-authorised skipping this and deleting any hash file. **No model or hash
file was ever downloaded, so there is nothing to delete.** The check that decided
it: `/System/Volumes/Data` had **4.7 GiB free at 98% capacity**, with `.build`
alone at 5.0 GB. Populating `knownHashes` needs the four WhisperKit models
(~2.1 GB), two Parakeet models (~5 GB) and a correction model (0.6–2.4 GB) —
comfortably more than the free space. Disk ended the session at 5.0 GiB free,
essentially unchanged.

H3 was done instead: ADR 0006 now carries an *Implementation status* section
stating plainly that the pinned-hash half does not run, with a table of what is
actually enforced today and the steps to close it.

### Corrections to the plan, found while executing

1. **D5's premise was wrong.** `Tests/test_parakeet_transcribe.py` imports
   `parakeet_transcribe`; the real module is `parakeet_transcribe_pcm`. The
   import therefore **always** failed, the file defined its own
   `MockParakeetTranscribe`, and 8 of its 12 tests exercised that self-defined
   mock while 4 skipped. Wiring it into CI would have enshrined a fake pass — a
   fifth tautology. Deleted instead. The real module has hard module-level
   `numpy`/`mlx` imports and cannot run under plain `python3`; it is covered by
   the nightly end-to-end job, which is the right place for it.
2. **D3's "no rendering excuse" was only half right.** Both subjects were
   blocked by hardware, not neglect: `MicrophoneVolumeManager` called the Core
   Audio HAL against the machine's real default input device (a test would have
   changed the developer's microphone volume for real, and CI has no input
   device), and `AudioProcessor.loadAudio` **short-circuits under test by
   design**, returning a hardcoded five-element array — which is why the tests
   named after it could only assert on the stub. Both needed a seam before any
   test could mean anything.
3. **C4 was bigger than described.** The verify flow existed *twice*, verbatim,
   in two view files — including two separate `private actor
   VerificationMessageStore` declarations with identical members.

### New findings

#### K1 — Two bundled Python scripts are never invoked
- **Where:** `Sources/parakeet_transcribe_pcm.py`, `Sources/mlx_semantic_correct.py`; bundled by [Package.swift:35](Package.swift:35) and [scripts/build.sh:191](scripts/build.sh:191)
- **What's wrong:** `ResourceLocator.pythonScriptURL` is the only runtime script lookup, and it is called for exactly three names: `ml_daemon`, `verify_parakeet`, `verify_mlx`. These two are shipped in the app bundle and never executed — Parakeet transcription and MLX correction both go through `MLDaemonManager` → `ml_daemon.py` → `ml/rpc.py`. `build.sh` still warns "Parakeet functionality will not work" if the file is absent, which is now false and would mislead anyone debugging a build.
- **Fix:** Confirm against the daemon path, then drop both from `Package.swift` resources and `build.sh`, and remove the stale warnings. `Tests/Utilities/ResourceLocatorTests` and `Tests/MLXScriptTests` reference them and would need updating. **Not done here** — removing a shipped bundle resource is a deliberate call, not an audit cleanup.
- **Effort:** S
- **Grade lift:** A → A (removes ~300 lines of shipped-but-dead Python and a misleading build warning)

#### K2 — `testConcurrentDuplicateEventsAreHandledCorrectly` is flaky under load
- **Where:** [PressAndHoldKeyMonitorTests+DuplicateEvents.swift:141](Tests/PressAndHoldKeyMonitorTests+DuplicateEvents.swift:141)
- **What's wrong:** Failed once during a full `--parallel` run (`downCount` 2, expected 1) and passed **5/5** when run in isolation, then passed again in the next full run. `git diff` confirms nothing in this session touched `PressAndHoldKeyMonitor` or its tests. It fires 10 concurrent `processTransition(isKeyDownEvent:)` calls from `DispatchQueue.global()` and asserts the handler ran exactly once; under the load of ~2,890 tests across parallel processes the dedup race can lose.
- **Fix:** Decide first whether this is a *test* race or a real one in `processTransition`'s dedup guard — the assertion may be catching a genuine bug rather than being wrong. Do not loosen the assertion to make it green; that would hide the answer.
- **Effort:** S
- **Grade lift:** C → C (reliability of the suite, not of the app — but a flake that is ignored is a flake that hides a real failure later)

### Still open (4)

E1 (pinned hashes — needs disk), C3, C5, D4, plus the new K1 and K2.

---

## A — Architecture & Design — B−

The layering is sound and deliberate: `App` / `Views` / `ViewModels` / `Services`
/ `Stores` / `Managers` / `Models` / `Utilities`, with large types split across
focused extension files (`AppDelegate+Hotkeys`, `+Lifecycle`, `+Menu`, …) so no
file is unmanageable. Concurrency primitives are custom-built and correct —
`VenvSerializer` ([UvBootstrap.swift:32](Sources/Services/UvBootstrap.swift:32))
chains tasks to survive `await` points inside the critical section, which a
plain actor would not, and `DiskMutationSerializer`
([DiskMutationSerializer.swift:16](Sources/Utilities/DiskMutationSerializer.swift:16))
clears failed entries synchronously so a failure is never re-served. Six ADRs
document the load-bearing decisions.

What pulls it to B− is a structural defect rather than a stylistic one: the
ViewModel layer was built to own transcription orchestration, is tested, and is
never called. The live path is the untested copy in a View extension.

#### ~~A1~~ ✓ done 2026-08-24 — The tested orchestration layer is dead; the live one is a View extension
- **Where:** [RecordingViewModel.swift:183](Sources/ViewModels/RecordingViewModel.swift:183) (`startRecording`), [TranscriptionCoordinator.swift:60](Sources/ViewModels/TranscriptionCoordinator.swift:60) (`runTranscription`), against the live callers [ContentView.swift:78](Sources/Views/ContentView.swift:78), [ContentView+Lifecycle.swift:40](Sources/Views/ContentView+Lifecycle.swift:40) → [ContentView+Recording.swift:6](Sources/Views/ContentView+Recording.swift:6) and [:21](Sources/Views/ContentView+Recording.swift:21)
- **What's wrong:** `RecordingViewModel.startRecording(audioRecorder:permissionManager:)` and `TranscriptionCoordinator.runTranscription(...)` have **zero production callers** — the only references outside their own definitions are [RecordingViewModelCoverageTests.swift:89](Tests/RecordingViewModelCoverageTests.swift:89) and [TranscriptionCoordinatorCoverageTests.swift:243](Tests/TranscriptionCoordinatorCoverageTests.swift:243). The app actually runs `ContentView+Recording.startRecording()` and `stopAndProcess()`, which build their own `TranscriptionPipeline` inline at [:155](Sources/Views/ContentView+Recording.swift:155) instead of going through the coordinator. So the codebase carries two implementations of the same flow — including a duplicated `isLocalModelInvocationPlanned` at [RecordingViewModel.swift:205](Sources/ViewModels/RecordingViewModel.swift:205) and [ContentView+Recording.swift:287](Sources/Views/ContentView+Recording.swift:287) — and the tested one is the one nothing runs. `ContentView+Recording.swift` measures **0.0% coverage, 440 missed lines**. This is worse than an untested path: it is coverage that reads as reassurance while proving nothing about shipped behaviour.
- **Fix:** Finish the migration the code comments already describe (they cite "audit item A2/C1"). Move the bodies of `startRecording()`, `stopAndProcess()` and `transcribeExternalAudioFile(_:)` into `RecordingViewModel`, routing the pipeline call through `coordinator.runTranscription`. Reduce the `ContentView` extension methods to one-line delegations (`viewModel.startRecording(audioRecorder:permissionManager:)`). Delete the now-duplicate `runTranscriptionPipeline` and `isLocalModelInvocationPlanned` from the View. The existing coverage tests then exercise live code for the first time.
- **Effort:** M
- **Grade lift:** B− → B+ (removes the only place where live and dead implementations of a core flow coexist; also unblocks D1)

#### ~~A2~~ ✓ done 2026-08-24 — `KeychainService` is entirely dead code
- **Where:** [KeychainService.swift](Sources/Services/KeychainService.swift) (194 lines), injected-but-ignored at [SpeechToTextService.swift:41-42](Sources/Services/SpeechToTextService.swift:41), [SemanticCorrectionService.swift:42-43](Sources/Services/SemanticCorrectionService.swift:42), [ProviderSettingsState.swift:41-42](Sources/Stores/ProviderSettingsState.swift:41); tested by [KeychainServiceTests.swift](Tests/KeychainServiceTests.swift) (18 tests)
- **What's wrong:** All three call sites take a `keychainService` parameter and carry the identical comment "kept for API compatibility but no longer used". Nothing reads or writes a key — this fork removed the cloud providers (ADR 0005), so there are no API keys to store. That leaves 194 lines of `SecItem*` code and 18 tests exercising a component the app never invokes, measured at **0.6% coverage**. Dead code in a security-sensitive area is the kind that gets accidentally revived.
- **Fix:** Delete `KeychainService.swift`, `KeychainServiceProtocol`, `Tests/KeychainServiceTests.swift`, and the three vestigial `keychainService:` init parameters. If a stub is wanted for a future provider, an empty commit message is cheaper than 194 live lines. Re-run `swiftlint analyze` afterwards and lower the `unused_declaration` BASELINE in [ci.yml](.github/workflows/ci.yml) to lock in the drop.
- **Effort:** S
- **Grade lift:** B− → B (removes the largest dead subsystem and 18 tests that inflate the count without covering anything)

#### ~~A3~~ ✓ done 2026-08-24 — `stopAndProcess` and `transcribeExternalAudioFile` are near-identical 45-line Task bodies
- **Where:** [ContentView+Recording.swift:21-85](Sources/Views/ContentView+Recording.swift:21) and [ContentView+Recording.swift:88-142](Sources/Views/ContentView+Recording.swift:88)
- **What's wrong:** The two Task bodies differ only in how the audio URL and duration are obtained (recorder vs. `AVAsset`). Everything after that — `runTranscriptionPipeline`, `try Task.checkCancellation()`, the `viewModel.finishTranscription` call with an identically-shaped `TranscriptionRunContext`, the `catch is CancellationError` block, and the `handleTranscriptionFailure` tail — is duplicated verbatim. Two copies of cancellation handling is exactly where the flows will silently diverge.
- **Fix:** Extract a single `private func runTranscriptionFlow(source: TranscriptionSource, resolveAudio: () async throws -> URL) async` holding the shared body, and have both entry points supply only their audio-resolution closure and initial `TranscriptionSource`. Do this as part of A1 so the result lands in the ViewModel, not the View.
- **Effort:** S
- **Grade lift:** B− → B (removes ~45 duplicated lines from the app's most important path)

#### ~~A4~~ ✓ done 2026-08-24 — Audio is validated twice per transcription
- **Where:** [TranscriptionPipeline.swift:59](Sources/Services/TranscriptionPipeline.swift:59) (step 1) then again inside [SpeechToTextService.swift:52](Sources/Services/SpeechToTextService.swift:52) (`validatedAudioURL`, called by `transcribeRaw`)
- **What's wrong:** `TranscriptionPipeline.transcribe` runs `AudioValidator.validateAudioFile(at:)`, then calls `speechService.transcribeRaw(...)`, which runs the same validation again on the same URL. `AudioValidator` opens and inspects the file, so this is duplicated I/O on every single transcription. Both layers document their validation as the authoritative one.
- **Fix:** Pick one owner. Preferred: keep validation in `TranscriptionPipeline` (it is the documented sole orchestrator) and add an internal `transcribeRawUnvalidated(...)` that the pipeline calls, leaving the public `transcribeRaw` validating for direct callers. Add a test asserting `AudioValidator` runs exactly once per pipeline invocation.
- **Effort:** S
- **Grade lift:** B− → B− (correctness-neutral cleanup; removes redundant file I/O from every transcription)

#### ~~A5~~ ✓ done 2026-08-25 — 17 singletons, concentrated in the least-tested layers
- **Where:** 17 `static let shared` across `Sources/` — notably [ModelManager.swift](Sources/Services/ModelManager.swift), [MLXModelManager.swift](Sources/Services/MLXModelManager.swift), [ParakeetService.swift](Sources/Services/ParakeetService.swift), [LocalWhisperService.swift](Sources/Services/LocalWhisperService.swift), [MLDaemonManager.swift](Sources/Managers/MLDaemonManager.swift), [PermissionManager.swift](Sources/Managers/PermissionManager.swift)
- **What's wrong:** Several are defensible for a menu-bar app (one WhisperKit cache, one daemon, one window coordinator). But the singleton-heavy layers are exactly the ones with the weakest coverage — Services 48.1%, Managers 44.8% — because a `shared` with no injection seam cannot be substituted in a test. `SpeechToTextService` already hard-codes `LocalWhisperService.shared` and `ParakeetService.shared` as `private let`s at [SpeechToTextService.swift:35-37](Sources/Services/SpeechToTextService.swift:35), so no test can reach it without the real services.
- **Fix:** Don't remove the singletons — add injection seams. Give `SpeechToTextService` `init(localWhisper:parakeet:)` defaulting to the `.shared` instances, matching the pattern `PasteManager` already uses at [PasteManager.swift:71](Sources/Managers/PasteManager.swift:71). Repeat for the two or three services with the most untested logic. This is the prerequisite for lifting Services coverage past ~50%.
- **Effort:** M
- **Grade lift:** B− → B (unblocks meaningful service-layer testing)

---

## B — Backend Quality — B

For a local-first desktop app the "backend" is the services and persistence
layer, and it is in good shape. SwiftData access is disciplined — predicates push
filtering into the store rather than fetching-then-filtering
([DataManager.swift:239](Sources/Stores/DataManager.swift:239),
[:285](Sources/Stores/DataManager.swift:285),
[:382](Sources/Stores/DataManager.swift:382)), `fetchLimit` is set where a bound
exists ([:253](Sources/Stores/DataManager.swift:253),
[:280](Sources/Stores/DataManager.swift:280),
[:312](Sources/Stores/DataManager.swift:312)). Error types are rich, exhaustive
and localized (`TranscriptionError` is 293 lines of real cases, not a string
bag). Domain errors are deliberately preserved rather than flattened —
`transcribeWithLocal` re-throws `SpeechToTextError` before wrapping
([SpeechToTextService.swift:112](Sources/Services/SpeechToTextService.swift:112)),
which is the kind of detail that usually gets lost.

Held to B by the empty integrity table (E1, which is as much a backend
correctness issue as a security one), the dead Keychain layer (A2), and one
unbounded query.

#### ~~B1~~ ✓ done 2026-08-24 — `fetchAllRecords()` loads the entire transcript history into memory
- **Where:** [DataManager.swift:196-210](Sources/Stores/DataManager.swift:196), reached via `fetchAllRecordsQuietly()` at [:415](Sources/Stores/DataManager.swift:415) from [UsageMetricsStore.swift:239](Sources/Stores/UsageMetricsStore.swift:239) and [DashboardHomeView.swift:235](Sources/Views/Dashboard/DashboardHomeView.swift:235)
- **What's wrong:** The descriptor sets a sort but no `fetchLimit`, so every record is materialised. Retention is user-configurable and one of the options is **forever** (README, "History & usage stats"), so this grows without bound. Opening the Dashboard on a long-lived install loads the full history to compute aggregates, and `UsageMetricsStore` does the same on rebuild. Every *other* fetch in this file correctly bounds itself, which makes this one look like an oversight rather than a decision.
- **Fix:** For `UsageMetricsStore`'s aggregate rebuild, page the fetch (`fetchLimit` + `fetchOffset` in a loop) and accumulate counters, so peak memory is one page rather than the whole table. For `DashboardHomeView`, it needs only summary figures — have it call a new `aggregateStats()` that fetches with a projection/limit rather than the full record set. Add a test inserting ~5,000 records and asserting the dashboard path does not fetch all of them.
- **Effort:** M
- **Grade lift:** B → B+ (removes the only unbounded query in the persistence layer)

#### ~~B2~~ ✓ done 2026-08-24 — Model-download stderr is classified by substring matching
- **Where:** [MLXModelManager+Downloads.swift:113-141](Sources/Services/MLXModelManager+Downloads.swift:113)
- **What's wrong:** Whether a line on the Python subprocess's stderr is an error or a progress update is decided by scanning for `"Fetching"`, `"Downloading"`, `"%"`, `"it/s"`, `"MB/s"`, `"GB/s"` and negating against `"no module"` / `"not found"`. `huggingface_hub`'s progress format is not a stable contract; when it changes, real download failures get silently reclassified as progress and the user sees a spinner that never resolves. The file is at **8.3% coverage (665 missed lines)**, so no test would catch the flip.
- **Fix:** Stop parsing stderr for control flow. The download script already runs under `-c` with the repo as `argv[1]` — have it emit structured single-line JSON on **stdout** (`{"event":"progress","pct":42}` / `{"event":"error","message":"…"}`) and treat stderr as diagnostics only. Decide success from the process exit code, which is already available at [:172](Sources/Services/MLXModelManager+Downloads.swift:172). Add unit tests feeding synthetic stdout lines.
- **Effort:** M
- **Grade lift:** B → B+ (replaces a fragile heuristic on the model-download path with an explicit protocol)

#### ~~B3~~ ✓ done 2026-08-24 — Three services take a `keychainService` parameter they ignore
- **Where:** [SpeechToTextService.swift:41](Sources/Services/SpeechToTextService.swift:41), [SemanticCorrectionService.swift:42](Sources/Services/SemanticCorrectionService.swift:42), [ProviderSettingsState.swift:41](Sources/Stores/ProviderSettingsState.swift:41)
- **What's wrong:** Each initializer accepts `keychainService: KeychainServiceProtocol = KeychainService.shared` and does nothing with it. The signature advertises a dependency and a seam that do not exist, and every construction of these services instantiates a Keychain wrapper for nothing.
- **Fix:** Delete the parameters as part of A2. If any call site passes one explicitly, remove the argument there too.
- **Effort:** S
- **Grade lift:** B → B (API honesty; folds into A2)

#### ~~B4~~ ✓ done 2026-08-25 — `SpeechToTextService.transcribe` and `transcribeRaw` are now the same function
- **Where:** [SpeechToTextService.swift:64](Sources/Services/SpeechToTextService.swift:64) and [:95](Sources/Services/SpeechToTextService.swift:95)
- **What's wrong:** Since the correction pass moved to `TranscriptionPipeline`, `transcribe(audioURL:provider:model:)` is a one-line forward to `transcribeRaw(audioURL:provider:model:)`. Both carry long doc comments explaining that they used to differ. Two public names for one behaviour invites a caller to assume `transcribe` still applies correction — which is precisely the bug the split was meant to prevent.
- **Fix:** Keep `transcribeRaw` as the single name. Mark `transcribe(audioURL:provider:model:)` `@available(*, deprecated, renamed: "transcribeRaw(audioURL:provider:model:)")`, migrate the remaining callers and the mock surface, then delete it. Leave the no-argument `transcribe(audioURL:)` convenience alone — it does something distinct (auto-selects a provider).
- **Effort:** S
- **Grade lift:** B → B (removes a name whose only remaining purpose is to be misread)

---

## C — Frontend Quality — C+

There is real craft in the view layer: a design system (`Sources/Design`,
`LayoutMetrics`), reduce-motion support with its own tests, a documented
`ScrollableContent` wrapper that exists because `ImageRenderer` cannot draw
`ScrollView` content (a subtle trap, caught and written down), and a snapshot
harness whose `assertSnapshot` fails any render that is >99.5% one colour so a
view that quietly stops drawing cannot pass by matching an equally blank
baseline. State management is mostly idiomatic — `@AppDefault`
([AppDefault.swift:17](Sources/Utilities/AppDefault.swift:17)) is a genuinely
good custom property wrapper that re-reads only its own keypath, so an unrelated
defaults write no longer re-renders every view holding one.

C+ rather than B− because of the size of the untested surface, several
oversized view files, and accessibility that stops about a third of the way in.

#### ~~C1~~ ✓ done 2026-08-24 (via A1) — Core recording orchestration lives in a View extension
- **Where:** [ContentView+Recording.swift](Sources/Views/ContentView+Recording.swift) (292 lines, **0.0% coverage**)
- **What's wrong:** Permission checks, recorder lifecycle, cancellation, `AVAsset` duration loading, pipeline invocation and error mapping all live in an extension on a SwiftUI `View`. `View` structs are re-created on every render and cannot be instantiated in a test without a rendering context, which is why this file is at zero. This is the same defect as A1 seen from the frontend side.
- **Fix:** Covered by A1 — move the bodies into `RecordingViewModel` and leave the View with delegations only.
- **Effort:** M
- **Grade lift:** C+ → B− (moves the app's most important logic out of the untestable layer)

#### ~~C2~~ ✓ done 2026-08-24 — Accessibility labels cover roughly a third of the view layer
- **Where:** 92 accessibility modifiers across **25 of 70** view files; entirely absent from e.g. [DashboardPermissionsView.swift](Sources/Views/Dashboard/DashboardPermissionsView.swift), [DashboardSettingsCards.swift](Sources/Views/Dashboard/DashboardSettingsCards.swift), [PermissionModals.swift](Sources/Views/Components/PermissionModals.swift)
- **What's wrong:** The gap falls on exactly the screens where it matters most: the permission-granting flow. A VoiceOver user who cannot complete the Accessibility/microphone prompts cannot use the app at all, and those modals are the least labelled. There is an existing `UnifiedModelRowAccessibilityTests`, so the pattern is established — it just was not carried through.
- **Fix:** Work through the permission and settings surfaces first (`PermissionModals`, `DashboardPermissionsView`, `DashboardSettingsCards`), adding `.accessibilityLabel` / `.accessibilityHint` to every control and `.accessibilityAddTraits(.isHeader)` to section headers. Then the Dashboard nav. Extend the existing accessibility test pattern to assert labels are non-empty on the permission views.
- **Effort:** M
- **Grade lift:** C+ → B− (makes the mandatory onboarding path usable with VoiceOver)

#### C3 — Six view files exceed 320 lines, several over the SwiftLint `type_body_length` intent
- **Where:** [WaveformContainer.swift](Sources/Views/Components/Waveform/WaveformContainer.swift) (563), [DashboardHomeView.swift](Sources/Views/Dashboard/DashboardHomeView.swift) (465), [DashboardView.swift](Sources/Views/Dashboard/DashboardView.swift) (455), [CategoryEditorSheet.swift](Sources/Views/Dashboard/CategoryEditorSheet.swift) (373), [CelebrationEffects.swift](Sources/Views/Components/Effects/CelebrationEffects.swift) (366), [StateTransitionEffects.swift](Sources/Views/Components/Effects/StateTransitionEffects.swift) (358)
- **What's wrong:** These pass lint (`file_length` warns at 600) but each holds several independent subviews in one `body` tree, which is why their coverage sits at 1–11% — there is no seam to render a piece in isolation. The codebase already knows the fix: `DashboardHome+Sections.swift` and `CategoryEditorSheet+Sections.swift` exist as extension splits. It just was not finished.
- **Fix:** Continue the established pattern — pull each logical section into its own `View` struct in a `+Sections` file, sized so it can be rendered standalone in a test. Prioritise `WaveformContainer` (largest, and the one with real layout logic) and `DashboardHomeView`.
- **Effort:** M
- **Grade lift:** C+ → B− (creates the seams C4 and D3 need)

#### ~~C4~~ ✓ done 2026-08-25 — Dashboard views are the largest untested block in the codebase
- **Where:** `Sources/Views/Dashboard/` — [DashboardHome+Sections.swift](Sources/Views/Dashboard/DashboardHome+Sections.swift) (0%, 886 missed), [DashboardCorrection+ModelPicker.swift](Sources/Views/Dashboard/DashboardCorrection+ModelPicker.swift) (0%, 857), [DashboardProviders+Parakeet.swift](Sources/Views/Dashboard/DashboardProviders+Parakeet.swift) (0%, 832), [DashboardProviders+Correction.swift](Sources/Views/Dashboard/DashboardProviders+Correction.swift) (0%, 829), [DashboardVisualsView.swift](Sources/Views/Dashboard/DashboardVisualsView.swift) (1.0%, 798), [DashboardRecordingView.swift](Sources/Views/Dashboard/DashboardRecordingView.swift) (1.1%, 742)
- **What's wrong:** ~5,000 missed lines in six files. These are not pure chrome — `DashboardProviders+Parakeet` spawns a verification subprocess at [:258](Sources/Views/Dashboard/DashboardProviders+Parakeet.swift:258) and `DashboardCorrection+Verify` does the same at [:97](Sources/Views/Dashboard/DashboardCorrection+Verify.swift:97). Process launching, argument construction and output parsing are ordinary testable logic that happens to be typed inside a view file.
- **Fix:** Don't chase view-body coverage. Extract the non-view logic instead: move the verify/spawn helpers into a `ModelVerificationService` in `Sources/Services/`, unit-test that directly, and leave the views calling it. That converts several hundred untestable lines into testable ones without fighting SwiftUI.
- **Effort:** M
- **Grade lift:** C+ → B− (turns the largest untestable block into ordinary service code)

#### C5 — `@State` holding shared singletons blurs ownership
- **Where:** [DashboardView.swift:158](Sources/Views/Dashboard/DashboardView.swift:158) (`@State private var metricsStore = UsageMetricsStore.shared`), and similar across the 114 `@State` declarations in `Sources/Views`
- **What's wrong:** `@State` declares *view-owned* value state. Assigning a process-wide singleton to it works under `@Observable` but misstates ownership: it reads as though the view creates and owns the store, and the initializer expression is evaluated on every `View` init even though the result is discarded after the first. With only 11 `@Binding` against 114 `@State`, shared state is mostly reached through singletons rather than passed, which is the same testability problem as A5 seen from the view side.
- **Fix:** For singletons, prefer `@Environment` injection (register once at the window root) or a plain `let` referencing `.shared`, reserving `@State` for state the view genuinely owns. Start with `DashboardView` and the metrics/category stores.
- **Effort:** S
- **Grade lift:** C+ → C+ (clarity and correct SwiftUI semantics; enables injecting a fake store in tests)

---

## D — Testing & Reliability — C

The *infrastructure* here is better than most projects ever build. Per-process
`UserDefaults` isolation keyed on pid ([AppDefaults.swift:38](Sources/Stores/AppDefaults.swift:38))
makes `--parallel` genuinely safe, and it detects the test runner intrinsically
via `NSClassFromString("XCTestCase")` so a harness that forgets the env var still
gets an isolated store — that fix came from 24 real cross-suite failures.
`IsolatedXCTestCase` offers a `strict` mode that fails on defaults leakage. The
nightly workflow runs the true end-to-end path (real 2.5 GB model, real Python,
real transcription) which was previously claimed-but-absent. The coverage gate
was rebuilt after being caught reading the wrong `awk` column and silently
passing for its whole life.

The *tests themselves* are the problem. 2,839 green tests coexist with 28.33%
coverage and a 0%-covered primary user flow, and a portion of the suite asserts
on variables the test just created.

#### ~~D1~~ ✓ done 2026-08-24 — The app's primary user flow has zero automated coverage `[both]`
- **Where:** [ContentView+Recording.swift](Sources/Views/ContentView+Recording.swift) — 0.0%, 440 missed lines, covering `startRecording`, `stopAndProcess`, `transcribeExternalAudioFile`, `retryLastTranscription`, `showLastAudioFile`
- **What's wrong:** Press hotkey → record → stop → transcribe → correct → paste is what the app *is*, and not one line of its orchestration is executed by the test suite. Cancellation handling, the "first model use" hint, the model-missing dashboard redirect, and the error tail are all unexercised. Meanwhile `RecordingViewModelCoverageTests` and `TranscriptionCoordinatorCoverageTests` pass — against the dead copies (A1).
- **Fix:** Do A1 first; the logic becomes reachable. Then add `RecordingViewModel` tests for: successful live-recording round trip with mocked speech + paste; recorder returning `nil` URL; empty-URL guard; `CancellationError` mid-pipeline clearing `isProcessing` and the hint flag; correction failure surfacing `correctionFailedMessage` while still pasting raw text; and the `.importedFile` path with a fixture audio file. Six tests would cover most of those 440 lines.
- **Effort:** M
- **Grade lift:** C → B− (the single largest and most important coverage gap)

#### ~~D2~~ ✓ done 2026-08-24 — Tautological tests: files named after code they never execute `[both]`
- **Where:** [Tests/Views/ContentViewRecordingTests.swift](Tests/Views/ContentViewRecordingTests.swift) (10 tests, 301 lines) and [Tests/LRUCacheTests.swift](Tests/LRUCacheTests.swift) (11 tests)
- **What's wrong:** These assert on locally-declared variables, not on production code. `testIsProcessingSetBeforeTaskCreation` ([:44](Tests/Views/ContentViewRecordingTests.swift:44)) declares `var isProcessing = false`, sets it to `true`, starts a `Task`, and asserts the captured value is `true` — it tests Swift closure capture. `testTranscriptionStartTimeSetWithIsProcessing` ([:66](Tests/Views/ContentViewRecordingTests.swift:66)) sets two locals, asserts they are set, clears them, asserts they are cleared — it tests assignment. `testLRUSortingByAccessTime` ([LRUCacheTests.swift:15](Tests/LRUCacheTests.swift:15)) builds its own dictionary and sorts it inline, testing `Dictionary.sorted`; its own comment concedes "We simulate the sorting logic used in the WhisperKitCache." This is why `ContentView+Recording.swift` is at 0% despite a test file bearing its name — the naming makes the gap invisible, and these tests would keep passing if the production files were deleted.
- **Fix:** Delete both files outright rather than repairing them — after A1/D1 the real behaviour is covered by real tests. For the LRU logic, add one test through `LocalWhisperService`'s public surface that loads N+1 models and asserts the least-recently-used one was evicted (observable via the cache's public state). Then grep the suite for the same shape — `grep -rn "// Simulate the" Tests/` returns 6 hits, each worth an individual check.
- **Effort:** S
- **Grade lift:** C → C+ (removes tests that actively misrepresent what is covered)

#### ~~D3~~ ✓ done 2026-08-25 — ~20 test files whose named subject is under 10% covered `[FE]`
- **Where:** cross-referencing test filenames against coverage: `MLXModelManagementViewTests` → subject 0.0% (585 missed), `DashboardPermissionsViewTests` → 0.0% (368), `WaveformViewTests` → 0.0% (336), `TranscriptionSearchBarTests` → 0.0% (80), `CelebrationEffectsTests` → 1.0% (601), `DashboardVisualsViewTests` → 1.0% (798), `DashboardRecordingViewTests` → 1.1% (742), `StateTransitionEffectsTests` → 1.5% (394), `MicrophoneVolumeManagerTests` → 6.4% (235), `AudioProcessorTests` → 7.4% (87)
- **What's wrong:** A reviewer scanning `Tests/` sees a test file per component and concludes the component is tested. The measurement says otherwise. The last two are the concerning ones — `MicrophoneVolumeManager` and `AudioProcessor` are not views, so there is no rendering excuse.
- **Fix:** Start with the two non-view cases: write real tests for `AudioProcessor` (deterministic input buffers → asserted output) and `MicrophoneVolumeManager` (mock the device, assert volume-boost/restore transitions). For the view files, apply C4 — extract the logic and test that, then rename the remaining files to reflect what they actually assert (e.g. `…ViewConstantsTests`) so the naming stops overclaiming.
- **Effort:** M
- **Grade lift:** C → C+ (aligns the suite's apparent coverage with its real coverage)

#### D4 — Snapshot suite is local-only, so 34 baselines are unenforced in CI `[FE]`
- **Where:** `Tests/__Snapshots__`, gated behind `SNAPSHOT_TESTS=1`; the deliberate no-snapshot-job rationale is in [ci.yml](.github/workflows/ci.yml)
- **What's wrong:** The reasoning for excluding them is sound and well-documented — a GitHub runner has no usable WindowServer and produced 19–100% pixel divergence on all 34 renders — so this is not a mistake. But the consequence stands: the only mechanism that verifies the view layer renders anything runs solely when a developer remembers to run it. Nothing in CI or in a pre-commit hook prompts for it, so a view regression ships silently until someone opts in.
- **Fix:** Don't put them in CI. Add a `make snapshot-check` target wrapping the documented invocation, reference it in the CONTRIBUTING pre-PR checklist, and have `scripts/lint.sh` (already run pre-PR) print a reminder when `Sources/Views/**` is modified in the working tree without a snapshot run. Cheap, and it converts "remember to" into a prompt.
- **Effort:** S
- **Grade lift:** C → C (does not raise coverage, but stops the one view-layer safety net from depending on memory)

#### ~~D5~~ ✓ done 2026-08-25 — Python has 1 of its 2 test files wired into CI `[BE]`
- **Where:** [ci.yml](.github/workflows/ci.yml) runs only `Tests/test_correction_sanitize.py`; [Tests/test_parakeet_transcribe.py](Tests/test_parakeet_transcribe.py) is excluded from the SwiftPM target and referenced by no workflow
- **What's wrong:** `Sources/ml/` is 870 lines of Python that performs the actual transcription and correction. One of its two test files runs. `test_parakeet_transcribe.py` covers `parakeet_transcribe_pcm.py` — the PCM entry point the app calls on every Parakeet transcription — and nothing executes it.
- **Fix:** Add it to the existing "Python unit tests" step in `ci.yml` alongside the sanitize tests. If it needs real MLX imports (unlike the sanitize tests, whose mlx imports are lazy), split the import-free assertions into a module that plain `python3` can run and leave the model-dependent parts to the nightly E2E job.
- **Effort:** S
- **Grade lift:** C → C+ (brings the second half of the Python surface under per-PR test)

---

## E — Security — B−

The fundamentals are handled well and, in places, better than typical. Every
`Process` invocation uses `executableURL` + an `arguments` array — there is no
`/bin/sh -c` anywhere, and hostile input is passed as `argv[1]` rather than
interpolated into a script body, with the reasoning written down at
[MLXModelManager+Downloads.swift:143-150](Sources/Services/MLXModelManager+Downloads.swift:143).
Subprocesses get a minimal environment allowlist (`MLDaemonManager.daemonEnvironment()`)
rather than the inherited environment, so HF tokens and proxy credentials are not
leaked downstream. The bundled `uv` binary is SHA-256 verified at runtime against
a build-time stamp ([UvBootstrap.swift:256-267](Sources/Services/UvBootstrap.swift:256)).
Error messages are redacted before display (there are tests for API-key, email
and file-path redaction). Hardened runtime, notarization, and a three-entitlement
minimum. CodeQL runs on both Swift and Python. Being local-only removes the
exfiltration surface entirely — there is not a single `URLSession` call in
`Sources/`.

B− because the one integrity control the project documents as a hard guarantee
is switched off, and the Python supply chain gets no advisories.

#### E1 — The pinned model-hash table is empty, so ADR 0006's hard-fail guarantee is inert
- **Where:** [DiskMutationSerializer.swift:96](Sources/Utilities/DiskMutationSerializer.swift:96) — `static let knownHashes: [String: String] = [:]`; documented as enforced in [docs/adr/0006-model-integrity.md](docs/adr/0006-model-integrity.md)
- **What's wrong:** ADR 0006 states that for app-shipped models "the file's SHA-256 is compared against the value baked into this build. A mismatch is a **hard fail** … There is no trust-on-first-use escape hatch." Because the table is empty, `knownHash(for:)` returns `nil` for *every* model, so `verify(at:modelIdentifier:)` ([:135](Sources/Utilities/DiskMutationSerializer.swift:135)) always takes the TOFU branch. A poisoned first download of a shipped model — the exact case the ADR says is covered — is silently trusted and its hash recorded as the reference. The source comment is candid about this (">>> ACTION REQUIRED <<<"), and populating the table honestly beats an ADR that overstates the control. This is the only `ACTION REQUIRED` marker in the entire codebase.
- **Fix:** Two parts, and do both. (1) Compute the real hashes: for each shipped model, download via a release build, then hash the representative file each caller passes — `config.json` via `ModelManager.representativeFileURL` for WhisperKit, `refs/main` via `MLXModelManager.integrityFileURL` for MLX/Parakeet — and paste the values into `knownHashes`. Add a test asserting the table is non-empty and that a deliberately corrupted fixture throws `.pinnedMismatch`. (2) Until (1) lands, amend ADR 0006 with a "Status: partially implemented" note so the document stops describing a control that does not run. Also action the ADR's own open item: surface the TOFU trust boundary in the UI when a user adds a custom repo.
- **Effort:** M
- **Grade lift:** B− → B+ (turns the project's flagship integrity control from documentation into enforcement)

#### ~~E2~~ ✓ done 2026-08-24 — Dependabot does not watch the Python dependency tree
- **Where:** [.github/dependabot.yml](.github/dependabot.yml) declares `swift` and `github-actions` only; [Sources/Resources/pyproject.toml](Sources/Resources/pyproject.toml) pins `mlx-lm`, `parakeet-mlx`, `librosa`, `numba`, `llvmlite`, `numpy`, `scipy`, `scikit-learn`
- **What's wrong:** `pyproject.toml` even records the consequence — "Dependabot does not manage this file" — but treats it as a note rather than a gap. These are large native-code scientific packages with real CVE history (`numpy`, `scipy`, `scikit-learn`, `librosa`), they are installed into a venv on the user's machine, and their code is executed by the app. With exclusive upper bounds and `uv sync --frozen`, `uv.lock` can never self-update, so a published advisory produces no signal anywhere in this repo.
- **Fix:** Add a `uv` ecosystem entry to `dependabot.yml` pointing at `/Sources/Resources` (Dependabot supports `uv` for `pyproject.toml`/`uv.lock`). If coverage proves incomplete, fall back to a scheduled workflow running `uv pip audit` (or `pip-audit` against the exported requirements) and failing on high-severity findings. The existing "lockfile is in sync" CI step is the natural place to hang it.
- **Effort:** S
- **Grade lift:** B− → B (closes the unmonitored half of the supply chain)

#### ~~E3~~ ✓ done 2026-08-25 — TOFU sidecar files sit unprotected beside the models they vouch for
- **Where:** [DiskMutationSerializer.swift:171](Sources/Utilities/DiskMutationSerializer.swift:171) — `modelURL.appendingPathExtension("audiowhisper-integrity")`
- **What's wrong:** The reference hash is a plain text file in the same directory as the model, under `~/.cache/huggingface`. Any local process that can rewrite the model can rewrite the sidecar next to it, so the check does not survive the threat it names in its own doc comment ("tampering by another local process"). The app is unsandboxed by design (ADR 0001), so there is no OS-level protection either. This is a real limitation of TOFU rather than a coding error — but the doc comment claims more than the design delivers.
- **Fix:** Move the sidecar hashes out of the model directory into app-controlled storage — a single plist/JSON under `~/Library/Application Support/AudioWhisper/` keyed by model path. That does not defeat a determined local attacker, but it stops the trivial rewrite-both-files case and puts the record somewhere the app owns. Then narrow the doc comment on [:59-66](Sources/Utilities/DiskMutationSerializer.swift:59) to claim only what it delivers: corruption and truncation detection, plus tamper detection once E1's pinned hashes are populated.
- **Effort:** S
- **Grade lift:** B− → B− (removes the trivial bypass and makes the documented claim accurate)

#### ~~E4~~ ✓ done 2026-08-25 — No `SECURITY.md` or disclosure path
- **Where:** repository root — absent
- **What's wrong:** The app is unsandboxed, launches subprocesses, downloads and executes model weights, and requests Accessibility permission (which grants synthetic-event injection). That profile warrants a stated way to report a vulnerability privately. There is currently no channel other than a public issue.
- **Fix:** Add `SECURITY.md` with a contact and expected response window, and enable GitHub private vulnerability reporting on `jtn0123/AudioWhisper`. Reference the trust boundaries already documented in ADRs 0001, 0002 and 0006 so a reporter knows what is in scope.
- **Effort:** S
- **Grade lift:** B− → B− (process gap, not a code vulnerability, but the right thing for this threat profile)

---

## F — Dependencies & Tech Currency — B+

This is managed with real deliberation. Only two direct Swift dependencies, both
current, and both recently moved for stated reasons: `KeyboardShortcuts` 3.0.1
after retesting the belief that 3.x required Swift 6 language mode (it does not),
and `argmax-oss-swift` 1.0.0 after discovering the old `.upToNextMinor(from:
"0.15.0")` pin had silently skipped 0.16 through 1.0. `Package.resolved` is
committed. `uv.lock` is committed *and* verified against `pyproject.toml` in CI
with `uv lock --check`, because `uv sync --frozen` does not itself detect drift —
a subtle failure mode, correctly identified. The Python pins use exclusive upper
bounds with a four-step bump checklist naming the exact API surface to re-verify,
written because those libraries break it across minors.

B+ rather than A− only because of E2's missing advisory coverage and one
documentation inaccuracy.

#### ~~F1~~ ✓ done 2026-08-24 — Add Python to Dependabot
- **Where:** [.github/dependabot.yml](.github/dependabot.yml)
- **What's wrong:** Same gap as E2, counted here as currency rather than security: with exclusive upper bounds and a frozen lock, the Python dependencies cannot move at all without a human editing `pyproject.toml`, and nothing tells anyone when they should. `mlx-lm` is pinned `>=0.31, <0.32` — a single minor's window on a fast-moving library.
- **Fix:** As E2. Even if the PRs are usually closed unmerged, they provide the "a new minor exists" signal that the current setup cannot generate.
- **Effort:** S
- **Grade lift:** B+ → A− (the only structural hole in an otherwise well-run dependency story)

#### ~~F2~~ ✓ done 2026-08-24 — `CLAUDE.md` lists three dependencies that do not exist
- **Where:** [CLAUDE.md:125-128](CLAUDE.md:125)
- **What's wrong:** "Key Dependencies" names **Alamofire** ("HTTP requests and model downloads"), **HotKey** ("Global keyboard shortcuts") and **KeychainAccess** ("Secure API key storage"). None appears in `Package.swift`, and `grep -rn "import Alamofire\|import HotKey\|import KeychainAccess" Sources Tests` returns **zero** hits for all three. Hotkeys come from `KeyboardShortcuts`; the Keychain wrapper is hand-rolled on the `Security` framework and is itself dead (A2); and there is no HTTP client at all — `URLSession` appears **0 times** in `Sources/`, because downloads go through WhisperKit and `huggingface_hub`. This is the file that configures Claude Code for this repo, so the error propagates into future automated work.
- **Fix:** Rewrite the section to the actual set: SwiftUI + AppKit, AVFoundation, Accelerate, SwiftData, `Security` (direct), `KeyboardShortcuts`, and `WhisperKit` via `argmax-oss-swift` — plus the uv-managed Python runtime. Add a line noting there is no Swift HTTP client by design.
- **Effort:** S
- **Grade lift:** B+ → B+ (documentation accuracy; also fixes H1)

#### ~~F3~~ ✓ done 2026-08-25 — Orphaned root-level Python script referencing removed providers
- **Where:** [test_semantic_correction.py](test_semantic_correction.py) at the repository root
- **What's wrong:** Its docstring says it "Tests all semantic correction modes: Off, Local (MLX), and Cloud (OpenAI/Gemini)" — the cloud providers were removed from this fork (ADR 0005). It is referenced by no workflow, no script, and no `Package.swift` entry, and it sits at the root rather than in `Tests/`. It is stale documentation masquerading as a test.
- **Fix:** Delete it. If any of its manual-check value is worth keeping, fold the local-MLX portion into `Tests/test_correction_sanitize.py`, which CI already runs.
- **Effort:** S
- **Grade lift:** B+ → B+ (removes a file that describes a product this fork is not)

---

## G — Performance & Scalability — B

Sampled the audio path, the hashing path, and the data layer. The engineering is
mostly right and in places notably good: FFT uses Accelerate/vDSP throughout with
a pre-computed Hann window and a single `fftSetup` allocated once
([FFTProcessor.swift:73-87](Sources/Services/Audio/FFTProcessor.swift:73));
the level-meter publish is throttled to 60 Hz while buffer accumulation and file
writes are deliberately *not* throttled so no audio frames are dropped
([AudioEngineRecorder.swift:399-401](Sources/Services/Audio/AudioEngineRecorder.swift:399));
SHA-256 streams in 64 KB chunks so gigabyte models do not blow up memory
([DiskMutationSerializer.swift:107-119](Sources/Utilities/DiskMutationSerializer.swift:107));
the menu bar reads a cached three-record snapshot instead of loading history
([AppDelegate+Menu.swift:88](Sources/App/AppDelegate+Menu.swift:88), a fix from a
prior audit). Waveform data is downsampled to ~128 points before crossing to the
main actor.

#### ~~G1~~ ✓ done 2026-08-24 — Two heap allocations per audio callback, under a lock, unthrottled
- **Where:** [AudioEngineRecorder.swift:385-396](Sources/Services/Audio/AudioEngineRecorder.swift:385)
- **What's wrong:** On every input-tap callback — roughly 94/sec at a 512-frame buffer and 48 kHz, and deliberately *outside* the 60 Hz publish gate — the code runs `sampleBuffer = Array(sampleBuffer.suffix(sampleBufferSize))` and then `let currentBuffer = sampleBuffer`, both while holding `sampleBufferLock`. That is two ~8 KB allocations plus a full copy of 2,048 `Float`s per callback, on the realtime audio thread, inside a lock the main actor also contends for. Allocation on the audio thread is the classic source of dropouts under memory pressure; the comment calling `suffix` "efficient" describes the API, not the allocation.
- **Fix:** Replace the array-plus-suffix with a fixed-capacity ring buffer: pre-allocate `[Float](repeating: 0, count: sampleBufferSize)` once, maintain a write index, and overwrite in place — no allocation in steady state. Take the snapshot copy only when `shouldPublish` is true (it is only consumed on that branch), which moves the one remaining copy from ~94/sec to 60/sec and shrinks the locked region. `AudioEngineRecorderTests` already exists to pin the behaviour.
- **Effort:** M
- **Grade lift:** B → B+ (removes all steady-state allocation from the realtime audio path)

#### ~~G2~~ ✓ done 2026-08-24 — Whole-history load on the dashboard path
- **Where:** [DataManager.swift:196-210](Sources/Stores/DataManager.swift:196) via `fetchAllRecordsQuietly()` → [UsageMetricsStore.swift:239](Sources/Stores/UsageMetricsStore.swift:239), [DashboardHomeView.swift:235](Sources/Views/Dashboard/DashboardHomeView.swift:235)
- **What's wrong:** Same root cause as B1, stated as a scaling concern: with the "forever" retention option, memory and dashboard-open latency grow linearly with lifetime transcript count, and both the metrics rebuild and the dashboard home take the hit.
- **Fix:** As B1 — page the aggregate computation and give the dashboard a bounded summary query.
- **Effort:** M
- **Grade lift:** B → B+ (removes the only unbounded-growth path in the app)

#### ~~G3~~ ✓ done 2026-08-24 — Duplicate `AudioValidator` pass per transcription
- **Where:** [TranscriptionPipeline.swift:59](Sources/Services/TranscriptionPipeline.swift:59) and [SpeechToTextService.swift:52](Sources/Services/SpeechToTextService.swift:52)
- **What's wrong:** Same as A4, measured as cost: `AudioValidator.validateAudioFile(at:)` opens and inspects the audio file, and it runs twice on the same URL for every transcription — once in the pipeline, once inside `transcribeRaw`.
- **Fix:** As A4.
- **Effort:** S
- **Grade lift:** B → B (small, certain saving on every transcription)

---

## H — Documentation & Onboarding — B−

Where this repo's documentation is fresh, it is among the best I have seen in a
codebase this size. Comments explain *why*, and specifically which failure
motivated the code: the CI coverage gate records that it was reading `$(NF-1)` —
missed branches, not line coverage — and had therefore never enforced anything;
the SwiftLint pin records that the same tree reports 144 findings on 0.63.2 and
46 on 0.65.0; the `print()` gate records that its loop ran in a subshell so
`exit 1` never propagated and it silently passed on every run; `run-tests.sh`
records that an EXIT-trap cleanup leaked 4,335 plists because it raced `cfprefsd`.
Six ADRs cover the load-bearing decisions. The README is accurate about features
and unusually honest about the fork's divergence from upstream — I verified all
seven advertised feature areas are actually wired in code.

B− because the two files a new contributor opens first are materially wrong, and
two ADRs describe a product that has moved on.

#### ~~H1~~ ✓ done 2026-08-24 — `CLAUDE.md` misstates the dependency set
- **Where:** [CLAUDE.md:125-128](CLAUDE.md:125)
- **What's wrong:** As F2 — Alamofire, HotKey and KeychainAccess are all listed and none exists. Because this file is loaded as instructions for automated work in this repo, a wrong dependency list actively misdirects.
- **Fix:** As F2. While there, fix two smaller drifts in the same file: the menu item is titled "Transcribe a File…" not "Transcribe Audio File...", and the `Sources/Managers/` description still says "`HotKeyManager.swift` - Global keyboard shortcuts via HotKey library".
- **Effort:** S
- **Grade lift:** B− → B (the highest-traffic doc in the repo becomes trustworthy)

#### ~~H2~~ ✓ done 2026-08-24 — `CONTRIBUTING.md` gives setup instructions that do not work
- **Where:** [CONTRIBUTING.md:20](CONTRIBUTING.md:20), [:28](CONTRIBUTING.md:28), [:43](CONTRIBUTING.md:43), [:84](CONTRIBUTING.md:84)
- **What's wrong:** Four separate errors on the onboarding path. (1) Line 20 says "**Xcode 15.0+** - For Swift development (optional, can use CLI tools)" — wrong twice over: the README correctly states Xcode 26.0+ is required because `KeyboardShortcuts` 3.x declares `swift-tools-version: 6.2`, and Command Line Tools alone **cannot** build this project, because the asset catalog needs `actool`. I hit exactly this during the audit: a bare `swift test` on a CLT-selected machine dies with `Failed to decode version info for '/usr/bin/actool'`. (2) Line 43 lists "Internet connection (for API-based transcription)" — this fork is local-only (ADR 0005), and there is no HTTP client in the Swift sources at all. (3) Line 28 still clones `https://github.com/yourusername/AudioWhisper.git`. (4) Line 84 offers `swift test --filter SettingsViewTests`, and no `SettingsViewTests` class exists.
- **Fix:** Correct all four. For (1), state Xcode 26.0+ as required, delete the "optional, can use CLI tools" clause, and point at `make build` / `make test` — those source `scripts/lib/xcode-env.sh`, which sets `DEVELOPER_DIR` per-process and recovers from a CLT-selected machine automatically. Note that bare `swift build`/`swift test` bypass that recovery (see I2). For (4), substitute a filter that exists, e.g. `DataManagerTests`.
- **Effort:** S
- **Grade lift:** B− → B (a new contributor's first three commands currently fail or mislead)

#### ~~H3~~ ✓ done 2026-08-25 — ADR 0006 documents an enforcement that does not run
- **Where:** [docs/adr/0006-model-integrity.md](docs/adr/0006-model-integrity.md) against [DiskMutationSerializer.swift:96](Sources/Utilities/DiskMutationSerializer.swift:96)
- **What's wrong:** The ADR's Decision section states shipped models get a hard fail on hash mismatch "including on the very first download. There is no trust-on-first-use escape hatch." With `knownHashes` empty, every model takes the TOFU path. An ADR that describes an unimplemented control is more dangerous than no ADR, because it ends reviewer inquiry.
- **Fix:** Bundled into E1 — either populate the table (preferred) or add an explicit "Status: Accepted, partially implemented" header plus a Consequences bullet naming the gap. Do not leave the current text standing.
- **Effort:** S
- **Grade lift:** B− → B (fixes the one ADR that overstates reality)

#### ~~H4~~ ✓ done 2026-08-25 — ADR 0001 references a library and a distribution channel this fork does not use
- **Where:** [docs/adr/0001-no-sandbox.md](docs/adr/0001-no-sandbox.md) — Context bullet 4 and the Decision/Consequences sections
- **What's wrong:** It justifies going unsandboxed partly via "Global hotkeys via the `HotKey` library use Carbon APIs" — the project uses `KeyboardShortcuts` now. It also states "Distribute via direct download and Homebrew cask" and "Notarization is mandatory for every release", but this fork publishes **no releases and no tap**: the README says so and the `Makefile` deliberately disables `update-brew-cask`/`publish-brew-cask` because they pushed into upstream's repository. The ADR's reasoning for not sandboxing remains valid — the surrounding facts have drifted.
- **Fix:** Amend in place with a dated "Superseded facts" note: swap `HotKey` for `KeyboardShortcuts`, and correct the distribution consequence to match `HOMEBREW.md` and the README. Keep the decision itself — it is still right.
- **Effort:** S
- **Grade lift:** B− → B− (keeps the ADR set trustworthy as a whole)

---

## I — Developer Experience & Tooling — A−

The standout category, and not by a small margin. Every gate in CI has been
caught failing open at some point and then repaired, with the diagnosis recorded
in the workflow itself: the coverage gate that parsed the wrong column and always
exited 0; the `print()` gate whose `exit 1` ran in a subshell; the SwiftLint
version that drifted through Homebrew and swung the analyzer baseline 3×; the
`unused_import` gate whose first real failure printed no filenames because the
GitHub reporter swallowed them. Gates are chosen intelligently — `unused_import`
is enforced at zero because the backlog was triaged by removing each import and
letting the *compiler* be the oracle, while `unused_declaration` is a ratchet
because much of what remains is structural. The coverage ratchet was
deliberately set from CI's own measured baseline (27%) rather than a local one,
with the reason recorded: dev boxes with cached models run a different test set
than a clean runner. `scripts/lib/xcode-env.sh` fixes the CLT trap per-process
without requiring `sudo`. Measured results back all of it: 0 warnings, 0
violations in 355 files, 2,839 green tests.

#### ~~I1~~ ✓ done 2026-08-24 — Every PR runs the full test suite twice and builds the project four times
- **Where:** [ci.yml](.github/workflows/ci.yml) `build-and-test` (`swift test --parallel`), [sonarcloud.yml:52](.github/workflows/sonarcloud.yml:52) (`swift test --no-parallel --enable-code-coverage`), plus `analyze` (`xcodebuild build-for-testing`) and `bundle-smoke-test` (`make build`)
- **What's wrong:** `ci.yml` contains a careful note explaining that running the suite twice "bought nothing and doubled this job", and removed the sequential run — measuring 53.50% parallel against 53.54% sequential, a 30-line difference out of 92,525 that is ordinary variance. But `sonarcloud.yml` still performs exactly that second full run, and does it `--no-parallel`, the slower way, on every push and PR to master. Add the analyze job's `xcodebuild build-for-testing` and the smoke test's `make build` and each PR pays for four full builds and two full test runs across three macOS runners. The `analyze` job alone has a 45-minute timeout.
- **Fix:** Apply the reasoning already written in `ci.yml`. Either (a) have `sonarcloud.yml` run `swift test --parallel --enable-code-coverage`, matching CI and roughly halving that job, or better (b) have `build-and-test` upload its `codecov` JSON / `coverage.lcov` as an artifact and have the Sonar job download and convert it, eliminating the second test run entirely. Option (b) also guarantees Sonar reports the same number the gate enforced.
- **Effort:** M
- **Grade lift:** A− → A (removes the single largest CI cost with no loss of signal)

#### ~~I2~~ ✓ done 2026-08-24 — Bare `swift build` / `swift test` fail on a CLT-selected machine, and the docs recommend them
- **Where:** [CLAUDE.md](CLAUDE.md) "Build Commands" presents `swift run`, `swift build -c release`, `swift test --filter …` and states "plain `swift test --parallel` is safe too"; the recovery lives only in [scripts/lib/xcode-env.sh](scripts/lib/xcode-env.sh), sourced by `run-tests.sh` and `lint.sh` but **not** by `build.sh`
- **What's wrong:** `xcode-select` pointing at `/Library/Developer/CommandLineTools` happens routinely and silently after a CLT update — `xcode-env.sh` documents exactly this. In that state every bare `swift build`/`swift test` dies with seven repetitions of `Failed to decode version info for '/usr/bin/actool'` and `error: fatalError`, which names neither the cause nor the fix. This is not hypothetical: it is what happened on this machine during this audit, and the documented commands are the ones that fail. CI sidesteps it with its own `xcode-select` step, so the trap is developer-only. `build.sh` not sourcing the helper is a second instance of the same gap.
- **Fix:** Source `xcode-env.sh` from `scripts/build.sh` too, so all three entry points self-heal. In `CLAUDE.md` and `CONTRIBUTING.md`, lead with `make build` / `make test` and add one line: bare `swift` commands work only when `xcode-select -p` points at a full Xcode, otherwise prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Optionally have the Makefile print the active toolchain on failure.
- **Effort:** S
- **Grade lift:** A− → A− (removes the most likely first-hour blocker for a new contributor or a fresh agent session)

#### ~~I3~~ ✓ done 2026-08-25 — No pre-commit hook, so all feedback waits on CI
- **Where:** no `.pre-commit-config.yaml`, `.githooks/`, or `core.hooksPath` configuration
- **What's wrong:** SwiftLint strict, the `print()`-outside-`#if DEBUG` gate and `uv lock --check` are all fast, deterministic, and locally runnable, but none runs before a push. A trailing `print()` or a lockfile drift costs a full CI round trip on macOS runners to discover — the `lint` job installs a pinned SwiftLint from GitHub releases before it can even start checking.
- **Fix:** Add a `.githooks/pre-commit` (opt-in via `git config core.hooksPath .githooks`, documented in CONTRIBUTING) that runs `scripts/lint.sh` on staged Swift files plus the `print()` grep, and `uv lock --check` when `Sources/Resources/pyproject.toml` is staged. Keep it under a couple of seconds so nobody disables it.
- **Effort:** S
- **Grade lift:** A− → A− (shifts three existing gates left; does not change what is enforced)

---

## Appendix — how to use this report

Item IDs are stable for the lifetime of this file. To execute specific items:

```bash
/grade-codebase A1 D1 E1
```

To re-grade one category after fixes:

```bash
/grade-codebase D
```

**Suggested sequencing.** A1 is the keystone — it unblocks D1 and C1, and it is
what turns three existing test files from decorative into meaningful. E1 is
independent and should be done in parallel because it is the only item where the
documentation currently overstates a security guarantee. A2 (delete
`KeychainService`) and D2 (delete the tautological tests) are both small, both
pure deletion, and both make every subsequent measurement more honest — do them
first if you want the fastest signal.
