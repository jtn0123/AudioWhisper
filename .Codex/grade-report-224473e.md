# Codebase Grade Report

**Project:** AudioWhisper Rebuild
**Audited:** 2026-10-07, after opening [PR #40](https://github.com/jtn0123/AudioWhisper/pull/40)
**Code:** `224473efc775d0547cac2a467379736baf354e98`, branch `rebuild/native-v2`
**Stack:** native SwiftUI/AppKit, AVFoundation/CoreAudio, SwiftData, WhisperKit, and offline MLX/Parakeet Python services.
**Scope:** the active rebuild and its shared services/tooling. Native acceptance targets macOS 26/27; app profiles remain removed. This is a development-app grade, not public-release acceptance.

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Architecture & Design | B+ | 1 |
| B | Backend Quality | B+ | 1 |
| C | Frontend Quality | B+ | 1 |
| D | Testing & Reliability | B | 2 |
| E | Security | B+ | 2 |
| F | Dependencies & Tech Currency | B+ | 1 |
| G | Performance & Scalability | B+ | 1 |
| H | Documentation & Onboarding | B | 1 |
| I | Developer Experience & Tooling | B+ | 1 |
| **Overall** | | **B+** | **11** |

**Top 5 highest-leverage fixes:** B1, C1, D2, G1, A1.

**Simply:** the rebuild is substantially more dependable and easier to use. Recording, cancellation and paste worked in the fresh VM run without renewed consent. It still has a reproduced file-import bookkeeping bug, a stale microphone-selection path, and some unfinished testing/maintenance work. It earns a solid B+, not an A.

### Ranked remaining work, in plain language

| Rank | ID | What it means | Evidence | Effort |
|------|----|---------------|----------|--------|
| 1 | B1 | Imported recordings lose their length, so history/stats are wrong. | Reproduced in the running app and saved database | M |
| 2 | C1 | Plugging in a microphone while Preferences is open can leave its list out of date. | Current source; no physical hotplug reproduction | S |
| 3 | D2 | Automated real-model checks do not cover all the models the app offers. | Current inference fixtures/workflow | M |
| 4 | G1 | A large history can keep the UI busy during cleanup or recalculation. | MainActor code path; no measured freeze | M |
| 5 | A1 | Old, unused app screens/controllers still compile beside the rebuild. | Current production target and entry point | L |
| 6 | H1 | Some agent instructions still describe the old app and unsafe replacement procedure. | Contradictory current documentation | S |
| 7 | D1 | Virtual tests cannot prove physical hold keys, unplugging or sleep recovery. | Explicit acceptance gaps; no observed failure | M |
| 8 | E2 | The release command can upload a development package without distribution checks. | Current Makefile/build flow; no release executed | M |
| 9 | F1 | Dependency alerts do not audit this branch's exact Python lock. | Workflow/default-branch scope | M |
| 10 | E1 | CI action code can change behind a moving version tag. | Current workflow references | S |
| 11 | I1 | Missing local lint/type tools return success even though they skipped the check. | Reproduced with a restricted PATH | S |

## Evidence and limits

- **Fresh local full suite:** `make test` exited 0, discovering 2,979 Swift cases. Optional real-engine, hardware and snapshot tests can skip; this is not a claim that every physical/model scenario ran. All 121 Python unit tests and 6 acceptance-tool tests passed. Strict mypy passed 11 sources, and CI-pinned SwiftLint 0.65.0 reported zero violations across 424 Swift files.
- **Exact-head hosted CI:** [run 37643160057](https://github.com/jtn0123/AudioWhisper/actions/runs/37643160057) passed lint, build/tests, full analyzer and universal packaged smoke. Sources-only coverage is **40.80%**, 15,038/36,862 lines across 189 files, against a 40% floor. Sonar was intentionally skipped for that branch push. The new PR checks are separate; see their live state on PR #40.
- **Changed-line coverage review:** the exact-head Swift coverage artifact intersects 4,406 changed executable Source lines, with 1,968 covered and 2,438 uncovered. Many uncovered lines are native view/window rendering; VM coverage is separate and does not alter this unit-coverage number. Critical session, cancellation, setup, delivery and transport behavior has dedicated regression coverage. These counts are not 2,438 distinct untested behaviors.
- **Fresh packaged macOS 26.6.2 acceptance:** ten shortcut/start/native Cancel cycles passed, followed by actual Stop/transcription and exactly one paste into disposable TextEdit. All five native pages were captured in light and dark, remained inside the guest's visible display, and exposed selected/focused navigation. The run began after restarting the prepared guest; existing microphone/Accessibility consent was retained, with no new prompts needed.
- **Binary identity:** host and guest SHA-256 are `58e531e1bc1e19dcadac4aa34af0330363897bcb34691dc85444b4f5f3e6b218`. Strict complete-bundle signatures passed. The installed package is source `a9a0fed`; `224473e` adds evidence/docs only, with unchanged production sources. Host 27.2 was checked read-only; the audit changed no host preferences, permissions or history.
- **Reproduced B1:** the public 2.67075-second WAV imported and produced the expected transcript, but its new SwiftData record had SQL `NULL` duration. Earlier live recording records had non-null duration. [Saved result](regrade-2026-10-07/import-duration.json).
- **Current native evidence:** [fresh audit acceptance](regrade-2026-10-07/README.md). The earlier same-source [visual/contrast evidence](opus-visuals-2026-10-07/README.md) and [fullscreen/shortcut/model-install/Library acceptance](ui-polish-2026-10-07/README.md) retain their exact build identities and limits; they were not all repeated here.
- Physical hold-key modifiers, microphone disconnect/input-change/sleep recovery and a complete VoiceOver walk-through remain unaccepted. These are evidence gaps, not newly asserted bugs. The prior coordinate-only missed Cancel click remains visible in its original evidence; the fresh run used enabled native controls and their actual bounds.
- This was a sampled security/dependency review, not an exhaustive transitive vulnerability certification. Developer signing and VM acceptance do not establish notarized public distribution readiness. No release or PR merge was performed.

---

## A — Architecture & Design — B+

The active app has one injectable session owner that captures configuration and fences delivery against stale sessions (`Sources/Rebuild/RebuildSession.swift:27-78,278-355`). Setup is separated from recording, and speech/correction use one pipeline (`Sources/Rebuild/RebuildSetupServices.swift:22-55`, `Sources/Services/TranscriptionPipeline.swift:62-104`). The remaining architectural drag is a second, superseded shell still compiled into the executable.

#### A1 — Retire the superseded recording shell
- **Where:** `Package.swift:23-30`, `Sources/App/AudioWhisperEntryPoint.swift:6-9`, `Sources/App/AppDelegate.swift:4`, `Sources/Views/ContentView.swift:39`, `Sources/ViewModels/RecordingViewModel.swift:40-92`.
- **What's wrong:** The entry launches `RebuildApp`, but the production target also includes the old app delegate, content view, recording model and coordinator. There are two implementations of workflow ownership after only one remains reachable from app launch.
- **Impact:** Moderate — maintainers can fix or test the old workflow without improving the app users run, and duplicate code adds build/review work.
- **Fix:** Inventory references from the rebuild, retain shared services and move reusable behavioral assertions to rebuild tests. Remove the unreachable shell and its shell-specific tests after that transfer.
- **Effort:** L.
- **Grade lift:** B+ → A−, by eliminating a concrete duplicate application architecture.

---

## B — Backend Quality — B+

RPC payloads are bounded and typed, writes are serialized off the actor, and cancellation/timeout reaps workers before audio ownership is released (`Sources/Managers/MLDaemonManager.swift:116-204`, `Sources/Managers/MLDaemonManager+Process.swift:249-290`). Cleanup failures retain original text, while a history-save failure is distinguished from successful copying (`Sources/Rebuild/RebuildSession.swift:301-345`). Fresh import acceptance confirms a remaining metadata defect.

#### B1 — Preserve imported audio duration through delivery
- **Where:** `Sources/Rebuild/RebuildSession.swift:265-275,81-94`, `Sources/Services/TranscriptionPipeline.swift:67-70`, `Sources/Services/Audio/AudioValidator.swift:123-126`, `Sources/Stores/UsageMetricsStore.swift:96-103`.
- **What's wrong:** Import sets `duration = nil`. Validation already computes file duration but the pipeline discards that metadata. Fresh native import of a 2.67075-second fixture saved a successful transcript with `duration: null`.
- **Impact:** Moderate — imported files have no length in history and add words/sessions without their audio time, skewing usage totals.
- **Fix:** Carry validated duration in the pipeline result and use it for imported-file persistence/accounting. Preserve the captured recorder duration for live sessions. Cover fixture import, saved duration, retry and usage totals.
- **Effort:** M.
- **Grade lift:** B+ → A−, by closing a demonstrated metadata gap across file transcription.

---

## C — Frontend Quality — B+

All five fresh light/dark native captures share coherent semantic styling, readable hierarchy and contained layout (`Sources/Rebuild/RebuildDesign.swift:8-135,203-215`). Record exposes shortcut/recovery controls; Models and Writing represent busy, installed, verified and failed states (`Sources/Rebuild/RebuildWorkspace.swift:248-271,369-399`, `RebuildModelsView.swift:231-248`, `RebuildWritingView.swift:119-167`). Named navigation, selected traits and keyboard focus are present; the remaining concrete Preferences issue is microphone-list refresh.

#### C1 — Refresh microphone choices while Preferences remains open
- **Where:** `Sources/Rebuild/RebuildPreferencesView.swift:43-52,115-120`.
- **What's wrong:** Microphones are enumerated only in the initial `.task`. App activation refreshes Accessibility alone, and there is no device-change observer. A newly connected input can remain absent; a saved input UID absent from the list has no unavailable row. This is source-confirmed, not a physical hotplug reproduction.
- **Impact:** Moderate — choosing or recovering a microphone is unclear when hardware changes while the page stays mounted.
- **Fix:** Refresh on mount, app activation, permission refresh and input connection/disconnection. Preserve the saved UID and show a disabled selected-input-unavailable row until it returns. Verify mounted-page grant/connect/disconnect transitions.
- **Effort:** S.
- **Grade lift:** B+ → A− potential, by repairing the remaining concrete Preferences state defect; full accessibility acceptance is still needed for an exemplary grade.

---

## D — Testing & Reliability — B

Tests cover pipe saturation, cancellation and audio ownership, frozen bootstrap failures, destination-safe paste, and real SwiftData invalidation (`Tests/DaemonTransportReliabilityTests.swift:44-84`, `Tests/UvBootstrapTests.swift:137-180`, `Tests/SmartPasteDestinationTests.swift:6-26`, `Tests/RebuildLibraryInvalidationTests.swift:55-87`). The fresh full suite and packaged VM recording/paste path pass, and CI fails on malformed analyzer/coverage input. Current physical acceptance and offered-model inference coverage remain incomplete; aggregate test count and 40.80% coverage do not close those gaps.

#### D1 — Complete physical recording acceptance [both]
- **Where:** `scripts/vm/README.md:3-6,122-126`, `Sources/Services/Audio/AudioEngineRecorder+Interruptions.swift:17,55,69`.
- **What's wrong:** Synthetic VM input does not establish physical left/right modifier behavior. The current binary has no completed physical microphone disconnect, input-change or sleep/recovery acceptance matrix. These are evidence gaps, not observed failures.
- **Impact:** Moderate — everyday keyboard/audio-device transitions can differ from the passing virtual recording path.
- **Fix:** Retain VM evidence and record a short macOS 26/27 physical matrix for hold/release/cancel, disconnect, input changes, sleep, recovery and correct destination paste, with exact binary identity. Do not add an older-OS matrix or reset host consent.
- **Effort:** M.
- **Grade lift:** B → B+ together with D2, by closing the important runtime evidence gaps.

#### D2 — Exercise offered models in real inference fixtures [BE]
- **Where:** `Tests/Integration/LocalEngineFixtureTests.swift:78-100`, `Tests/Integration/ParakeetEndToEndTests.swift:57-77`, `.github/workflows/nightly.yml:90-99`.
- **What's wrong:** The correction fixture uses the older Qwen3 4B exclusively. Parakeet uses the selected/default repository rather than explicit v2 and v3 cases. Earlier Qwen3.5/3.8 benchmarks and packaged smoke are valuable but are not current, repeatable fixture coverage for all offered configurations. Scheduled nightly success on `master` is not rebuild-head evidence.
- **Impact:** Moderate — model/cache selection tests can pass while a newly offered model fails to load or infer.
- **Fix:** Add opt-in fixtures for shipped Qwen3.5/Qwen3.8 and explicit Parakeet v2/v3, including a multilingual v3 sample, conservative correction assertions, warm reuse and switching. Run on a provisioned Apple Silicon machine and retain exact-head results.
- **Effort:** M.
- **Grade lift:** B → B+ together with D1, by validating models users can actually select.

---

## E — Security — B+

Bundled uv is checked before execution and rejects versions below the patched floor; runtime installation stays frozen (`Sources/Services/UvBootstrap.swift:82,125-128,186-195,216-224`). Model downloads are commit-pinned, loads explicitly resolve offline snapshots, paste checks destination/session identity, and bundled Python remains immutable (`Sources/Models/ModelPins.swift:28-38`, `Sources/ml/hub.py:36,48`, `Sources/Managers/PasteManager.swift:169-175`, `Tests/BundledPythonImmutabilityTests.swift:39-44`). No current leak, compromised action or unpatched advisory was demonstrated; CI action trust and the existing public-upload command need hardening.

#### E1 — Pin CI actions to immutable commits
- **Where:** `.github/workflows/ci.yml:38,63,171,562`, `.github/workflows/codeql.yml:32,59,64,67`, `.github/workflows/nightly.yml:31,42,103`.
- **What's wrong:** Workflows use mutable major-version tags, including the Sonar action receiving `SONAR_TOKEN`. Action code can change without a repository commit. This is a hardening gap, not evidence of compromise. [GitHub documents immutable action references](https://docs.github.com/en/actions/reference/security/secure-use).
- **Impact:** Moderate — external CI code can change outside this repository's review process.
- **Fix:** Replace action tags with verified full commit SHAs, retain release-version comments, and keep Dependabot's Actions update entry.
- **Effort:** S.
- **Grade lift:** B+ → A− potential for CI dependency trust, alongside the remaining distribution boundary.

#### E2 — Enforce distribution checks before public upload
- **Where:** `Makefile:82-90`, `scripts/build.sh:478-483,534-544`.
- **What's wrong:** `make release` builds without `--notarize` and then uploads the ZIP. A normal build can be ad-hoc or locally signed. Even the optional notarization path tolerates failed stapling. The command does not enforce a distributable artifact before upload; it was not executed in this audit.
- **Impact:** Moderate — using the existing release target can publish a development package that recipients cannot open through the expected distribution path.
- **Fix:** Require Developer ID signing, accepted notarization, successful stapling and Gatekeeper assessment before upload. Keep development preview packaging separate, and verify the release guard using disposable unsigned/rejected fixtures without publishing.
- **Effort:** M.
- **Grade lift:** B+ → A− potential, by closing an existing upload path that bypasses distribution verification.

---

## F — Dependencies & Tech Currency — B+

Swift packages are locked and current at the reviewed official releases: [KeyboardShortcuts 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts/releases/tag/3.1.0), [Argmax 1.1.0](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0), [mlx-lm 0.31.3](https://github.com/ml-explore/mlx-lm/releases/tag/v0.31.3) and bundled [uv 0.12.23](https://github.com/astral-sh/uv/releases/tag/0.12.23). Python 3.11 is [security-supported through October 2027](https://devguide.python.org/versions/). Current uv/fsspec pins contain the fixes for the reviewed [uv](https://github.com/astral-sh/uv/security/advisories/GHSA-4gg8-gxpx-9rph) and [fsspec](https://github.com/fsspec/filesystem_spec/security/advisories/GHSA-27vj-qcqg-25rc) advisories; exact branch-lock advisory coverage is still missing.

#### F1 — Audit the runtime lock on the branch being built
- **Where:** `.github/workflows/ci.yml:242-275`, `.github/dependabot.yml:26-29`, `Sources/Resources/uv.lock:1`.
- **What's wrong:** CI checks manifest/lock consistency but does not audit that exact lock against advisories. Dependabot alerts examine the default branch (`master`), whose lock differs from the rebuild. Its alerts therefore do not establish this branch's advisory state. [GitHub documents the alert scope](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-alerts).
- **Impact:** Moderate — a reproducible lock can still include a newly disclosed vulnerable version without a branch check catching it.
- **Fix:** Add a branch advisory check for the shipped frozen Python lock, preserving its exact package/version set. Fail on actionable findings; document applicability and expiry for any explicit exceptions.
- **Effort:** M.
- **Grade lift:** B+ → A−, by checking security evidence for the runtime artifact actually built.

Parakeet 0.5.3 is newer than locked 0.5.2, but its [overlap patch](https://github.com/senstella/parakeet-mlx/pull/59) describes corrected token timing/order with unchanged sentence text. AudioWhisper consumes result text. No current-output defect or mandatory upgrade is inferred from that patch alone.

---

## G — Performance & Scalability — B+

PCM conversion uses fixed buffers, Parakeet processes bounded overlapping windows, and Python retains one model per engine (`Sources/Services/RawPCMConverter.swift:7-65`, `Sources/ml/parakeet.py:57-101`, `Sources/ml/loader.py:30-84`). Export runs in a cancellable background model actor; recording visualization uses bounded storage and throttled publication (`Sources/Stores/HistoryExporter.swift:11-60`, `Sources/Services/Audio/AudioEngineRecorder.swift:285-321`). The remaining whole-history maintenance operations still run on the UI actor.

#### G1 — Move history maintenance off the UI actor
- **Where:** `Sources/Stores/DataManager.swift:114-115,302-327`, `Sources/Stores/DataManager+Fetching.swift:42-65`, `Sources/Stores/UsageMetricsStore.swift:229-233`, `Sources/Rebuild/RebuildPreferencesView.swift:66-71`.
- **What's wrong:** Retention fetches every expired record and deletes individually on `MainActor`. Usage recalculation bounds page memory but its fetch/accumulate loop has no suspension or cancellation point. No freeze or timing regression was measured here.
- **Impact:** Moderate — large saved libraries can keep the UI thread occupied during cleanup or recalculation.
- **Fix:** Use background `@ModelActor` maintenance, predicate batch deletion and cancellable bounded aggregation returning value snapshots. Publish history revision/metrics on `MainActor` after successful completion.
- **Effort:** M.
- **Grade lift:** B+ → A−, by extending the existing background-export design to remaining whole-library work.

---

## H — Documentation & Onboarding — B

README and CONTRIBUTING explain the separate signed rebuild, explicit setup, one cleanup policy, source tooling and macOS 26/27 QA (`README.md:15-105`, `CONTRIBUTING.md:7-42,66-89`). Evidence retains source/binary identity and distinguishes VM, hardware and release proof. The root agent instructions still contradict the new installation and architecture guidance, so a fresh contributor/agent can take the wrong path.

#### H1 — Reconcile agent instructions with the active rebuild
- **Where:** `CLAUDE.md:93-114,123-127,189`, `docs/rebuild.md:7`, `CONTRIBUTING.md:24-36,70-81`.
- **What's wrong:** CLAUDE still recommends killing every AudioWhisper process, deleting the original Applications bundle and copying over it, followed by re-adding Accessibility after rebuilds. It describes the superseded entry and removed CategoryStore, and says no Keychain use despite persistent local signing. The rebuild notes still describe the earlier rust/paper palette.
- **Impact:** Moderate — following these instructions can undo the intended isolated installation and repeat permission churn; architecture/style instructions direct work toward stale code.
- **Fix:** Make `make run`/the staged installer the documented development path, explain retained signing identity and actual permission-repair boundaries, and describe `RebuildApp`, shared services, removed profiles and the slate/teal theme. Preserve the explicit fork PR target and Xcode recovery guidance.
- **Effort:** S.
- **Grade lift:** B → B+, by making the instructions agree with the app and documented safe workflow.

---

## I — Developer Experience & Tooling — B+

Toolchain recovery, strict CI lint/typing, analyzer failure gates, tested coverage provenance and atomic installation give useful feedback and preserve local identity (`scripts/lib/xcode-env.sh`, `scripts/analyze-gate.py`, `scripts/coverage-artifact.py`, `scripts/install-rebuild.py`). Fresh tests and pinned lint run successfully. The local wrappers still return success when tools are absent, which weakens scripted/pre-commit validation.

#### I1 — Make skipped required local checks visible as failure
- **Where:** `scripts/typecheck.sh:13-15`, `scripts/lint.sh:22-24`, `.pre-commit-config.yaml:7-12`.
- **What's wrong:** Missing mypy or SwiftLint prints a skip message and exits 0. A fresh restricted-PATH reproduction confirms both wrappers return success without performing their check. CI installs its tools, so this is a local-feedback defect, not a demonstrated CI bypass.
- **Impact:** Moderate — a script or hook can treat an unperformed check as passed and defer the error until remote CI.
- **Fix:** Fail required local check commands with the exact pinned install guidance when tools are missing. If optional skipping is needed, make it an explicit separate option rather than the default success path.
- **Effort:** S.
- **Grade lift:** B+ → A− potential, by making automated local-check status truthful.

## Using this report

These IDs belong to the **224473e / 2026-10-07 codebase regrade**; they do not refer to older code or UI report IDs. The canonical `grade-report.md` is a copy, and the previous canonical report is retained in `baseline-pre-pr-2026-10-07/`. Ask for specific IDs or the top five to execute them. This audit did not bulk-fix its newly listed items.
