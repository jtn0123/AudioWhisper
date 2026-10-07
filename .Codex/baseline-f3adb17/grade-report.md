# Codebase Grade Report

**Project:** AudioWhisper
**Audited:** 2026-10-03
**Stack:** Native macOS SwiftUI/AppKit app, SwiftData history, WhisperKit/CoreML, embedded Python/uv with Parakeet and MLX correction.
**Baseline:** `f3adb171169f0625cdd19d57ba80ce2ae62019ce` (`f3adb17`); this is a fresh baseline audit, not a regrade of the polishing branch. File line references describe that baseline.

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Architecture & Design | C+ | 2 |
| B | Backend Quality | C | 4 |
| C | Frontend Quality | C | 3 |
| D | Testing & Reliability | C+ | 4 |
| E | Security | C+ | 4 |
| F | Dependencies & Tech Currency | B | 2 |
| G | Performance & Scalability | C+ | 3 |
| H | Documentation & Onboarding | B− | 3 |
| I | Developer Experience & Tooling | B− | 4 |
| **Overall** | | **C** | **29** |

**Top 5 highest-leverage fixes:** C1, C2, A1, E1, B2.

The app has substantial functionality, useful service boundaries, and a large test suite, but essential recording/setup/cancellation/paste workflows contain concrete defects. A passing unit suite does not establish a reliable desktop experience. Overall C weights these workflow and safety problems more heavily than dependency hygiene or documentation.

### Evidence and limits

