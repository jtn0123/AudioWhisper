# Codebase Grade Report

**Project:** AudioWhisper Rebuild
**Audited:** 2026-10-04
**Stack:** Native macOS SwiftUI/AppKit, SwiftData, AVFoundation, WhisperKit/Core ML, bundled uv/Python with Parakeet and MLX.
**Version:** `rebuild/native-v2`; audit checkout `2d3e058`, packaged source `f0cc89a40dd380668c432ec186826772f3cd2b03`. This version identifies the historical audit snapshot; subsequent selected fixes are tracked in the execution follow-up. Backend means local engines and services.
**Previous reports:** [2026-10-03 rebuild audit](baseline-2026-10-03-native-v2/grade-report.md); [original app baseline](baseline-f3adb17/grade-report.md).
**Execution follow-up (2026-10-04):** Selected ranks 1–9 and 14–17 are implemented; D3 remains partially verified. See [ranked fixes and native matrix](ranked-fixes-validation.md). Grades and original findings below describe the audit snapshot; current open counts exclude implemented items.

**Fix evidence:** [Recommended fixes and native validation](recommended-fixes-validation.md). Existing IDs are retained; completed issues are excluded from open-item counts. B3 is new.

## Summary

| ID | Category | Grade | Open items |
|----|----------|-------|------------|
| A | Architecture & Design | B+ | 0 |
| B | Backend Quality | B | 0 |
| C | Frontend Quality | B | 0 |
| D | Testing & Reliability | B− | 1 |
| E | Security | B | 1 |
| F | Dependencies & Tech Currency | B− | 1 |
| G | Performance & Scalability | B | 0 |
| H | Documentation & Onboarding | B | 2 |
| I | Developer Experience & Tooling | B | 0 |
| **Overall** | | **B** | **5** |

**Remaining work after selected fixes:** D3, E2, H2, F2, H1.

The rebuild improves from C+ to B because the confirmed setup, input, interruption, verification, retry and Library defects are now addressed with meaningful regression coverage. This is a solid local preview. Remaining work concerns the full production delivery test, native shortcut/paste/device acceptance, long-import memory, a pointer-lifetime defect and public distribution requirements. The grade is an evidence-based judgment, not a test-count average or a release certification.

### Evidence and limits

- Fresh native inspection covers Record, Models, Writing, Preferences and history-off Library. [Captures and provenance](ui-ux-audit/2026-10-04-regrade/README.md) accompany the [UI/UX report](ui-ux-grade-report.md).
- This regrade exercised actual installed Parakeet verification to **Model ready (offline)**, then recording start, navigation while recording and cancellation back to Ready. No renewed permission prompt appeared. No transcript was generated or saved by that cancel check; preferences were not changed.
- Earlier observations of the same packaged source include five start/cancel cycles, selected MacBook Pro Microphone capture, stop/transcription/nonempty clipboard delivery and cold quit/relaunch without another consent prompt. Strict/deep signature verification remained valid after inference; bundled Python caches remained absent. These are prior same-build observations, not all repeated during the regrade.
- Fresh [code CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37178898261) passed: 3,026 discovered Swift cases, 88 Python tests, typing of 11 Python source files, strict lint with zero violations and packaged smoke. Sources-only coverage is **37.88% (14,433/38,102 lines across 189 files)**. The 27% gate leaves substantial room for regression and should be ratcheted against measured CI results; count and aggregate coverage do not prove any particular workflow.
- Previous local full checks and three actual-engine fixtures passed for this source: Parakeet speech, Whisper cold/warm speech and actual load verification, and MLX writing inference. [Documentation-head CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37179132940) also passed. Tests/builds were not redundantly rerun for this documentation-only audit.
- Only one physical microphone is attached. Physical global shortcut/hold, Smart Paste, actual disconnection/sleep, two distinguishable inputs, VoiceOver, long-file memory and the full desktop/full-screen Spaces matrix remain unverified. Mounted-Library invalidation has real SwiftData/observation regression coverage; its native save-while-mounted scenario is still unperformed.
- A previously reported macOS-runner Whisper inference failure is historical; its current resolution was not established by this regrade. It is separate from the freshly verified green primary CI and local engine evidence.
- The universal preview is completely ad-hoc signed, not Developer ID signed/notarized. Same-build consent persistence is observed; rebuilding with another signing identity can require new consent. The security review samples boundaries and the named vendor advisories; it does not claim an exhaustive transitive vulnerability audit.

