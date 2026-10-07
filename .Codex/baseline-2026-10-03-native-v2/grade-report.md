# Codebase Grade Report

**Project:** AudioWhisper Rebuild
**Audited:** 2026-10-03
**Stack:** Native macOS SwiftUI/AppKit, SwiftData, AVFoundation, WhisperKit/Core ML, bundled uv/Python with Parakeet and MLX.
**Version:** `rebuild/native-v2`, code commit `c75a55d3b0b12c2bd5dc7f5c67422584de792246`; the packaged app reports this exact commit. Backend means local engines/services, not a hosted API.
**Historical report:** [Original app baseline and implementation notes](baseline-f3adb17/grade-report.md). New IDs below apply to the rebuild.

**Recommended-fix follow-up:** [Implementation and validation](recommended-fixes-validation.md). Addressed IDs are marked below; the original grades and audit evidence remain historical.

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Architecture & Design | B− | 2 |
| B | Backend Quality | C+ | 2 |
| C | Frontend Quality | C+ | 2 |
| D | Testing & Reliability | C+ | 3 |
| E | Security | C+ | 2 |
| F | Dependencies & Tech Currency | C+ | 3 |
| G | Performance & Scalability | B | 2 |
| H | Documentation & Onboarding | B | 2 |
| I | Developer Experience & Tooling | B | 2 |
| **Overall** | | **C+** | **20** |

**Top 5 highest-leverage fixes:** E1, A1, B1, B2, D1.

The rebuild materially improves session ownership, setup, window policy, packaging and permission persistence. The normal native recording path works. C+ reflects concrete input/state integration defects, critical setup coverage gaps, and an affected bundled installer. Attractive screens and a large passing suite do not cancel those findings. Fixing the first five plus related control/history contracts would put a B-level regrade within reach, subject to native validation.

### Evidence and limits