- Findings below are confirmed by baseline source inspection unless explicitly described as a runtime inference or an upstream dependency issue. Timing-sensitive impact and actual macOS focus/permission behavior require native verification.
- The user reports a false Ready state, at least five permission asks described as audio permissions after pressing the recording key, and a hidden missing-model error. Source paths explain how readiness and permission sequencing can produce this experience; the full physical journey was not independently reproduced during this audit.
- Native CUA app attachment timed out four times. An idle app sample does **not** establish that the app froze. There is no completed physical workflow proof or release-readiness claim.
- Baseline [CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37167335636), [CodeQL](https://github.com/jtn0123/AudioWhisper/actions/runs/37167335644), and [SonarCloud](https://github.com/jtn0123/AudioWhisper/actions/runs/37167335696) all completed successfully at the final refresh. Earlier app commit `6026cda` passed [primary CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37158321394) but failed its separately repeated Sonar test run. A later green run does not explain that intermittent stream-output failure.
- The [Oct 3 Nightly](https://github.com/jtn0123/AudioWhisper/actions/runs/37122087420), at `51cb703`, genuinely ran one real Parakeet model test and passed in 37 seconds. It was not an architecture skip and is not proof of the later desktop changes.
- Existing historical reports are preserved. This report records baseline findings; implementation progress below is not a regrade.

---

## A — Architecture & Design — C+

The app has explicit transcription service/protocol boundaries and a shared coordinator rather than duplicating the pipeline in views (`Sources/ViewModels/RecordingViewModel+Transcription.swift:220-294`). However, recording interaction and canceled-run cleanup do not have a common ownership/state rule (`Sources/ViewModels/RecordingViewModel.swift:202-223`, `Sources/Views/ContentView.swift:64-78`). Paste destinations also span global and view-model state without an explicit recording-session lifetime (`Sources/ViewModels/RecordingViewModel+Paste.swift:78-110`).

#### A1 — Give recording and transcription runs explicit state ownership
- **Where:** `Sources/ViewModels/RecordingViewModel.swift:202-223`, `Sources/Views/ContentView.swift:64-78`, `Sources/ViewModels/RecordingViewModel+Transcription.swift:220-269,308-314`.
- **What's wrong:** The waveform mouse action and start-recording method do not reject an already-processing run. A canceled task can later execute its cleanup against shared state after a newer run begins; there is no run identity guarding those writes.
- **Impact:** Major — users can start overlapping work or see the old run clear the new run's processing state. The source permits this interleaving; its actual frequency was not measured.
- **Fix:** Route mouse, menu, and key actions through the same state-aware recording command. Assign each processing run an identity and allow only the current run to publish results, errors, and cleanup. Reproduce busy-click and delayed-cancellation interleavings with controllable service doubles.
- **Effort:** M.
- **Grade lift:** C+ → B−, by making primary-flow transitions consistent and preventing stale task ownership.

#### A2 — Bind paste-target state to the current recording session
- **Where:** `Sources/ViewModels/RecordingViewModel+Paste.swift:24-46,78-110`, `Sources/ViewModels/RecordingViewModel.swift:202-223`.
- **What's wrong:** Paste/source resolution prefers persistent `WindowController.storedTargetApp` and cached view-model target/source state. These values are not consistently captured and retired as part of a particular recording run.
- **Impact:** Major — a later transcript can use a destination or category from an earlier interaction. Wrong-app paste impact is addressed separately in E1.
- **Fix:** Capture an explicit destination/source-app value when a recording command starts, carry it in that run's context, and clear ownership on cancellation/completion/new recording. Test two consecutive recordings initiated from different applications and delayed completion of the first.
- **Effort:** M.
- **Grade lift:** C+ → B−, by removing stale session state from a user-facing action.

---

## B — Backend Quality — C

Here backend means local transcription, subprocess, and model-management services; this app has no hosted API backend. Typed RPC envelopes, a dedicated verification service, and per-model download serialization are useful foundations (`Sources/Managers/MLDaemonManager.swift:131-168`, `Sources/Services/ModelManager.swift:98-106`). Current stream draining, concurrent writes, cancellation, and exceptional cleanup violate those boundaries in ways that can lose messages, delay cancellation, or leave downloads stuck.

#### ~~B1~~ ✓ done 2026-10-03 — Drain and frame verification output before returning its result
- **Where:** `Sources/Services/ModelVerificationService.swift:24-29,125-158`.
- **What's wrong:** Readability handlers consume arbitrary chunks as complete text/JSON lines; a split JSON message can be discarded. Waiting for process exit does not wait for both pipe handlers to reach EOF, so the final result can be read before the last stdout/stderr data is collected.
- **Impact:** Major — verification can lose useful failure details or success messages. The earlier Sonar failure in `testFailureFallsBackToStderr` is concrete intermittent evidence; a later successful run does not remove the race.
- **Fix:** Use independent stream readers with byte buffering and complete-line framing, await both EOFs after exit, and flush any final unterminated line before result construction. Test split UTF-8/JSON, burst output, and a short process that writes immediately before exit.
- **Effort:** M.
- **Grade lift:** C → C+, by making subprocess completion include complete output delivery.

#### B2 — Serialize complete daemon request frames
- **Where:** `Sources/Managers/MLDaemonManager.swift:170-180`.
- **What's wrong:** Each request creates a detached writer and writes JSON and its newline separately to the same pipe. Concurrent writers can interleave frames despite the manager's actor-isolated pending-request dictionary.
- **Impact:** Major — legitimate concurrent requests can arrive as malformed or combined JSON and lead to protocol errors/timeouts. The corruption risk is source-confirmed; no frequency is claimed.
- **Fix:** Add a dedicated serialized writer outside the response-handling actor, write each complete JSON-plus-newline frame as one operation, and fail affected pending requests on write failure. Verify concurrent requests with a real pipe-backed fake daemon and a deliberately blocked reader.
- **Effort:** M.
- **Grade lift:** C → C+, by preserving the RPC framing contract under concurrency.

#### B3 — Let canceled Parakeet callers return promptly
- **Where:** `Sources/Services/ParakeetService.swift:64-87`.
- **What's wrong:** A detached daemon task owns PCM cleanup, but the caller awaits its value with an empty cancellation handler. The comment claims the await throws on caller cancellation; awaiting an unstructured task's value does not itself provide that cancellation behavior.
- **Impact:** Major — cancellation can keep waiting for model inference or timeout, contributing to stale UI work and a stuck-looking recording flow.
- **Fix:** Race or bridge caller cancellation with the daemon result using an exactly-once completion mechanism. Return cancellation promptly while the detached request retains PCM ownership until its real completion; test delayed daemon responses and cancellation without early file deletion.
- **Effort:** M.
- **Grade lift:** C → C+, by honoring cancellation while preserving subprocess file ownership.

#### B4 — Clean download state when capacity lookup throws
- **Where:** `Sources/Services/ModelManager.swift:111-148`.
- **What's wrong:** The model is marked downloading before `getAvailableStorageSpace()` runs, but that throwing capacity call is outside the cleanup-protected download `do/catch`. Its error leaves the model in the downloading/preparing collections.
- **Impact:** Moderate — a disk-capacity lookup failure can leave a download stuck and block retry.
- **Fix:** Put all post-registration work inside one cleanup scope, or use a reliable deferred MainActor cleanup path. Inject a throwing capacity provider and verify that downloading/stage state is cleared and a second attempt can proceed.
- **Effort:** S.
- **Grade lift:** C → C+, by restoring retryability after an existing exceptional path.

---

## C — Frontend Quality — C

The dashboard has coherent sections and dedicated settings components, while window policy distinguishes normal windows from the recording overlay (`Sources/Views/Dashboard/DashboardView.swift:129-149`, `Sources/Managers/Windows/ActivationPolicyController.swift:57-88`). These strengths do not resolve the central setup experience: the menu declares Ready unconditionally, provider status does not validate the selected model, permission prompts are independently scheduled, and a failed model's Retry loses its target.

#### ~~C1~~ ✓ done 2026-10-03 — Show readiness for the selected engine and required setup
- **Where:** `Sources/Views/Components/MenuPopupViews.swift:80-92`, `Sources/Stores/ProviderSettingsState.swift:45-50`, `Sources/App/AppStatus.swift:84-104`.
- **What's wrong:** Menu text is hardcoded Ready. Local provider readiness means any Whisper model is downloaded, Parakeet readiness means only its Python environment is ready, and recording status has no selected-model readiness input. These checks can claim Ready with the selected model absent or microphone unavailable.
- **Impact:** Major — users start recording under a false promise and encounter a missing-model error after speaking, matching the user's report.
- **Fix:** Introduce one readiness model for the selected provider/model, microphone, supported architecture, runtime, and in-flight setup. Drive menu, dashboard, and recording commands from it. Show a single actionable setup checklist before recording and keep optional correction/Smart Paste separate from recording prerequisites.
- **Effort:** M.
- **Grade lift:** C → C+, by making readiness truthful and resolving blockers before users record.

#### ~~C2~~ ✓ done 2026-10-03 — Make permission requests single-flight and sequential
- **Where:** `Sources/Managers/PermissionManager.swift:87-91,94-135,157-184`, `Sources/Views/ContentView.swift:101-140`.
- **What's wrong:** The combined setup flow schedules Accessibility after 300 ms without waiting for the microphone result, denial schedules another recovery sheet, and refresh can overwrite Accessibility `.requesting`. The test path also fails to reserve `.requesting` before scheduling, allowing repeated calls to queue work.
- **Impact:** Major — repeated hotkey/view events can create overlapping or cascading audio/Accessibility prompts, consistent with the reported prompt storm.
- **Fix:** Reserve request state synchronously, coalesce repeat commands, preserve in-flight states on refresh, and use one modal owner. Continue to optional Accessibility only after the microphone result succeeds. Provide microphone-only setup and leave denial inline until an explicit recovery action.
- **Effort:** M.
- **Grade lift:** C → C+, by replacing competing permission prompts with one understandable setup flow.

#### ~~C3~~ ✓ done 2026-10-03 — Retain the failed Whisper download target for Retry
- **Where:** `Sources/Views/Dashboard/DashboardProviders+LocalWhisper.swift:61-71,225-237`.
- **What's wrong:** Retry finds its model in `downloadStartTime`, but the failure handler removes that entry. With no other active download, Retry simply clears the error; with another download, it can choose the wrong model.
- **Impact:** Moderate — the advertised recovery control does not retry the failed action.
- **Fix:** Store the failed model independently from in-progress timing data, clear it on success or an explicit new action, and have Retry invoke that exact model. Verify single-failure and overlapping-download cases.
- **Effort:** S.
- **Grade lift:** C → C+, by making a visible recovery action perform the promised work.

---

## D — Testing & Reliability — C+

The real Swift/Python contract tests and opt-in Parakeet transcription test are meaningful (`Tests/MLRPCContractTests.swift:14-22`, `Tests/Integration/ParakeetEndToEndTests.swift:51-94`). Several suites described as integration/full-flow instead insert records, invoke clipboard APIs, or post notifications manually (`Tests/Integration/TranscriptionFlowIntegrationTests.swift:81-173`, `Tests/Integration/SmartPasteIntegrationTests.swift:43-73,156-163`). Native startup/paste are disabled in test mode, all snapshots are local opt-in, and the current source-coverage floor trails measured CI by about eleven percentage points.

#### D1 — [FE] Verify the actual native recording journeys
- **Where:** `Tests/Managers/Windows/WindowBehaviorTests.swift:26-30,79-114,175-187`, `Tests/SnapshotTestCase.swift:44-51`, `Sources/App/AppDelegate+Lifecycle.swift:9-12`, `Sources/Managers/PasteManager.swift:191-195`.
- **What's wrong:** Window tests inject Space visibility and assert properties; they do not establish actual menu opening, placement, focus return, or paste delivery between applications. There is no complete automated native recording journey.
- **Impact:** Major — a large green suite can coexist with the visible desktop bugs reported by the user.
- **Fix:** Keep a reproducible release matrix for menu/key initiation, desktop/full-screen, dashboard open/closed/minimized, record/stop/cancel, and target-app focus/paste. Automate stable journeys with a native app harness and retain explicit manual evidence for Space transitions that cannot be reliably automated.
- **Effort:** L.
- **Grade lift:** C+ → B−, by testing the product behavior the user actually experiences.

#### D2 — [both] Replace simulated integration assertions with production flows
- **Where:** `Tests/Integration/TranscriptionFlowIntegrationTests.swift:81-173`, `Tests/Integration/SmartPasteIntegrationTests.swift:43-73,156-163`.
- **What's wrong:** The cancellation test performs no cancellation; correction tests manually save already corrected text. Clipboard and success-notification tests invoke platform APIs or post notifications themselves, so they keep passing if the corresponding production flow breaks.
- **Impact:** Major — misleading test names/counts obscure critical gaps.
- **Fix:** Drive the production recording view model/coordinator with controllable service boundaries. Assert cancellation stops publication, correction reaches storage/clipboard, raw text survives correction failure, and production code emits the paste result. Rename remaining storage/API tests accurately.
- **Effort:** M.
- **Grade lift:** C+ → B−, by turning purported flow coverage into genuine regression protection.

#### D3 — [BE] Add real WhisperKit and correction model checks
- **Where:** `Tests/LocalWhisperServiceTests.swift:58-59`, `Tests/Integration/ParakeetEndToEndTests.swift:26-94`, `.github/workflows/nightly.yml:83-92`, `Sources/Resources/pyproject.toml:29-36`.
- **What's wrong:** Nightly real-model coverage exercises one Parakeet model. There is no corresponding real WhisperKit transcription or MLX correction check; the dependency-upgrade checklist names only Parakeet E2E.
- **Impact:** Major — the other supported engine and optional correction can fail at load/inference despite mocked tests passing.
- **Fix:** Add opt-in/nightly speech-fixture checks for WhisperKit tiny/base and the recommended correction model. Assert recognizable transcript words, successful correction inference, and meaning preservation; require relevant checks before dependency upgrades.
- **Effort:** M.
- **Grade lift:** C+ → B−, by checking both engine families and the real correction boundary.

#### D4 — [both] Advance the source-coverage ratchet
- **Where:** `.github/workflows/ci.yml:142-156`, `scripts/coverage-gate.py:72-81`.
- **What's wrong:** The floor remains 27%, while completed app CI run 37158321394 reports 38.26% own-source coverage (12,584/32,895 lines across 165 files). About eleven percentage points of regression can pass the advertised ratchet.
- **Impact:** Moderate — substantial loss of existing coverage can go unnoticed by the gate.
- **Fix:** Measure several clean CI runs, raise the floor conservatively to the current runner baseline, and record the associated commit/runs. Improve meaningful critical-flow coverage rather than adding assertions merely for totals.
- **Effort:** S.
- **Grade lift:** C+ → C+ with a stronger gate; native/real-flow coverage remains the larger limitation.

---

## E — Security — C+

This fork runs transcription locally, uses explicit permissions, and pins model/runtime dependencies (`README.md:118-123`, `Sources/Services/UvBootstrap.swift:180-198`). However, native paste events are global and destination activation is not revalidated, uv integrity verification can be disabled by clean-build ordering, frozen installation silently retries live resolution, and successful recordings retain owned raw audio in temporary storage. These are source-confirmed safety/privacy boundaries; no exploitation or wrong-destination physical paste was demonstrated.

#### E1 — Paste only into the explicitly captured and verified destination
- **Where:** `Sources/ViewModels/RecordingViewModel+Paste.swift:78-122,153-190`, `Sources/Managers/PasteManager.swift:191-232`.
- **What's wrong:** If stored targets are unavailable, the code chooses the first eligible running application. Target activation is followed by global synthetic Command-V without verifying that this process is actually frontmost at dispatch time.
- **Impact:** Major — transcript text can land in an unintended app or context. The unsafe selection/event path is confirmed; actual misdelivery was not reproduced.
- **Fix:** Require the destination captured for the current user action, verify its process/frontmost state immediately before event dispatch, and fail to clipboard-only delivery if it disappears or activation fails. Inject destination/activation/event boundaries and test changed focus, terminated target, and failed activation.
- **Effort:** M.
- **Grade lift:** C+ → B−, by removing an unintended-destination path for potentially sensitive text.

#### E2 — Verify bundled uv before executing it and stamp its actual bytes
- **Where:** `scripts/build.sh:36-46,225-263`, `Sources/Services/UvBootstrap.swift:128-129,157-160,234-236`.
- **What's wrong:** Build metadata captures uv version/checksum before the clean-build download, leaving the first bundle with an empty checksum. Runtime verification then no-ops; discovery also executes uv for its version before verifying the bundled binary.
- **Impact:** Major — the intended integrity check can be absent on a fresh build and occurs after execution when present.
- **Fix:** Download/validate the expected uv artifact before metadata generation, stamp the exact bundled executable after it exists, and verify its bytes before version probing or execution. Fail release builds if required integrity metadata is missing; test clean-build ordering and tampered-binary rejection.
- **Effort:** M.
- **Grade lift:** C+ → B−, by making the existing integrity boundary real rather than best-effort.

#### E3 — Fail closed when frozen Python installation fails
- **Where:** `Sources/Services/UvBootstrap.swift:198-205`.
- **What's wrong:** Any failed `uv sync --frozen` retries unrestricted `uv sync`. An unrelated network/install error can therefore replace the shipped, reviewed dependency selection with live PyPI resolution.
- **Impact:** Major — users can execute a runtime different from the committed lockfile; logging the downgrade does not preserve the pin.
- **Fix:** Keep production installation frozen and surface an actionable install error. Repair corrupted project files from the bundle without resolving new versions, and test that frozen-sync failure never invokes live resolution.
- **Effort:** S.
- **Grade lift:** C+ → B−, by preserving deterministic dependency execution on failure.

#### E4 — Give owned recording audio a bounded retention lifetime
- **Where:** `Sources/Services/Audio/AudioEngineRecorder.swift:145-148,258-294`, `Sources/ViewModels/RecordingViewModel+Transcription.swift:77-78,117-118`, `Sources/ViewModels/RecordingViewModel.swift:189-192`.
- **What's wrong:** Successful stop returns the raw recording URL; cleanup is used for cancellation/unusable audio, while successful/replaced recordings are not consistently deleted through explicit ownership. Clearing/replacing a URL is not deleting its file.
- **Impact:** Moderate — sensitive raw audio can remain in temporary storage beyond the user-facing recording/history operation.
- **Fix:** Distinguish app-owned recordings from imported user files. Retain only the owned current retry file for a bounded lifetime and delete it when replaced, explicitly discarded, or aged out. Preserve any subprocess lease and never delete imported originals; verify each ownership transition.
- **Effort:** M.
- **Grade lift:** C+ → B−, by making raw-audio privacy match an explicit retention rule.

---

## F — Dependencies & Tech Currency — B

Swift and Python lockfiles are checked in, uv runtime installation is intended to be frozen, and Swift/Actions/uv all have weekly Dependabot coverage (`Package.resolved:2-29`, `Sources/Resources/uv.lock:1-15`, `.github/dependabot.yml:3-29`). The current GitHub Dependabot alert refresh returned 21 alerts, all fixed; this is not a claim that undisclosed vulnerabilities do not exist. The app misses released direct-dependency improvements relevant to menus/hotkeys and imported-file memory, while its recently updated Python bounds warrant deliberate compatibility review rather than indiscriminate upgrades.

#### F1 — Adopt the released KeyboardShortcuts menu/hotkey fixes
- **Where:** `Package.resolved:13-18`, `Package.swift:16`.
- **What's wrong:** The lock pins 3.0.1. Current 3.1.0 fixes laggy menu highlighting, function-key shortcuts not firing while a menu is open, and shortcut recorder handling of the currently registered shortcut. These are upstream-confirmed issues, not reproduced AudioWhisper failures. [Primary release notes](https://github.com/sindresorhus/KeyboardShortcuts/releases/tag/3.1.0).
- **Impact:** Moderate — the app misses concrete fixes in a dependency central to the reported interaction problems.
- **Fix:** Update the lock to 3.1.0, build both release architectures, run hotkey tests, and verify actual menu-open function-key shortcuts and shortcut reassignment.
- **Effort:** S.
- **Grade lift:** B → B+, by adopting relevant released fixes after compatibility verification.

#### F2 — Evaluate the newer WhisperKit incremental file loader
- **Where:** `Package.resolved:4-9`, `Package.swift:22`, `Sources/Services/LocalWhisperService.swift:38-49`.
- **What's wrong:** Argmax SDK is pinned to 1.0.0; 1.1.0 adds incremental audio-file loading. Upstream reports over 70% lower peak memory for three-hour audio; that is its benchmark, not a measured result in this app. [Primary release notes](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0).
- **Impact:** Moderate — long imported recordings miss a released memory improvement.
- **Fix:** Upgrade in isolation, verify API and universal-bundle compatibility, run a real WhisperKit fixture, and compare peak memory on the same representative file before/after.
- **Effort:** M.
- **Grade lift:** B → B+, subject to measured compatibility and performance.

Current maintainer releases [mlx-lm 0.32.0](https://pypi.org/project/mlx-lm/) and [parakeet-mlx 0.5.3](https://pypi.org/project/parakeet-mlx/) were published Oct 1. The repo pins 0.31.3/0.5.2 and deliberately bounds minors. A two-day version difference alone is not a defect.

---

## G — Performance & Scalability — C+

The project has useful lazy/offline model loading, native model caching, and memory-pressure handling (`Sources/ml/loader.py:29-66`, `Sources/Services/LocalWhisperService.swift:122-150`). However, Python caches retain every loaded model, the native pressure handler reads the configured mask rather than delivered events, and transcription/correction repeatedly perform runtime setup. These establish resource/latency risks; the audit did not measure a physical freeze or quantify user-facing latency from them.

#### G1 — Bound the Python daemon's loaded-model caches
- **Where:** `Sources/ml/loader.py:19-20,29-66`.
- **What's wrong:** Both caches retain every successfully loaded repository for the lifetime of the daemon, with no eviction or unload policy. Switching among transcription/correction models therefore accumulates heavyweight model objects.
- **Impact:** Moderate — model switching can progressively consume memory and increase pressure on the user's other apps.
- **Fix:** Implement a bounded cache or one active model per engine with explicit unload/release behavior. Add fake-loader tests for switching/eviction and measure daemon memory while switching real models before selecting the limit.
- **Effort:** M.
- **Grade lift:** C+ → B−, by bounding a present resource-retention path.

#### G2 — Handle delivered memory-pressure events
- **Where:** `Sources/Services/LocalWhisperService.swift:130-150`.
- **What's wrong:** The callback reads `source.mask`, which describes subscribed events (`warning` and `critical`), instead of `source.data`, which describes the delivered event. The critical branch is therefore selected even when the notification is only a warning.
- **Impact:** Moderate — warnings unnecessarily clear every cached model and can force avoidable reloads.
- **Fix:** Branch on the delivered event data and test warning versus critical handling through an injectable pressure-event seam. Confirm cache behavior under controlled pressure; do not infer a physical freeze from static inspection.
- **Effort:** S.
- **Grade lift:** C+ → B−, by making the existing pressure policy behave as intended.

#### G3 — Reuse verified Python runtime setup during transcription
- **Where:** `Sources/Services/SpeechToTextService.swift:154-162`, `Sources/Services/SemanticCorrectionService.swift:96-107`, `Sources/Services/UvBootstrap.swift:155-205`.
- **What's wrong:** Parakeet transcription and subsequent local correction each call the venv setup/sync path. Serialization prevents races but does not avoid repeated subprocess/filesystem work for an unchanged runtime.
- **Impact:** Moderate — repeated runtime checks add avoidable work to the core transcription path; the exact latency is not measured.
- **Fix:** Cache successful runtime preparation keyed by shipped project/lock/interpreter identity, invalidate on setup changes or relevant failures, and reuse it across transcription/correction. Measure warm-path process count and latency before/after.
- **Effort:** M.
- **Grade lift:** C+ → B−, by removing repeated preparation from the warm user journey.

---

## H — Documentation & Onboarding — B−

The README clearly distinguishes this fork from upstream, explains local transcription and permissions, and gives the current Xcode requirement (`README.md:9-13,25-54,118-123`). ADRs and test docs explain unusual architectural/verification constraints (`docs/adr/README.md:7-12`, `Tests/README.md:74-107`). Some current instructions still conflict with implemented Dock/storage behavior, effective toolchain requirements, and the actual dependency inventory.

#### H1 — Align first-run and storage instructions with current behavior
- **Where:** `README.md:29,91`, `Sources/Managers/Windows/ActivationPolicyController.swift:57-73`, `Sources/Services/WhisperKitStorage.swift:5-7`.
- **What's wrong:** README says there is no Dock icon, but the app becomes a regular Dock/Command-Tab app while normal windows are open. It describes all model storage under `~/.cache/huggingface/hub`, while WhisperKit uses `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml`.
- **Impact:** Moderate — users get inaccurate expectations and inspect the wrong directory when troubleshooting missing models.
- **Fix:** Explain window-dependent Dock behavior and list WhisperKit and MLX storage separately. Verify first-run instructions against the completed setup flow after polishing.
- **Effort:** S.
- **Grade lift:** B− → B, by making user-facing setup/troubleshooting accurate.

#### H2 — Remove contradictory development and test instructions
- **Where:** `CONTRIBUTING.md:20-24,40-46,60,84-100`, `Tests/README.md:3-9`.
- **What's wrong:** The guide correctly requires Xcode 26/Swift 6.2 tooling, later says Swift 5.9+, and alternates between preferring make and always using bare Swift commands. Test docs call make test the whole stock-checkout suite, while it runs only Swift and needs prior generated VersionInfo.
- **Impact:** Moderate — contributors follow conflicting commands or believe they ran checks that did not execute.
- **Fix:** State one effective toolchain floor and one supported workflow. Distinguish Swift-only from complete verification and document or eliminate generated-source bootstrap.
- **Effort:** S.
- **Grade lift:** B− → B, by making onboarding consistent and reproducible.

#### H3 — Correct dependency inventory and maintenance comments
- **Where:** `README.md:175-178`, `Package.swift:10-22`, `Sources/Resources/pyproject.toml:8-10`, `.github/dependabot.yml:26-29`.
- **What's wrong:** README lists ViewInspector, absent from the manifest/lock, and groups parakeet-mlx under MIT although its current maintainer metadata declares Apache-2.0. The Python manifest says Dependabot does not manage it even though a uv updater is configured. [Parakeet metadata](https://pypi.org/project/parakeet-mlx/).
- **Impact:** Minor — inventory and maintenance guidance are misleading.
- **Fix:** Derive the shipped/test dependency list from current manifests, use correct licenses, and describe deliberate compatibility review rather than absent dependency monitoring.
- **Effort:** S.
- **Grade lift:** B− → B, as part of a documentation correction pass.

---

## I — Developer Experience & Tooling — B−

CI enforces strict lint/analyzer checks, Python typing/tests, lock consistency, own-source coverage, and a universal bundle (`.github/workflows/ci.yml:111-156,186-187,220-305,343-367`). Local Xcode recovery and scratch-default isolation address real tooling friction (`scripts/run-tests.sh:28-40`). Generated source is not bootstrapped for local testing, there is no complete local verification entrypoint, and Sonar duplicates tests while accepting missing Swift coverage artifacts.

#### I1 — Generate required version code for clean local test checkouts
- **Where:** `.gitignore:127`, `Package.swift:32`, `scripts/run-tests.sh:102`, `scripts/build.sh:72-81`, `Sources/Services/UvBootstrap.swift:234`, `Sources/Views/Dashboard/DashboardPreferencesView.swift:199`.
- **What's wrong:** VersionInfo.swift is ignored/untracked and its template is excluded from compilation. Production references the type, while make test does not generate it. CI explicitly generates it, masking the clean-checkout gap.
- **Impact:** Major — the recommended local test command needs a prior release build to supply required source.
- **Fix:** Extract a deterministic version-generation helper for local build/test and CI, keeping release integrity stamping after bundled uv preparation. Verify make test in an isolated checkout with no generated VersionInfo; static inspection established this gap, not a fresh-build reproduction in this audit.
- **Effort:** S.
- **Grade lift:** B− → B, by making the local test entrypoint independently usable.

#### I2 — Provide one complete local verification command
- **Where:** `Makefile:38-44`, `scripts/run-tests.sh:102-105`, `.github/workflows/ci.yml:255-305`, `scripts/lint.sh:22-24`, `scripts/typecheck.sh:13-15`.
- **What's wrong:** make test runs only Swift. Python tests, typing, lint, and lock checks require separate commands; the lint/typecheck wrappers return success if their tools are missing. There is no single honest equivalent of the fast CI checks.
- **Impact:** Moderate — local passing verification can omit the shipped Python code and quality gates.
- **Fix:** Add make check for Swift tests, four Python suites, strict lint, typing, and lock consistency. Fail clearly for missing required tools in that entrypoint; retain explicit lightweight wrappers if useful.
- **Effort:** S.
- **Grade lift:** B− → B, by making complete local verification easy and explicit.

#### I3 — Fail Sonar coverage export when required artifacts are missing
- **Where:** `.github/workflows/sonarcloud.yml:78-85`.
- **What's wrong:** Missing profdata/test-binary input emits an empty coverage XML and exits successfully, unlike the primary coverage gate's fail-on-missing-input behavior.
- **Impact:** Moderate — broken artifact discovery becomes misleading coverage instead of a clear infrastructure failure.
- **Fix:** Fail with expected paths and diagnostic artifact information, select the current test-build inputs deterministically, and verify exported own-source entries before scanning.
- **Effort:** S.
- **Grade lift:** B− → B, by making missing measurement visible.

#### I4 — Reuse one verified test/coverage result for Sonar
- **Where:** `.github/workflows/ci.yml:88-107,278-305`, `.github/workflows/sonarcloud.yml:51-71,118-125`.
- **What's wrong:** Both workflows run the full Swift suite with coverage and the Python suites independently. The earlier app commit passed primary CI while its repeated Sonar test run failed, producing conflicting verification results as well as duplicate runner work.
- **Impact:** Moderate — developers wait for repeated verification and diagnose separate outcomes for the same commit.
- **Fix:** Consolidate into dependent jobs in one workflow, or publish commit-specific coverage artifacts from the verified run and consume them for Sonar. Preserve scanner failure visibility and meaningful required checks.
- **Effort:** M.
- **Grade lift:** B− → B+, together with the local entrypoint improvements.

---

## Initial polishing work

**Status: source fixes implemented and regression checks passing; native onboarding verification remains open.** These are baseline grades, not a regrade or release certification.

| Item | Result | Commit |
|------|--------|--------|
| C1 | Shared microphone + selected-engine/model readiness, a single Setup page, first-run/shortcut routing, inline installation errors, persistent installation state and an actual menu recording command. Refreshes coalesce and recheck changed Parakeet selections; microphone access refreshes on activation and before recording. | `71e0422`, `bb90d81` |
| C2 | One active presentation/request; request reserved synchronously; microphone callback precedes optional Accessibility; no timer-driven recovery cascade; Setup requests microphone only. | `13604a0` |
| C3 | Failed Whisper model retained separately from active downloads; Retry invokes that exact model. | `f52dd28` |
| B1 | Complete concurrent stdout/stderr drains and handler-before-launch termination; removes the observed cross-thread exit wait hang. | `8f45089` |
| A1 partial | Busy mouse/view-model recording actions are ignored; processing control disabled. Run identities and stale cancellation/result callbacks remain open. | `05b0597` |
| UI D1 partial | Record-control accessibility describes its action and full status; Whisper-row actions and native VoiceOver verification remain open. | `472d1fe` |
| H1 partial | First-run README instructions now explain the checklist, required microphone/model, normal windows and optional Smart Paste. Remaining storage/development documentation gaps remain open. | `528d36d` |

Validation evidence:

- Baseline PermissionManager behavior failed three baseline-compatible coordination regressions with seven assertions: stacking presentations, clearing in-flight Accessibility state, and competing recovery/optional prompts. The original behavior was temporarily restored only for this reproduction and then the fixed source restored.
- A streamed verification JSON message failed before the stream fix; the old fast-exit wait also hung during the 20-attempt stderr regression. All ten process tests now pass, including all 20 fast failures and the 300 ms hung-script timeout fixture.
- Removing the busy guard makes the production view-model regression start a microphone recording during processing (one call instead of zero); restoring it passes.
- 171 focused checks passed across permission orchestration, setup prerequisites, selection changes during an in-flight check, retry target, first-run routing, busy guard, status, provider badges, and window-controller logic.
- Full `make test` passed on the latest source with 2,946 discovered tests. Opt-in snapshot and headless native-interaction cases are not physical desktop proof.
- Strict SwiftLint passed with zero violations; Python strict typecheck passed for 11 source files.
- `make build` passed; `lipo -info` confirms both arm64 and x86_64 in the local `AudioWhisper.app` executable. The bundle contains source commit `bb90d81`; later commits change tests/audit artifacts only. It is a local development bundle, not a notarized release.
- Native attachment to the rebuilt bundle also timed out. The running app was not restarted, so the changed native permission/recording journey remains unverified.
- [Setup layout previews](ui-ux-audit/README.md) were generated and inspected in light/dark using ImageRenderer. This validates composition, not real macOS interactions.

The paragraph above records the first batch only. The subsequent [ten-item reliability pass](reliability-roadmap.md) implements A1, E1/A2, B2/B3/B4, G1/G2/G3, E2/E3, production delivery coverage and real local engine fixtures. It also completes shortcut/duration/model-control polish. Native workflow validation remains open. The roadmap records current evidence, measurements and limitations; these baseline grades are preserved until the physical workflow is verified.
