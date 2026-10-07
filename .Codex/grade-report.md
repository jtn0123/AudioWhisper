# Codebase Grade Report

**Project:** AudioWhisper Rebuild
**Audit baseline:** 2026-10-07, [post-PR b64f707 report](grade-report-b64f707.md).
**Execution update:** completed saved items D3, B1, C1, D2 and G1 on 2026-10-07. This is a scoped grade/ledger update, not another complete audit.
**Code:** production source/package `5c5a13d2271f555a0e6582f61b902dc617fc9d92`; final real-model fixture proof `3312fd35be5b83ee2c6345190dc5b168854f4a4c` changes tests only.
**Stack:** native SwiftUI/AppKit, AVFoundation/CoreAudio, SwiftData, WhisperKit, and offline MLX/Parakeet Python services.
**Scope:** active rebuild and shared services/tooling; native acceptance targets macOS 26/27, app profiles remain removed. Development-app grade, not public-release acceptance.

## Summary

| ID | Category | Grade | Remaining items |
|----|----------|-------|-----------------|
| A | Architecture & Design | B+ | 1 |
| B | Backend Quality | A− | 0 |
| C | Frontend Quality | A− | 0 |
| D | Testing & Reliability | B | 1 |
| E | Security | B+ | 2 |
| F | Dependencies & Tech Currency | B+ | 1 |
| G | Performance & Scalability | A− | 0 |
| H | Documentation & Onboarding | B | 1 |
| I | Developer Experience & Tooling | B+ | 1 |
| **Overall** | | **B+** | **7** |

**Simply:** imported files now keep their length, microphone choices refresh, and history maintenance runs away from the UI thread. Real tests exercise the offered models and actual rebuild controls. The prior coverage blocker is closed: official Sonar passes at **80.5%** against the unchanged **80%** requirement. Physical hardware and public-distribution acceptance still limit the grade.

**Next five:** A1, H1, D1, E2, F1.

### Ranked remaining work, in plain language

| Rank | ID | What it means | Evidence | Effort |
|------|----|---------------|----------|--------|
| 1 | A1 | Old, unused app screens/controllers still compile beside the rebuild. | Original production-target/entry-point audit | L |
| 2 | H1 | Some agent instructions still describe the old app and replacement procedure. | Original contradictory documentation | S |
| 3 | D1 | Virtual tests cannot prove physical hold keys, unplugging or sleep recovery. | Acceptance gaps; no newly observed failure | M |
| 4 | E2 | The release command can upload a development package without distribution checks. | Original Makefile/build-flow audit; no release executed | M |
| 5 | F1 | Dependency alerts do not audit this branch's exact Python lock. | Original workflow/default-branch scope | M |
| 6 | E1 | CI action code can change behind a moving version tag. | Original workflow audit | S |
| 7 | I1 | Missing local lint/type tools return success though they skipped the check. | Preserved restricted-PATH reproduction | S |

### Completed batch

| ID | What changed | Proof |
|----|--------------|-------|
| ~~D3~~ ✓ done 2026-10-07 | Behavioral rebuild UI/startup/menu/window fixtures; no weakened gates. | Sonar 80.5% and passing full suite |
| ~~B1~~ ✓ done 2026-10-07 | Import/retry duration reaches history and usage. | Native fixture saves 2.67075 seconds, exact usage increment |
| ~~C1~~ ✓ done 2026-10-07 | Device choices refresh and retain unavailable saved input. | Notification/permission transitions and actual Picker fixtures |
| ~~D2~~ ✓ done 2026-10-07 | Explicit offered-model real inference, warm reuse and switching. | Six actual inference tests pass together |
| ~~G1~~ ✓ done 2026-10-07 | Background, cancellable history maintenance and stale-value protection. | Real SwiftData aggregation, retention and cancellation tests |

## Evidence and limits