---

## A — Architecture & Design — B+

The launched assembly has one observable session owner (`Sources/Rebuild/RebuildApp.swift:60-100`, `Sources/Rebuild/RebuildSession.swift:36-77`). Typed interruption events carry capture identity, and stale/duplicate events cannot take over another job (`RebuildSession.swift:151-193`, `Sources/Services/Audio/AudioEngineRecorder+Interruptions.swift:53-86`). Retry now shares admission rules and checks captured model identity (`RebuildSession.swift:132-143,347-365`). Compiled legacy UI remains acknowledged regression-test debt (`docs/rebuild.md:9`); no speculative architectural rewrite is recommended.

#### ~~A1~~ ✓ done 2026-10-03 — Connect recorder interruptions to the session

Typed, recorder-scoped events now reconcile phase, overlay and temporary-audio ownership. Graceful, failed, duplicate and stale-event regressions protect the bridge. Actual hardware interruption testing remains D3. [Original finding](baseline-2026-10-03-native-v2/grade-report.md).

#### ~~A2~~ ✓ done 2026-10-03 — Gate retry against maintenance and readiness

Retry/import share setup and maintenance gates; retry validates its captured engine/model, retains audio when blocked and presents a reason. Failing-before/passing-after coverage exists in `Tests/RebuildSessionTests.swift:300-390`.

---

## B — Backend Quality — B

Selected device routing is applied before format/tap setup and read back (`Sources/Services/Audio/AudioInputRouting.swift:23-64`, `AudioEngineRecorder.swift:364-369`); input boost and restoration use the captured device (`AudioEngineRecorder.swift:431-451`). Load verdicts persist by model/asset identity (`Sources/Rebuild/RebuildSession.swift:368-424`, `RebuildModelVerification.swift:15-25`), and Whisper verification actually loads the model (`Sources/Services/LocalWhisperService.swift:225-230`). Validation/correction fallback and serialized bounded RPC are retained (`TranscriptionPipeline.swift:55-97`, `Sources/Managers/MLDaemonManager.swift:126-204`). A confirmed unsafe-pointer lifetime violation in the Parakeet decoder remains, without a reproduced crash.

#### ~~B1~~ ✓ done 2026-10-03 — Route the selected microphone

Selected UID routing, unavailable-input errors and device-specific boost/restoration are implemented and tested. Prior same-build native capture from explicitly selected MacBook Pro Microphone passed; a two-source comparison remains unperformed.

#### ~~B2~~ ✓ done 2026-10-03 — Make readiness consume verification outcomes

Failed load verdicts block capture/import across refresh and relaunch until successful repair or changed assets invalidate them. Failure, repair, stale-result, changed-asset and thrown-error regressions are in `Tests/RebuildModelVerificationTests.swift:52-132`; fresh native Parakeet verification succeeded.

#### ~~B3~~ ✓ done 2026-10-04 — Keep decoder writes inside the buffer's unsafe-access scope

**Completed:** Unsafe decoder writes are scoped inside the access closure; streaming conversion retains this contract. PCM parity/error/cancellation checks pass. [Validation](ranked-fixes-validation.md). Original finding preserved below.

- **Where:** `Sources/Services/ParakeetService.swift:212-221`.
- **What's wrong:** `AudioBuffer.mData` escapes `withUnsafeMutableBytes`, then `ExtAudioFileRead` writes through it after the closure has returned. Swift guarantees this pointer only within that closure; this is a source-confirmed contract violation, not an observed crash. [Apple API contract](https://developer.apple.com/documentation/swift/array/withunsafemutablebytes%28_%3A%29).
- **Impact:** Moderate — audio decoding relies on storage validity outside its guaranteed lifetime.
- **Fix:** Construct AudioBuffer/AudioBufferList and call ExtAudioFileRead inside the unsafe-access closure. Handle returned status and append samples afterward; verify existing actual-speech conversion/output parity.
- **Effort:** S.
- **Grade lift:** B → B+, by removing unsafe lifetime handling from production audio preparation.

---

## C — Frontend Quality — B