- Fresh native screenshots/AX observations cover Record, history-off Library, Models & setup, Writing profiles and Preferences at this build. [UI report](ui-ux-grade-report.md) separates visual quality from state reliability.
- Earlier live checks of this exact build passed start/stop/transcription, repeated start/cancel and cold relaunch/start/cancel without another microphone prompt. Strict complete-bundle signature verification remained valid after transcription and GUI Parakeet/MLX verification. Python resource immutability has a real daemon regression.
- Current [CI run](https://github.com/jtn0123/AudioWhisper/actions/runs/37176336885) passed build/tests (2,992 cases), strict lint/Python checks and packaged bundle smoke. Sources coverage: 37.22% (14,031/37,693 lines); gate: 27%. SwiftLint analysis also completed successfully; the whole primary CI run is green.
- Prior local full suite passed 2,991 tests before the last added regression; latest focused suite passed 89. Actual local Parakeet, Whisper and MLX fixtures passed after the signature fix. A separate macOS-runner Whisper inference failure remains unresolved.
- Routing, interruption, verification, maintenance/retry and mounted-Library findings are source-confirmed. External input disconnection, deliberate machine sleep and corrupt-model runtime experiments were not performed.
- Physical global shortcut delivery, hold recording, Smart Paste, VoiceOver, long-file memory behavior and the full desktop/full-screen Spaces matrix remain unverified. Synthetic key input did not prove physical Carbon delivery. Shortcut remains disabled.
- Preview is completely ad-hoc signed, not Developer ID signed/notarized. Same-build permission persistence passed; replacing a build can change its signing identity.

---

## A — Architecture & Design — B−

`Sources/Rebuild/RebuildSession.swift:35-73,182-206` gives jobs a single owner, injectable processing services and captured configuration with late-result guards. `Sources/Rebuild/RebuildApp.swift:72-100` connects the new shell; it never launches the legacy shell. The disconnected recorder/session boundary and retry admission prevent a higher grade; compiled legacy UI is acknowledged temporary regression-test debt in `docs/rebuild.md:9`.

#### ~~A1~~ ✓ done 2026-10-03 — Connect recorder interruptions to the session
- **Where:** `Sources/Services/Audio/AudioEngineRecorder+Interruptions.swift:50-65`; `Sources/Rebuild/RebuildSession.swift:135-168`; `Sources/Rebuild/RebuildApp.swift:72-100`.
- **What's wrong:** Sleep stops recording and discards its audio URL; engine configuration failure cancels recording. Neither posted notification has a rebuild listener, so Listening can outlast actual capture.
- **Impact:** Major — misleading capture state can lose speech and leave controls busy.
- **Fix:** Deliver typed audio/error interruption events to the current session. Finish or fail once, close the overlay, preserve graceful-interruption audio deliberately, and fence stale events. Test both events and temporary-file ownership; validate a native route change.
- **Effort:** M.
- **Grade lift:** B− → B; B+ with A2, by reconciling hardware capture and session ownership.

**Implementation evidence:** Typed recorder-scoped events now carry capture UUID and graceful audio/duration into the session. Failed, graceful, duplicate and stale-event regressions pass; 36 recorder/session tests and strict targeted lint passed. Physical route-change verification remains separate.

#### ~~A2~~ ✓ done 2026-10-03 — Gate retry against maintenance and readiness
- **Where:** `Sources/Rebuild/RebuildSession.swift:118-125,141-143,170-175`.
- **What's wrong:** Retry skips recording/import installation and maintenance gates. Retrying a failed job can overlap model installation, verification or deletion after navigation.
- **Impact:** Moderate — asset operations can race processing that needs those assets.
- **Fix:** Apply common admission rules and validate the retry's captured model configuration. Preserve its audio and show a blocked reason. Test retry during install, verify and removal.
- **Effort:** S.
- **Grade lift:** B− → B+ with A1, by sharing admission rules across session entry points.


**Implementation evidence:** Retry and import share setup/install/maintenance gates; retry also checks its captured engine/model, preserves audio while blocked and exposes the reason. Both retry regressions failed before the fix and pass after; all 35 related setup/session/verification tests and strict targeted lint pass.

---

## B — Backend Quality — C+

`Sources/Services/TranscriptionPipeline.swift:55-97` preserves validation, cancellation and optional-correction fallback. `Sources/Managers/MLDaemonManager.swift:177-204` serializes RPC frames and handles timed-out workers. Input choice and model verification do not fully reach the engine/readiness contract, limiting local-service reliability.

#### ~~B1~~ ✓ done 2026-10-03 — Route the selected microphone
- **Where:** `Sources/Rebuild/RebuildPreferencesView.swift:10,51-55`; `Sources/Rebuild/RebuildSession.swift:44-50`; `Sources/Services/Audio/AudioEngineRecorder.swift:150-155`; `Sources/Managers/MicrophoneVolumeManager.swift:44-52`.
- **What's wrong:** The picker saves a device identifier that recording never reads. AVAudioEngine and boost use the system-default input.
- **Impact:** Major — selecting an external mic can still record another source or silence.
- **Fix:** Capture the selected CoreAudio device UID at start and route before format/tap setup. Boost/restore that same device; report unavailable inputs. Add routing-contract tests and native recordings from two distinguishable inputs.
- **Effort:** M.
- **Grade lift:** C+ → B−; B with B2, by implementing the advertised input choice.

**Implementation evidence:** Selected UID is resolved and applied to the input Audio Unit before format/tap setup; routing is read back and unavailable input errors reach the UI. Boost and queued restore target the captured device, even if preferences change. Routing/boost regression and all 55 related recorder/session tests pass; physical two-input recording remains pending.

#### ~~B2~~ ✓ done 2026-10-03 — Make readiness consume verification outcomes
- **Where:** `Sources/Rebuild/RebuildModelsView.swift:149-177`; `Sources/Rebuild/RebuildSession.swift:274-287`.
- **What's wrong:** Parakeet verification displays its message but ignores `result.succeeded`. Refresh computes Ready from asset presence/imports, so failed load verification does not block recording.
- **Impact:** Major — the app can encourage recording after learning its model cannot load.
- **Fix:** Keep verification state keyed by engine/model/asset identity; failure blocks readiness and offers repair. Invalidate after selection/install/delete changes. Test present-but-unloadable assets and successful repair.
- **Effort:** M.
- **Grade lift:** C+ → B with B1, by aligning setup and service results.


**Implementation evidence:** Failed load verification is persisted by engine/model/asset identity and blocks recording and file transcription across refresh/relaunch. Whisper verification now loads the model. Eight focused regressions cover failure, successful repair, changed assets, stale results and thrown errors; 33 setup/session/verification tests and strict targeted lint pass.

---

## C — Frontend Quality — C+

Small views share one observable session and theme (`Sources/Rebuild/RebuildWorkspace.swift:4-12,128-137`), with inline recovery and cancellation. Fresh native controls render correctly. Alongside A1/B1/B2, incomplete action and persistence linkages prevent a stronger grade.

#### ~~C1~~ ✓ done 2026-10-03 — Match action labels and availability to session state
- **Where:** `Sources/Rebuild/RebuildModelsView.swift:92`; `Sources/Rebuild/RebuildWorkspace.swift:141-176`; `Sources/Rebuild/RebuildStatusController.swift:34-38`; `Sources/Rebuild/RebuildSession.swift:141-143,170-175`.
- **What's wrong:** Models says Start recording while the action stops an active recording or does nothing during transcription. Import controls can accept a file during maintenance/install that the session silently rejects.
- **Impact:** Moderate — available controls promise another action or discard a request.
- **Fix:** Expose shared action titles, enabled states and blocked reasons. Use them in workspace, setup and menu; reject before opening the picker when appropriate. Test all busy/install/maintenance states.
- **Effort:** S.
- **Grade lift:** C+ → B−; B with C2 and A1/B1/B2, by matching views to session admission.


**Implementation evidence:** Record, Voice Models and the status menu share titles, enabled states and blocked reasons. Import is gated before opening a picker or accepting a drop; retry remains visible with an explanation while blocked. State-matrix regressions cover setup, capture, processing, installation and maintenance; 37 related tests and strict targeted lint pass.

#### ~~C2~~ ✓ done 2026-10-03 — Refresh a mounted Library after delivery
- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:7,70-76,101-117`; `Sources/Rebuild/RebuildSession.swift:94,219-225`; `Sources/Stores/DataManager.swift:186-211`.
- **What's wrong:** Library keeps a fetched snapshot. Save has no invalidation and `didDeliver` is an unassigned no-op, so a recording saved while Library is open does not appear until another refresh trigger.
- **Impact:** Moderate — successful persistence can look like lost history.
- **Fix:** Publish a history revision on successful save/retention/deletion, reload the mounted list and retain its query. Test delivery without navigation or search changes.
- **Effort:** S.
- **Grade lift:** C+ → B− with C1, by connecting saved data to the visible list.


**Implementation evidence:** Successful history saves, deletion and retention advance an observable store revision. Library reloads on that revision while keeping its search, and fences stale fetch results. An in-memory SwiftData/session-delivery regression failed before publication and passes after; disabled/failed saves and no-op retention do not invalidate. All 18 related integration/paging/usage tests and strict targeted lint pass.

---

## D — Testing & Reliability — C+

Session tests cover ownership, cancellation, captured settings, retry and empty output (`Tests/RebuildSessionTests.swift`); real-engine fixtures and `Tests/BundledPythonImmutabilityTests.swift` add meaningful evidence. CI enforces coverage and bundle checks. Nevertheless, setup/live delivery assembly lack critical integration coverage; test count and 37.22% aggregate coverage do not establish those new paths.

#### ~~D1~~ ✓ done 2026-10-03 — Cover the new setup coordinator [both]
- **Where:** `Sources/Rebuild/RebuildSession.swift:264-337`; `Tests/RebuildSessionTests.swift:52-78`.
- **What's wrong:** Tests assign readiness directly, bypassing async refresh, new-session microphone coalescing/denial and installation failure/retry. Setup methods directly call globals.
- **Impact:** Major — first-recording setup can regress with a green suite.
- **Fix:** Inject permission, runtime/cache and installation services. Test repeated requests, denial, delayed refresh after selection changes, failed install/retry and concurrent commands, including B2.
- **Effort:** M.
- **Grade lift:** C+ → B−; B with D2, by protecting actual first-use coordination.

**Implementation evidence:** New injectable setup services have seven coordinator tests for request coalescing/denial, blocked commands, allowed consent, stale selection refresh, failed install/retry, concurrent install and maintenance. All 62 combined setup/recording/input tests and targeted strict lint passed. Tests do not grant OS consent or install real models.

#### D2 — Exercise native delivery through isolated real stores [both]
- **Where:** `Sources/Rebuild/RebuildSession.swift:44-70,198-246`; `Tests/RecordingDeliveryIntegrationTests.swift:44-52`; `Tests/RebuildSessionTests.swift:27-42`.
- **What's wrong:** Native tests replace copy/save with array appends. Existing store integration constructs legacy RecordingViewModel rather than new live services.
- **Impact:** Major — central clipboard/history behavior lacks integration coverage on the launched path.
- **Fix:** Inject clipboard/history destinations into native live assembly. Exercise pipeline → isolated pasteboard/SwiftData, including correction fallback, save failure, cancellation and retry-audio cleanup.
- **Effort:** M.
- **Grade lift:** C+ → B with D1, by verifying production delivery wiring.

#### D3 — Keep a build-specific native acceptance matrix [FE]
- **Where:** `.github/workflows/ci.yml:385-400`; `Sources/Rebuild/RebuildApp.swift:143-191`; `docs/rebuild.md:31-42`.
- **What's wrong:** Diagnostic smoke exits before GUI creation. Physical shortcut, hold, paste and full-screen window scenarios remain unverified.
- **Impact:** Moderate — headless success leaves central OS workflows unproven.
- **Fix:** Record fresh/denied consent, click/menu/physical shortcut/hold, cancel/re-record, import, destination paste and normal-window Spaces results per build; automate practical portions.
- **Effort:** M.
- **Grade lift:** C+ → B+ with D1/D2, by covering native interaction boundaries. Coverage gaps are not newly reproduced OS defects.

---

## E — Security — C+

Verified uv archives/final signed bytes, frozen installation and allowlisted subprocess environments are strong foundations (`scripts/prepare-uv.sh:21-34`; `Sources/Services/UvBootstrap.swift`; `Sources/Managers/MLDaemonManager+Process.swift`). Bytecode suppression preserves signed resources; permissions are explicit and data isolated. An affected installer and permissive public-release signing path remain material gaps.

#### ~~E1~~ ✓ done 2026-10-03 — Upgrade affected bundled uv
- **Where:** `scripts/prepare-uv.sh:4-17`; `Sources/Services/UvBootstrap.swift:81`.
- **What's wrong:** uv 0.8.5 is affected by the vendor's [entry-point advisory](https://github.com/astral-sh/uv/security/advisories/GHSA-4gg8-gxpx-9rph), patched in 0.11.15: malicious wheels can write executables outside their environment. Exploitation with this frozen trusted lock was not demonstrated.
- **Impact:** Major — a known-affected installer runs under the user's account.
- **Fix:** Pin a reviewed supported uv ≥0.11.15; update both architecture checksums and runtime minimum. Preserve signing/hashing and rerun bootstrap, frozen failure, bundle and engine checks. Review [uninstall](https://github.com/astral-sh/uv/security/advisories/GHSA-pjjw-68hj-v9mw) and [ZIP](https://github.com/astral-sh/uv/security/advisories/GHSA-pqhf-p39g-3x64) advisories too.
- **Effort:** M.
- **Grade lift:** C+ → B−; B with E2, by removing the confirmed affected component.

**Implementation evidence:** uv 0.12.23, both vendor archive checksums, universal arm64/x86_64 binary and strict signature verification passed. Security-floor regression failed before and passed after; all 29 uv policy/bootstrap tests passed. Final packaged/real-engine checks follow after the remaining fixes.

#### E2 — Require distribution trust checks for public releases
- **Where:** `Makefile:77-84`; `scripts/build.sh:407-418`.
- **What's wrong:** Public release can upload the preview-capable script's ad-hoc artifact without requiring Developer ID signing/notarization/stapling. Local complete ad-hoc signing is appropriate for this preview.
- **Impact:** Moderate — public artifacts can skip intended distribution validation.
- **Fix:** Require distribution signing and notarization/stapling before release upload, fail clearly without credentials and keep local preview packaging separate.
- **Effort:** M.
- **Grade lift:** C+ → B with E1, by making public distribution fail closed.

---

## F — Dependencies & Tech Currency — C+

Swift/Python locks, curated model pins, frozen installation and weekly checks support reproducibility (`Package.resolved`; `Sources/Resources/uv.lock`; `.github/dependabot.yml`). Bundled uv escapes that monitoring. Relevant Swift fixes are available; merely newer ML releases are not considered confirmed defects.

#### F1 — Update KeyboardShortcuts
- **Where:** `Package.swift:16`; `Package.resolved`; `Sources/Rebuild/RebuildPreferencesView.swift:38`.
- **What's wrong:** Pinned 3.0.1 misses [vendor 3.1.0 fixes](https://github.com/sindresorhus/KeyboardShortcuts/releases/tag/3.1.0) for recorder behavior and function keys with menus open. App reproduction remains untested.
- **Impact:** Moderate — core shortcut functionality has relevant maintained fixes available.
- **Fix:** Update the lock; verify custom recording, registered-shortcut display and menu-open function-key delivery in the packaged app.
- **Effort:** S.
- **Grade lift:** C+ → B with E1, by adopting core-control fixes.

#### F2 — Monitor bundled-tool advisories
- **Where:** `.github/dependabot.yml`; `scripts/prepare-uv.sh:7-17`.
- **What's wrong:** Package monitoring does not cover shell-script-pinned uv. Zero open Dependabot alerts do not clear E1.
- **Impact:** Moderate — bundled installer advisories can remain unnoticed.
- **Fix:** Centralize version/checksums and schedule vendor-advisory checks against the shipped version, without executing unreviewed upgrades automatically.
- **Effort:** S.
- **Grade lift:** C+ → B with E1/F1, by closing that maintenance blind spot.

#### F3 — Adopt incremental Argmax audio loading
- **Where:** `Package.resolved`; `Sources/Services/LocalWhisperService.swift:185`.
- **What's wrong:** SDK 1.0.0 loads whole files. [Vendor 1.1.0](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0) offers incremental loading to reduce long-file memory pressure.
- **Impact:** Moderate — imports retain avoidable memory pressure; no app OOM reproduced here.
- **Fix:** Upgrade and enable incremental loading in production. Verify short-speech parity and representative long-file memory behavior.
- **Effort:** M.
- **Grade lift:** C+ → B with E1/F1, by improving the actual import path.

---

## G — Performance & Scalability — B

Bounded Python caches (`Sources/ml/loader.py:30-42`), Whisper LRU/memory-pressure handling (`Sources/Services/LocalWhisperService.swift:87-93,144-155`) and throttled capture publication (`Sources/Services/Audio/AudioEngineRecorder.swift:388-400`) help normal usage. Library pages 50 rows and streams exports. Whole-file preparation/allocation churn remain confirmed costs; long-file memory and UI latency were not benchmarked.

#### G1 — Stream Parakeet PCM preparation
- **Where:** `Sources/Services/ParakeetService.swift:129-141,198-232`; imported-audio validation.
- **What's wrong:** Conversion retains the complete Float array then another complete Data copy. Import has no duration/size cap.
- **Impact:** Moderate — long files consume avoidable preprocessing memory.
- **Fix:** Convert/write bounded chunks with cancellation and partial-file cleanup. Test short parity and long-input bounded buffers; measure resident memory.
- **Effort:** M.
- **Grade lift:** B → B+ with G2, by bounding preprocessing memory.

#### G2 — Remove per-bin visualization allocations
- **Where:** `Sources/Services/Audio/AudioEngineRecorder+Interruptions.swift:74-79`.
- **What's wrong:** Downsampling creates an Array per bin, typically 128 per publication.
- **Impact:** Minor — recurring allocation churn; audible glitches unverified.
- **Fix:** Compute RMS over slices/pointers, preserving semantics/throttling. Compare sample outputs and profile allocations.
- **Effort:** S.
- **Grade lift:** B → B+ with G1, by reducing recurring recording work.

---

## H — Documentation & Onboarding — B

`docs/rebuild.md:7-27,31-42` explains isolation, architecture, permissions and conventional desktop policy, then separates observed checks from outstanding scenarios. README still uses legacy destinations. Network/integrity claims require alignment with production; the feature-parity list is a target, not proof B1 works.

#### H1 — Replace legacy usage instructions
- **Where:** `README.md:76,104-118,157-160`; `Sources/Rebuild/RebuildStatusController.swift:27-30`; `docs/rebuild.md:13-19`.
- **What's wrong:** README refers to Correction under Models, Dashboard and old controls. Current shell separates Writing profiles and Models & setup with opt-in shortcut registration.
- **Impact:** Moderate — users follow labels absent from the rebuild.
- **Fix:** Document current setup/recording/shortcut destinations, Express overlay behavior and optional Smart Paste. Distinguish implemented features from unverified/outstanding parity.
- **Effort:** S.
- **Grade lift:** B → B+ with H2, by matching onboarding to shipped controls.

#### H2 — Align download and integrity claims
- **Where:** `README.md:123`; `docs/adr/0006-model-integrity.md:31-40`; `Sources/Services/UvBootstrap.swift:175-188`; `Sources/Services/LocalWhisperService.swift:96-101`; `Sources/Services/ParakeetService.swift:114-119`.
- **What's wrong:** Runtime setup downloads Python/packages beyond models. ADR later-load integrity promises exceed direct structural probes in production engine paths.
- **Impact:** Moderate — users/reviewers can misunderstand network and verification guarantees.
- **Fix:** Document actual runtime/package downloads. Enforce a shared production integrity contract or narrow the ADR to actual checks; distinguish asset presence from successful loading.
- **Effort:** M.
- **Grade lift:** B → B+ with H1, by aligning operational claims and code.

---

## I — Developer Experience & Tooling — B

Strict lint/analyzer rules, Python typing/tests, coverage and complete bundle checks enforce useful gates (`.github/workflows/ci.yml`). Current build/tests took roughly five minutes. Universal daily packaging and duplicate Sonar execution add avoidable iteration/CI cost.

#### I1 — Add an incremental native development target
- **Where:** `Makefile:28-31`; `scripts/build.sh:107-115,161-203`.
- **What's wrong:** Every normal launch builds both release architectures and recreates the full bundle.
- **Impact:** Moderate — routine UI changes pay distribution costs.
- **Fix:** Add host-architecture debug packaging with all resources, complete signing and stable rebuild identity. Keep universal release validation and document permission/signing boundaries.
- **Effort:** M.
- **Grade lift:** B → B+, by shortening normal iteration.

#### I2 — Reuse CI coverage in Sonar
- **Where:** `.github/workflows/ci.yml:105`; `.github/workflows/sonarcloud.yml:65-71`.
- **What's wrong:** Sonar independently reruns all tests instead of consuming gated coverage.
- **Impact:** Moderate — duplicate work adds latency and different-run evidence.
- **Fix:** Export commit-bound test/coverage artifacts from primary CI and consume them in Sonar, failing on missing/mismatched artifacts.
- **Effort:** M.
- **Grade lift:** B → B+, by reducing duplication while retaining provenance.

---

Request fixes with a report prefix, for example **code E1 A1 B1**. UI IDs in the separate report have different meanings. This audit changes reports/artifacts only and does not claim these findings are repaired.