- [Batch evidence](batch-2026-10-07/README.md) retains exact source/binary identities, current screenshots, native import and recording/paste proof, actual inference results, and the failed combined-model run before fixture cleanup.
- Full local Swift suite exits 0, **3,047 discovered cases**; opt-in physical/model/snapshot tests can skip. Strict SwiftLint 0.65.0 finds zero violations across 445 Swift files. Overall application-source line coverage is **51.01%** (18,853/36,956), passing the unchanged 40% floor.
- [Official Sonar gate](batch-2026-10-07/sonar-status.json) at [verified source 5c5a13d](batch-2026-10-07/sonar-analysis.json): **80.5% new-code coverage**, A reliability/security/maintainability ratings, zero duplication and 100% reviewed hotspots. Local Swift-only 80.31% and hosted Swift-only 79.49% changed-line intersections are diagnostic estimates, not the official combined Sonar metric. No exclusions, gate reductions or existing-test skips were added.
- [5c5a13d PR CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37689278997) build/tests, lint and Sonar scan passed. Analyzer and packaged-smoke checks are still running at this ledger update; [latest PR state](https://github.com/jtn0123/AudioWhisper/pull/40/checks) is separate from completed local/native proof.
- macOS **26.6.2 VM**: ten actual shortcut/start/native Cancel cycles, Stop/transcription and exactly one Smart Paste into disposable TextEdit; all five pages captured in light/dark and contained at 870x620; import metadata fixed; no renewed consent; strict bundle signature stays valid.
- [Host installation](batch-2026-10-07/host-install.json) on macOS **27.2** preserves signing identity, all **19 checked preferences**, history and SQLite integrity. Binary SHA-256 `f75d1f81665ffe2ae32c22367cd6b4f49d033aacd0a4ed8d032121dc685a3f2a` matches the accepted guest package. Host live recording was not tested and no host consent was reset.
- Physical hold modifiers, microphone disconnect/input-change/sleep recovery and complete VoiceOver acceptance remain open. VM events use synthetic keys and virtual audio. Earlier fullscreen/contrast acceptance retains its original source provenance; it was not all repeated here. Development signing does not establish notarized public distribution. PR #40 remains open/unmerged; no release occurred.
- The [original failed headless AX probe](regrade-2026-10-07/headless-probe/README.md), original NULL-duration reproduction and previous grade reports are preserved. Other categories' unresolved findings retain their original audit evidence and IDs; dependency/security claims were not exhaustively re-audited in this batch.

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

## B — Backend Quality — A−

RPC payloads are bounded and typed, writes are serialized off the actor, and cancellation/timeout reaps workers before audio ownership is released (`Sources/Managers/MLDaemonManager.swift:116-204`, `Sources/Managers/MLDaemonManager+Process.swift:249-290`). Cleanup failures retain original text, while a history-save failure is distinguished from successful copying (`Sources/Rebuild/RebuildSession.swift:301-345`). Import duration now survives pipeline delivery, history persistence and usage accounting, with a passing native regression.

#### ~~B1~~ ✓ done 2026-10-07 — Preserve imported audio duration through delivery

**Completed:** Validated audio duration travels through the pipeline and is used for import/retry persistence and usage. The native 2.67075-second fixture now saves the same duration and usage increment, while preserving its source WAV and signature. Live capture retains elapsed recorder duration. [Batch evidence](batch-2026-10-07/README.md).

The following retains the original finding for traceability:
- **Where:** `Sources/Rebuild/RebuildSession.swift:265-275,81-94`, `Sources/Services/TranscriptionPipeline.swift:67-70`, `Sources/Services/Audio/AudioValidator.swift:123-126`, `Sources/Stores/UsageMetricsStore.swift:96-103`.
- **Original issue:** Import sets `duration = nil`. Validation already computes file duration but the pipeline discards that metadata. Fresh native import of a 2.67075-second fixture saved a successful transcript with `duration: null`.
- **Impact:** Moderate — imported files have no length in history and add words/sessions without their audio time, skewing usage totals.
- **Fix:** Carry validated duration in the pipeline result and use it for imported-file persistence/accounting. Preserve the captured recorder duration for live sessions. Cover fixture import, saved duration, retry and usage totals.
- **Effort:** M.
- **Grade lift:** B+ → A−, by closing a demonstrated metadata gap across file transcription.

---

## C — Frontend Quality — A−

All five pages use shared semantic visual tokens, native controls and a single session. Microphone choices now have an observable lifecycle and preserve unavailable saved selections. Behavioral fixtures cover actual control effects and recovery states; physical hotplug and a complete VoiceOver walk-through remain acceptance limits.

#### ~~C1~~ ✓ done 2026-10-07 — Refresh microphone choices while Preferences remains open

**Completed:** Observable microphone descriptions refresh on connect/disconnect, app activation and permission changes. A missing saved UID remains selected with an unavailable row. Notification/authorization and actual Picker fixtures pass; physical hotplug remains D1. [Batch evidence](batch-2026-10-07/README.md).

The following retains the original finding for traceability:
- **Where:** `Sources/Rebuild/RebuildPreferencesView.swift:43-52,115-120`.
- **Original issue:** Microphones are enumerated only in the initial `.task`. App activation refreshes Accessibility alone, and there is no device-change observer. A newly connected input can remain absent; a saved input UID absent from the list has no unavailable row. This is source-confirmed, not a physical hotplug reproduction.
- **Impact:** Moderate — choosing or recovering a microphone is unclear when hardware changes while the page stays mounted.
- **Fix:** Refresh on mount, app activation, permission refresh and input connection/disconnection. Preserve the saved UID and show a disabled selected-input-unavailable row until it returns. Verify mounted-page grant/connect/disconnect transitions.
- **Effort:** S.
- **Grade lift:** B+ → A− potential, by repairing the remaining concrete Preferences state defect; full accessibility acceptance is still needed for an exemplary grade.

---

## D — Testing & Reliability — B

The expanded suite covers real rebuild UI actions, setup admission, cancellation, held-session ownership, Library maintenance and native window policy without requesting desktop consent. The signed macOS 26 VM acceptance and all six offered/legacy model inference tests pass. Sonar now passes its unchanged 80% new-code gate at 80.5%. Physical hardware and hold-key acceptance remain open; testing is B, not complete product certification.

#### ~~D3~~ ✓ done 2026-10-07 — Establish reliable automated coverage for the rebuilt UI [FE]

**Completed:** Actual SwiftUI controls, bindings, disabled/busy/error states and callbacks now have semantic fixtures, alongside startup/menu/window/hold ownership tests. Full local suite exits 0 with 3,047 discovered cases. Official Sonar now passes at 80.5%, retaining the original 80% gate and all coverage scope. The failed old headless AX experiment remains preserved. [Batch evidence](batch-2026-10-07/README.md).

The following retains the original finding for traceability:
- **Where:** `Tests/RebuildWorkspaceLayoutTests.swift:12-14`, `Tests/Views/ViewBodyRenderingTests.swift:80-99`, `Sources/Rebuild/RebuildWorkspace.swift:74-84`, `Sources/Rebuild/RebuildLibraryView.swift:51-57,137-169`, `.github/workflows/ci.yml:154-168,562`.
- **Original issue:** PR #40 fails its established 80% new-code coverage gate at 45.7%. Much of the unexecuted code is rebuilt UI. One interactive fixture is guarded after a hosted signal-6 abort; the fresh offscreen semantic probe exposed no control children and could not assert the actual button behavior. No reliable replacement currently covers these page states in hosted CI.
- **Impact:** Major — the PR remains blocked and UI regressions lack dependable automated behavior coverage. Uncovered lines are not a count of distinct bugs.
- **Fix:** Isolate and validate a minimal semantic page harness before expanding ready/blocked/busy/error and original-text cases. Keep interactive desktop checks separate. Preserve the current 80% gate and metric scope; do not use zero-child success assertions, layout-only coverage filler, placeholder snapshots or exclusions to bypass it.
- **Effort:** L overall; M for initial harness isolation/feasibility. The failed probe does not prove that offscreen testing is universally impossible or that one harness alone will close the entire gap.
- **Grade lift:** C+ → B once reliable meaningful coverage satisfies the existing gate; D1/D2 remain for B+.

#### D1 — Complete physical recording acceptance [both]
- **Where:** `scripts/vm/README.md:3-6,122-126`, `Sources/Services/Audio/AudioEngineRecorder+Interruptions.swift:17,55,69`.
- **What's wrong:** Synthetic VM input does not establish physical left/right modifier behavior. The current binary has no completed physical microphone disconnect, input-change or sleep/recovery acceptance matrix. These are evidence gaps, not observed failures.
- **Impact:** Moderate — everyday keyboard/audio-device transitions can differ from the passing virtual recording path.
- **Fix:** Retain VM evidence and record a short macOS 26/27 physical matrix for hold/release/cancel, disconnect, input changes, sleep, recovery and correct destination paste, with exact binary identity. Do not add an older-OS matrix or reset host consent.
- **Effort:** M.
- **Grade lift:** B → B+ together with D2 after D3, by closing the important runtime evidence gaps.

#### ~~D2~~ ✓ done 2026-10-07 — Exercise offered models in real inference fixtures [BE]

**Completed:** Explicit real v2/v3 English switching/warm fixtures and a Spanish v3 fixture pass. Production conservative cleanup runs successfully with Qwen3.5 and Qwen3.8, including warm reuse and switching. All six current/legacy inference tests pass together at 3312fd3; the script records source/OS and requires provisioned Apple Silicon memory. [Batch evidence](batch-2026-10-07/README.md).

The following retains the original finding for traceability:
- **Where:** `Tests/Integration/LocalEngineFixtureTests.swift:78-100`, `Tests/Integration/ParakeetEndToEndTests.swift:57-77`, `.github/workflows/nightly.yml:90-99`.
- **Original issue:** The correction fixture uses the older Qwen3 4B exclusively. Parakeet uses the selected/default repository rather than explicit v2 and v3 cases. Earlier Qwen3.5/3.8 benchmarks and packaged smoke are valuable but are not current, repeatable fixture coverage for all offered configurations. Scheduled nightly success on `master` is not rebuild-head evidence.
- **Impact:** Moderate — model/cache selection tests can pass while a newly offered model fails to load or infer.
- **Fix:** Add opt-in fixtures for shipped Qwen3.5/Qwen3.8 and explicit Parakeet v2/v3, including a multilingual v3 sample, conservative correction assertions, warm reuse and switching. Run on a provisioned Apple Silicon machine and retain exact-head results.
- **Effort:** M.
- **Grade lift:** B → B+ together with D1 after D3, by validating models users can actually select.

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

## G — Performance & Scalability — A−

PCM conversion uses fixed buffers, Parakeet processes bounded overlapping windows, and Python retains one model per engine (`Sources/Services/RawPCMConverter.swift:7-65`, `Sources/ml/parakeet.py:57-101`, `Sources/ml/loader.py:30-84`). Export runs in a cancellable background model actor; recording visualization uses bounded storage and throttled publication (`Sources/Stores/HistoryExporter.swift:11-60`, `Sources/Services/Audio/AudioEngineRecorder.swift:285-321`). Whole-history retention and recalculation now run in a background SwiftData model actor with cancellation and guarded publication.

#### ~~G1~~ ✓ done 2026-10-07 — Move history maintenance off the UI actor

**Completed:** Detached SwiftData model-actor maintenance aggregates bounded pages and deletes by predicate, with cancellation and revision guards before publishing values. Real multi-page, cancellation, stale totals and retention-boundary tests pass; no timing/freeze claim is inferred. [Batch evidence](batch-2026-10-07/README.md).

The following retains the original finding for traceability:
- **Where:** `Sources/Stores/DataManager.swift:114-115,302-327`, `Sources/Stores/DataManager+Fetching.swift:42-65`, `Sources/Stores/UsageMetricsStore.swift:229-233`, `Sources/Rebuild/RebuildPreferencesView.swift:66-71`.
- **Original issue:** Retention fetches every expired record and deletes individually on `MainActor`. Usage recalculation bounds page memory but its fetch/accumulate loop has no suspension or cancellation point. No freeze or timing regression was measured here.
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

These IDs belong to the **2026-10-07 post-PR codebase audit**. Completed IDs remain visible and addressable; unresolved IDs are unchanged. The original B/C+ post-PR report is retained at `grade-report-b64f707.md`, and earlier UI report IDs retain their own scope. Ask for the next batch or specific remaining IDs to execute them. PR #40 remains open and unmerged; read the current hosted check state before promotion.