Purpose-specific native views share theme, observable state and recovery controls (`Sources/Rebuild/RebuildWorkspace.swift:4-12,93-114`). Record, Voice Models, menu and import controls now consume common titles, enabled states and blocked reasons (`RebuildSession.swift:325-365`, `RebuildModelsView.swift:98-100`, `RebuildStatusController.swift:34-40`). Mounted Library reloads from an observed store revision and rejects stale fetches (`RebuildLibraryView.swift:75-81,107-123`). Fresh native Ready, Verifying, Listening and Cancel states support the improved grade; accessibility and shortcut polish remain addressable in the separate UI report.

#### ~~C1~~ ✓ done 2026-10-03 — Match action labels and availability to session state

State-matrix regressions cover capture, processing, install and maintenance; picker/drop admission is gated. Fresh Voice Models shows disabled **Verifying…** during verification and **Finish recording** during capture, then returns to Start after cancellation.

#### ~~C2~~ ✓ done 2026-10-03 — Refresh a mounted Library after delivery

Successful save/deletion/retention increments an observed revision; disabled/failed saves and no-op retention do not. An isolated real SwiftData/session/observation regression protects invalidation (`Tests/RebuildLibraryInvalidationTests.swift:27-95`).

---

## D — Testing & Reliability — B−

Coordinator tests now exercise real injected permission/setup transitions rather than assigning readiness (`Tests/RebuildSetupTests.swift:42-141`), while session/model tests protect retries, capture ownership and failed-model state (`Tests/RebuildSessionTests.swift:300-390`, `Tests/RebuildModelVerificationTests.swift:52-132`). Library coverage includes a real isolated SwiftData store and observation (`Tests/RebuildLibraryInvalidationTests.swift:27-50`). Green primary CI and previous engine/native checks are meaningful, but 37.88% aggregate source coverage and headless bundle smoke do not close the full live-delivery or macOS acceptance gaps. The 27% coverage floor should rise with measured results.

#### ~~D1~~ ✓ done 2026-10-03 — Cover the new setup coordinator [both]

Injectable permission, runtime/cache and installation services cover coalescing/denial, blocked recording commands, stale selection refresh, install failure/retry and maintenance. These tests simulate consent outcomes; they do not grant OS permissions.

#### ~~D2~~ ✓ done 2026-10-04 — Finish isolated integration coverage of launched delivery [both]

**Completed:** Live rebuild assembly accepts isolated delivery destinations; eight real-pipeline/pasteboard/SwiftData integration cases pass. [Validation](ranked-fixes-validation.md). Original finding preserved below.

- **Where:** `Sources/Rebuild/RebuildSession.swift:47-73,260-287`; `Tests/RebuildLibraryInvalidationTests.swift:40-45`; `Tests/RecordingDeliveryIntegrationTests.swift:37-52`.
- **What's wrong:** The Library regression uses a real store but replaces transcription and clipboard. The complete isolated pipeline/clipboard/history test still constructs legacy RecordingViewModel, while the live rebuild factory hardwires global destinations.
- **Impact:** Major — production delivery wiring can regress while component tests remain green.
- **Fix:** Inject pipeline, clipboard, history and usage destinations into live assembly. Exercise success, correction fallback, save failure, cancellation and owned retry-audio cleanup through that assembly with isolated store/pasteboard resources.
- **Effort:** M.
- **Grade lift:** B− → B, by verifying the launched delivery path rather than its pieces alone.

#### D3 — Complete the build-specific native acceptance matrix [FE]

**Partially verified:** The per-scenario matrix distinguishes final-bundle setup/long-import/cancellation evidence from predecessor shortcut/editor/search checks; UI code is unchanged in the final follow-up. Microphone and Accessibility consent, physical keys, full-screen/hardware and native mounted-save rows remain open as recorded in [the matrix](ranked-fixes-validation.md).

- **Where:** `.github/workflows/ci.yml:385-400`; `.Codex/recommended-fixes-validation.md:31-42`; `docs/rebuild.md:42`.
- **What's wrong:** Packaged diagnostics exit without GUI interaction. Physical shortcut/hold, Smart Paste, full-screen Spaces, actual disconnect/sleep and mounted-Library native save lack current build-specific acceptance evidence.
- **Impact:** Moderate — central macOS boundaries remain unproven. These are validation gaps, not reproduced OS defects.
- **Fix:** Extend observed checks into a per-build matrix, recording passed, failed and unperformed scenarios separately. Include cold consent/relaunch, click/menu/physical shortcut/hold, cancellation, import, destination paste, normal windows/recording overlay and hardware interruptions; automate practical portions.
- **Effort:** M.
- **Grade lift:** B− → B+ with D2, by validating the app's actual OS interaction boundaries.

---

## E — Security — B

Both uv vendor archives are checksum-pinned, the universal tool is signed and runtime checks enforce a minimum/integrity contract (`scripts/prepare-uv.sh:7-35`, `Sources/Services/UvBootstrap.swift:82,216-224`); dependency synchronization remains frozen (`UvBootstrap.swift:186-195`). Subprocess environments are allowlisted and speech-bearing stderr is private (`Sources/Managers/MLDaemonManager+Process.swift:79-86,154-173`), while bytecode suppression preserves signed resources. Bundled uv 0.12.23 exceeds all three reviewed advisory patch floors. Public release can still omit distribution trust checks, limiting this category.

#### ~~E1~~ ✓ done 2026-10-03 — Upgrade affected bundled uv

Bundled 0.12.23 and the runtime minimum 0.11.15 address the reviewed vendor advisories: [entry-point writes, patched 0.11.15](https://github.com/astral-sh/uv/security/advisories/GHSA-4gg8-gxpx-9rph), [uninstall deletion, patched 0.11.6](https://github.com/astral-sh/uv/security/advisories/GHSA-pjjw-68hj-v9mw), and [ZIP parsing, patched 0.9.6](https://github.com/astral-sh/uv/security/advisories/GHSA-pqhf-p39g-3x64). Vendor pages were refreshed during the regrade; bootstrap/bundle/engine checks passed after the upgrade.

#### E2 — Require distribution trust checks before public upload

- **Where:** `Makefile:77-84`; `scripts/build.sh:412-418,429-453`.
- **What's wrong:** make release invokes the preview-capable build without --notarize and can upload an ad-hoc artifact. Complete ad-hoc signing remains appropriate for this local preview.
- **Impact:** Moderate — public release permits skipping intended distribution validation.
- **Fix:** Require Developer ID signing, notarization, stapling and verification before upload; fail clearly if credentials are unavailable. Preserve local preview packaging as a separate path.
- **Effort:** M.
- **Grade lift:** B → B+, by making public distribution fail closed.

---

## F — Dependencies & Tech Currency — B−

Swift/Python locks and frozen runtime synchronization support reproducibility (`Package.resolved:4-27`, `Sources/Resources/uv.lock`). Weekly monitoring covers standard dependency ecosystems (`.github/dependabot.yml:3-29`), and the affected bundled installer was upgraded. Two vendor improvements directly relevant to shortcuts and large audio imports remain unapplied; the separately pinned installer lacks an advisory signal. A newer version alone is not treated as a reproduced app bug.

#### ~~F1~~ ✓ done 2026-10-04 — Update KeyboardShortcuts

**Completed:** KeyboardShortcuts 3.1.0 is locked. Native custom/cleared/disabled recording and matching Record hints pass. Physical/menu-open delivery stays in D3. [Validation](ranked-fixes-validation.md). Original finding preserved below.

- **Where:** `Package.resolved:13-18`; `Package.swift:16`; `Sources/Rebuild/RebuildPreferencesView.swift:38`.
- **What's wrong:** Locked 3.0.1 omits [vendor 3.1.0 fixes](https://github.com/sindresorhus/KeyboardShortcuts/releases/tag/3.1.0) for the recorder ignoring registered shortcuts and function-key delivery while menus are open. Vendor evidence is fresh; corresponding app failures were not reproduced.
- **Impact:** Moderate — maintained fixes concern the app's core recording controls.
- **Fix:** Update the lock; verify custom shortcut recording/display, disabled/cleared keys and menu-open physical delivery in the packaged app. Coordinate with UI I1 and native acceptance D3.
- **Effort:** S.
- **Grade lift:** B− → B with F2, by adopting relevant control fixes.

#### F2 — Monitor bundled-tool advisories

- **Where:** `.github/dependabot.yml:3-29`; `scripts/prepare-uv.sh:7-18`.
- **What's wrong:** Dependabot monitors Swift, actions and Python packages; the installer executable remains a separate shell-script pin outside those checks.
- **Impact:** Moderate — bundled-tool advisories lack an automated maintenance signal.
- **Fix:** Centralize tool version/checksum metadata and schedule vendor-advisory checks against it. Report required reviewed updates rather than executing unreviewed upgrades automatically.
- **Effort:** S.
- **Grade lift:** B− → B with F1, by protecting the installer update process.

#### ~~F3~~ ✓ done 2026-10-04 — Adopt incremental Argmax audio loading

**Completed:** Argmax 1.1.0 incremental loading is enabled. Exact short-speech parity and three-hour loader RSS/cancellation measurements pass. [Validation](ranked-fixes-validation.md). Original finding preserved below.

- **Where:** `Package.resolved:4-9`; `Sources/Services/LocalWhisperService.swift:190-192`.
- **What's wrong:** Locked SDK 1.0.0 uses whole-file loading. [Vendor 1.1.0](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0) provides bounded incremental loading; the current call cannot opt into it. No app OOM was reproduced.
- **Impact:** Moderate — long imports retain avoidable memory pressure.
- **Fix:** Upgrade, enable incremental loading, verify short-speech parity and measure representative long-file peak memory. Coordinate with G1 rather than treating both IDs as duplicate implementations.
- **Effort:** M.
- **Grade lift:** B− → B+ with F1/F2, by modernizing the production import path.

---

## G — Performance & Scalability — B

Python retains one engine cache at a time, and Whisper uses an LRU with memory-pressure handling (`Sources/ml/loader.py:30-84`, `Sources/Services/LocalWhisperService.swift:87-93,123,144-155`). Capture publications are throttled, Library uses 50-row paging and export streams results (`Sources/Services/Audio/AudioEngineRecorder.swift:295-312`, `Sources/Rebuild/RebuildLibraryView.swift:117-121,141-148`). Prior cold/warm fixture timing demonstrates reuse on this Mac, not a comprehensive latency benchmark. Whole-file preparation and avoidable waveform allocations remain concrete hotspots.

#### ~~G1~~ ✓ done 2026-10-04 — Stream Parakeet conversion with bounded memory

**Completed:** 4,096-frame conversion bounds Swift preparation and removes partial output on cancellation. A native 30-minute import exposed a 32 GB attention allocation; the follow-up reads/generates overlapping two-minute chunks and the same real fixture now succeeds. Separate loader and inference measurements are recorded. [Validation](ranked-fixes-validation.md). Original finding preserved below.

- **Where:** `Sources/Services/ParakeetService.swift:129-141,198-235`; `Sources/Services/Audio/AudioValidator.swift:24-28,112-126`.
- **What's wrong:** Decoding appends the complete PCM file into a Float array, then creates another complete Data buffer. Validation imposes no size/duration limit; the conversion loop does not check cancellation.
- **Impact:** Moderate — large imports consume memory proportional to the whole file and defer cancellation. No crash/OOM was reproduced.
- **Fix:** Stream PCM to the owned temporary file in bounded chunks, check cancellation and clean partial output. Verify short-file output parity and representative long-file peak RSS/cancellation. Pair with F3 for the Whisper path.
- **Effort:** M.
- **Grade lift:** B → B+ with G2, by bounding supported audio preparation.

#### ~~G2~~ ✓ done 2026-10-04 — Remove per-bin waveform slice allocations

**Completed:** RMS uses the original sample buffer. Output/remainder checks and the repeated-call benchmark pass. [Validation](ranked-fixes-validation.md). Original finding preserved below.

- **Where:** `Sources/Services/Audio/AudioEngineRecorder+Interruptions.swift:90-102`; `Sources/Services/Audio/AudioEngineRecorder.swift:303-312`.
- **What's wrong:** Each published waveform computes 128 RMS bins by allocating an Array for every slice, despite already-throttled publication.
- **Impact:** Minor — unnecessary allocations remain in a repeated capture path; audible glitches were not observed.
- **Fix:** Compute RMS over indices or buffer slices directly, preserve output parity and compare representative allocation/capture profiles.
- **Effort:** S.
- **Grade lift:** B → B+ with G1, by reducing recurring allocation work.

---

## H — Documentation & Onboarding — B

`docs/rebuild.md` documents preview isolation, identity and validation boundaries, and the recommended-fix record separates automated, actual-engine and native evidence. The current README contains useful product/setup information, but some directions still name legacy destinations (`README.md:76,105-118,160`). CONTRIBUTING mixes obsolete dependencies/toolchain advice with the new workflow (`CONTRIBUTING.md:20-24,40-60,84-100,302-305`). Network and model-integrity wording also promises more than the current implementation establishes.

#### H1 — Align user and contributor instructions with the launched rebuild

- **Where:** `README.md:76,105-118,157-160`; `CONTRIBUTING.md:20-24,40-60,84-100,302-305`.
- **What's wrong:** README routes correction settings to Models, references an unbound Space action/nonexistent Dashboard and mixes legacy labels. CONTRIBUTING retains Swift 5.9 guidance and removed Alamofire/HotKey/API-key-storage advice alongside the current Swift 6.2 setup.
- **Impact:** Moderate — users and contributors receive conflicting directions for the actual app.
- **Fix:** Rewrite destinations/shortcut behavior around the rebuild, document toolchain/environment and supported packaged development commands, and remove obsolete dependencies/secrets guidance. Check the steps against the running app.
- **Effort:** S.
- **Grade lift:** B → B+ with H2, by making setup and feature help consistent.

#### H2 — Match network and model-integrity claims to implementation

- **Where:** `README.md:123`; `CONTRIBUTING.md:54-57`; `docs/adr/0006-model-integrity.md:31,36-40`; `Sources/Services/UvBootstrap.swift:174-195`; model structural probes in `Sources/Services/LocalWhisperService.swift:96-101` and `Sources/Services/ParakeetService.swift:114-119`.
- **What's wrong:** Documentation says only model installation needs network, while first runtime setup also downloads Python/frozen packages. The model ADR promises later integrity checks that structural probes/asset identity alone do not establish cryptographically.
- **Impact:** Moderate — offline preparation and trust expectations exceed the actual contract.
- **Fix:** Explain runtime/package/model downloads and subsequent offline operation. Distinguish structural readiness, metadata asset identity, successful load verification and cryptographic integrity; narrow unsupported claims or implement the promised checks with documented tests.
- **Effort:** M.
- **Grade lift:** B → B+ with H1, by making privacy/readiness claims precise.

---

## I — Developer Experience & Tooling — B

Primary CI runs strict Swift/Python checks, coverage and packaged diagnostics (`.github/workflows/ci.yml:187-188,248-306,347-400`). Resource-complete packaging and identity checks address failures that a bare executable cannot reveal. Normal make run still performs universal release packaging (`Makefile:22-29`, `scripts/build.sh:110-113,161-203`), and Sonar independently reruns the suite (`.github/workflows/sonarcloud.yml:51-71`). These costs slow an otherwise useful verification loop.

#### ~~I1~~ ✓ done 2026-10-04 — Add incremental native development packaging

**Completed:** Resource-complete host debug packaging/signing passes twice (9.05 s, 6.05 s). Release packaging remains universal. [Validation](ranked-fixes-validation.md). Original finding preserved below.

- **Where:** `Makefile:22-29`; `scripts/build.sh:110-113,161-203`.
- **What's wrong:** Ordinary make run builds both release architectures and recreates the complete app bundle.
- **Impact:** Moderate — routine UI iteration repeatedly incurs distribution work.
- **Fix:** Add host-architecture debug packaging with complete resources/signing and stable rebuild identity; retain universal release checks. Document how the development path preserves resource lookup and permission behavior.
- **Effort:** M.
- **Grade lift:** B → B+ with I2, by shortening the normal iteration loop.

#### ~~I2~~ ✓ done 2026-10-04 — Reuse primary CI coverage in Sonar

**Completed:** Primary test jobs export coverage once; same-run Sonar verifies report provenance. Real reports and seven rejection/acceptance tests pass; the Sonar scan retains master/PR scope. [Validation](ranked-fixes-validation.md). Original finding preserved below.

- **Where:** `.github/workflows/ci.yml:105`; `.github/workflows/sonarcloud.yml:51-71`.
- **What's wrong:** Master pushes/PRs run the full Swift suite separately for Sonar rather than consuming primary CI's coverage output.
- **Impact:** Moderate — duplicate execution costs time and produces independent coverage evidence.
- **Fix:** Publish commit-bound coverage artifacts from primary CI and consume them in Sonar; reject absent or mismatched provenance instead of silently analyzing another commit's data.
- **Effort:** M.
- **Grade lift:** B → B+ with I1, by removing redundant execution.

Request code fixes by ID, for example **F1 D2 B3 G1 E2**. Use **UI** before IDs from the UI/UX report. This grading run changes reports/evidence only.
