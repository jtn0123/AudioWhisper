# Codebase Grade Report

**Project:** AudioWhisper Rebuild
**Audited:** 2026-10-04
**Code:** `rebuild/native-v2`, `187eacdb55737ba8eb6b57c9bb59f5e0cc23c506`
**Stack:** SwiftUI/AppKit, SwiftData, AVFoundation, WhisperKit/Core ML, bundled uv/Python, Parakeet and MLX. “Backend” means the local transcription and writing services.

This is a fresh audit of the rebuild after the VM recorder fixes. The older
[grade report](grade-report.md) retains its original findings and IDs. IDs below
belong to **this report**; specify “187eacd audit B1,” for example, to avoid
confusing them with historical completed items. This pass changes documentation
and audit evidence, not the app or its model defaults.

## Summary

| ID | Category | Grade | Open items | Plain meaning |
|---|---|---|---|---|
| A | Architecture & Design | B | 2 | Clear session ownership; some hidden configuration and duplicate app structure remain |
| B | Backend Quality | C+ | 3 | Recording works, but transcript preservation needs stronger protection |
| C | Frontend Quality | B | 2 | A coherent native interface with weak model guidance and some profile friction |
| D | Testing & Reliability | B− | 3 | Strong regression and VM checks; limited speech-quality and hardware coverage |
| E | Security | B | 1 | Local processing and controlled setup; public release packaging needs an enforced gate |
| F | Dependencies & Tech Currency | B+ | 1 | Pinned, monitored dependencies; the bundled tool needs its own update signal |
| G | Performance & Scalability | B | 2 | Bounded audio/history processing; export and cold setup still deserve attention |
| H | Documentation & Onboarding | B− | 2 | Useful evidence and VM instructions, mixed with obsolete user/developer guidance |
| I | Developer Experience & Tooling | B | 2 | Useful checks and reproducible packaging, with an analyzer failure loophole |
| **Overall** | | **B−** | **18** | A substantially improved preview, with meaningful text-integrity and acceptance work left |

**Top five, ranked:** **B1, B2, I1, D1, C1**. Stop deleting real words; make long
cleanup checks compare content; fail CI when its analyzer cannot run; measure
model quality properly; guide users to the right English model.

The overall grade is expert judgment, not an arithmetic average. Testing,
security and preservation of what the user actually said carry more weight
than styling or test totals. The previous B was a historical snapshot; the B−
here reflects a broader audit that found previously unreported integrity defects.
It does not mean the recorder fixes made the app worse.

## Evidence and limits

- The [code commit's CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37267004905)
  completed successfully: build/tests/coverage, strict lint/Python, SwiftLint
  analyze and universal bundle smoke. SonarCloud was skipped by push policy;
  this is not a new Sonar quality-gate result.
- CI's source-only Swift line coverage is **38.39%: 14,780 / 38,498 lines across
  192 files**. The enforced floor is still 27%. Code coverage and successful
  test counts do not establish speech accuracy or native OS behavior.
- The preceding implementation pass recorded **3,059 Swift tests executed,
  47 optional skips, zero failures**, and **137 unattended acceptance tests
  with zero skips/failures**. These are the documented local runs, not a claim
  that all were repeated during this read-only grading pass.
- Reviewed [native VM evidence](macos-vm-validation.md) covers ten recording
  cancellations, actual Whisper transcription, exactly-once Smart Paste into
  TextEdit, guest OS global-shortcut dispatch, microphone consent continuity,
  Preferences staying off a full-screen Space and the recorder appearing over
  it. The guest was macOS 26.6.2, four CPUs/8 GB RAM, using virtual BlackHole
  audio and a public fixture. The binary was built from `77d85cd` plus the
  implementation subsequently committed in `187eacd`; it was a signed arm64
  development preview, not a notarized distribution build.
- Fresh pure-helper reproductions confirm B1 and B2. The helpers were extracted
  verbatim and compiled with `swiftc -O`; no microphone or user transcript was
  used. The reproduced behavior and source scope are retained in
  [audit evidence](audit-187eacd/evidence.json).
- I1 was reproduced with installed SwiftLint 0.65.1 (CI pins 0.65.0) and a deliberately missing
  compiler log: analyzer exit 1, current CI recipe exit 0, empty report, zero
  counted findings. This proves the gate weakness, not that the successful
  remote run actually suffered that failure.
- Physical modifier hold/release, Sonoma 14 native compatibility, physical
  device disconnect/sleep, multiple displays and VoiceOver remain acceptance
  gaps. The VM input limitation and beta-host VM-control crashes are environment
  findings, not additional AudioWhisper defects. The lint runner is macOS 14;
  build/test, analyzer and bundle jobs use macOS 15. Lint on 14 does not validate
  the native Sonoma user journey.
- Published model research is separate from locally measured inference. See
  [model review](model-review-2026-10-04.md) and [UI/UX report](ui-ux-grade-report-187eacd.md).

## A — Architecture & Design — B

The rebuild has a single observable main-actor session owner and captures the
destination/configuration before asynchronous work (`Sources/Rebuild/RebuildApp.swift:59`,
`RebuildSession.swift:36`, `RebuildSession.swift:289`). Cancellation and session-ID
checks fence stale delivery; production destinations are injectable for real
isolated integration tests. The remaining weaknesses are implicit provider
configuration and compiling two complete app flows into one target.

#### A1 — Pass captured model configuration explicitly to the provider

- **Where:** `Sources/Services/TranscriptionPipeline.swift:117`, `Sources/Services/SpeechToTextService.swift:157`, `Sources/Rebuild/RebuildSession.swift:65`, `Sources/ViewModels/TranscriptionCoordinator.swift:74`.
- **What's wrong:** The pipeline accepts a configuration but does not pass its Parakeet selection to the speech service. The service instead reads a task-local configuration, falling back to mutable defaults. Current live callers install that task-local value correctly; a direct pipeline caller does not inherit that guarantee.
- **Impact:** Moderate — a reused pipeline can run a different model from the configuration it was given. This is a boundary defect, not a reproduced wrong-model event in the current UI.
- **Fix:** Pass typed provider/model and warmup options explicitly through `transcribeValidated`. Add a focused case where captured settings differ from current defaults.
- **Effort:** M.
- **Grade lift:** B → B+, by making configuration ownership explicit across the engine boundary.

#### A2 — Separate shared engines from the dormant legacy app flow

- **Where:** `Sources/App/AudioWhisperEntryPoint.swift:5`, `Package.swift:24`, `Sources/Rebuild/`, `Sources/ViewModels/RecordingViewModel*`, `Sources/Views/Dashboard/`.
- **What's wrong:** The executable launches RebuildApp but still compiles the old UI/orchestration alongside the new flow. Shared engine code is useful; duplicate complete application flows make it easy to change or test the inactive path.
- **Impact:** Moderate — maintenance and acceptance evidence can target code users never reach.
- **Fix:** Inventory actual callers, retain shared services, and isolate or remove the dormant app assembly in a staged change. Preserve meaningful shared-engine tests and migrate tests that should protect the rebuild.
- **Effort:** L.
- **Grade lift:** B → B+, by reducing ambiguity about the production entry point and ownership.

## B — Backend Quality — C+

Selected microphone routing is applied/read back before tap setup
(`Sources/Services/Audio/AudioInputRouting.swift:23`); model verification performs
real loads and persists failure by asset identity (`RebuildModelVerification.swift:15`,
`LocalWhisperService.swift:225`). Validation, typed RPC, retries and cancellation
are substantially stronger than the original app. However, two confirmed helper
defects can undermine the words delivered to the user, and successful cleanup
does not retain an original version for recovery.

#### B1 — Preserve legitimate parentheses and square brackets

- **Where:** `Sources/Services/SpeechToTextService.swift:225`, `Tests/SpeechToTextServiceTests.swift:71`.
- **What's wrong:** The cleaner removes every parenthesized or bracketed span, rather than recognized acoustic markers. Reproduction: `Send the report (including taxes) to Jordan [the editor].` becomes `Send the report to Jordan .` before optional writing cleanup.
- **Impact:** Major — legitimate qualifications, names, citations or code can silently disappear from copied and saved text.
- **Fix:** Remove only a deliberate allowlist of provider noise/silence markers. Preserve ordinary prose/code brackets, and cover nested content and marker-only silence separately.
- **Effort:** S.
- **Grade lift:** C+ → B−, by removing confirmed silent loss of valid transcript content.

#### B2 — Compare content when guarding long writing corrections

- **Where:** `Sources/Services/SemanticCorrectionService.swift:208`.
- **What's wrong:** Above 4,000 characters, `safeMerge` checks only the change in length. A 5,400-character repetition of `alpha ` can be replaced by unrelated, equally long `bravo ` text and accepted; the same 3,600-character example is rejected. This is a reproduced safeguard defect, not evidence that a model generated that particular rewrite.
- **Impact:** Major — long dictation loses the content-change protection the app applies to shorter text.
- **Fix:** Use bounded chunk/token content comparison with an explicit runtime budget. Retain the original and expose a skipped-cleanup outcome when comparison is inconclusive. Verify unrelated rewrites, truncation and legitimate small changes on long input.
- **Effort:** M.
- **Grade lift:** C+ → B−; together with B1, toward B, by restoring protection consistently across transcript lengths.

#### B3 — Keep an original transcript after successful cleanup

- **Where:** `Sources/Services/TranscriptionPipeline.swift:9`, `Sources/Rebuild/RebuildSession.swift:305`, `Sources/Models/TranscriptionRecord.swift:11`.
- **What's wrong:** The result, displayed session text and history retain final text only when cleanup succeeds. The original recognition result is unavailable to compare or restore after temporary audio is removed.
- **Impact:** Moderate — users cannot recover wording that optional AI cleanup altered.
- **Fix:** Carry original and final text separately, expose “Use original,” and persist the pair only when local history is enabled. Design a compatible SwiftData migration and keep history-off behavior private.
- **Effort:** M.
- **Grade lift:** C+ → B−; complements B1/B2 by making cleanup reversible rather than silently authoritative.

## C — Frontend Quality — B

Purpose-specific SwiftUI screens share heading, section and theme components
(`Sources/Rebuild/RebuildWorkspace.swift:5`, `:97`). Primary/menu/setup recording
actions consume a common session-state contract (`RebuildSession.swift:325`,
`RebuildModelsView.swift:98`). Library reloads are driven by a store revision and
reject stale fetch results (`RebuildLibraryView.swift:75`, `:107`). Guidance and
app-profile presentation remain weaker than the underlying capabilities.

#### C1 — Guide model selection around English and measured resource needs

- **Where:** `Sources/Rebuild/RebuildModelsView.swift:36`, `Sources/Rebuild/RebuildWritingView.swift:29`, `Sources/Services/MLXModelManager.swift:58`, `Sources/Models/TranscriptionTypes.swift:34`.
- **What's wrong:** Voice choices are mostly version names and cleanup choices repository names. The cleanup manager has human descriptions that the picker does not show. Whisper sizes are static estimates associated with old single-file artifacts, while the production runtime downloads Core ML bundles; they are not verified installed sizes or RAM requirements.
- **Impact:** Moderate — users cannot confidently choose English quality versus multilingual coverage, download size or speed.
- **Fix:** Offer an English recommendation with a short reason; preserve multilingual choices. Show cleanup descriptions, identify estimates honestly, and report actual installed bytes separately from measured peak memory. Use the model review and a shared-corpus benchmark before changing defaults.
- **Effort:** M.
- **Grade lift:** B → B+, by turning technical model selection into a guided product decision. Also UI/UX B1.

#### C2 — Show app names and refresh app-aware writing choices

- **Where:** `Sources/Rebuild/RebuildWritingView.swift:111`, `:125`, `:141`, `Sources/Managers/AppCategoryManager.swift:74`.
- **What's wrong:** Saved mappings render raw bundle identifiers and repeat them in accessibility labels. Running apps are sampled once in `.task`; an app opened afterward is absent until the view is recreated. The behavior is source-confirmed; a populated native mapping was not exercised during this review.
- **Impact:** Moderate — assigning or checking a writing profile requires deciphering technical identifiers and reopening the screen.
- **Fix:** Resolve/persist friendly app names with an identifier fallback, show icons where useful, and refresh on app launch/termination or through an explicit Refresh action.
- **Effort:** S.
- **Grade lift:** B → B+, by making an existing workflow understandable and current. Also UI/UX C1.

## D — Testing & Reliability — B−

Setup tests exercise injected permission and model transitions instead of merely
assigning Ready (`Tests/RebuildSetupTests.swift:42`). Live delivery integration
uses isolated pasteboard/SwiftData destinations, and the VM now verifies actual
native shortcut/transcription/paste/full-screen behavior. The real-engine speech
fixture nevertheless recognizes one sentence using a keyword assertion
(`Tests/Integration/LocalEngineFixtureTests.swift:12`), which does not establish
comparative model accuracy or broad hardware compatibility.

#### D1 — Build a representative speech and cleanup quality benchmark [BE]

- **Where:** `Tests/Integration/LocalEngineFixtureTests.swift:12`, `:78`, `Tests/Integration/ParakeetEndToEndTests.swift:76`, `Tests/Resources/`, `.claude/bench/`.
- **What's wrong:** The actual-engine acceptance fixture checks four of five keywords in one English sentence; writing inference checks one correction. The historical six-case cleanup benchmark is useful but predates current output parsing/guard changes. None establishes the best current English model.
- **Impact:** Major — a model can pass integration while mishandling accents, noise, names, numbers, silence or long recordings.
- **Fix:** Use a licensed, fixed English corpus plus a small multilingual subset. Measure raw ASR word errors, insertions on silence, named entities/numbers, long-form boundaries, cleanup meaning changes, cold/warm time and peak memory. Record model revision, quantization, runtime and hardware. Keep expected text and scoring normalization reproducible.
- **Effort:** L.
- **Grade lift:** B− → B, by measuring the app's actual output quality and supporting defensible model selection.

#### D2 — Finish the native compatibility and physical-input matrix [FE]

- **Where:** `.Codex/macos-vm-validation.md:85`, `scripts/vm/README.md:8`, `Package.swift:7`.
- **What's wrong:** The repeatable Tahoe guest cannot produce the device-specific modifier bits needed for the physical hold test. Minimum Sonoma 14, physical audio-device changes/sleep, multiple displays and VoiceOver also lack completed native acceptance evidence.
- **Impact:** Moderate — the supported product surface exceeds the environments and inputs actually demonstrated.
- **Fix:** Add a Sonoma baseline, then dedicated physical-input/device and accessibility runs. Keep guest OS shortcut dispatch distinct from physical key proof; publish pass/incomplete per scenario without repeated user handoffs where automation is possible.
- **Effort:** M.
- **Grade lift:** B− → B, by closing meaningful compatibility uncertainty rather than increasing unit-test counts.

#### D3 — Ratchet coverage against the current measured baseline [both]

- **Where:** `.github/workflows/ci.yml:144`, `scripts/coverage-gate.py:53`.
- **What's wrong:** The 27% floor is over eleven percentage points below current source-only CI coverage of 38.39%. A large regression can pass the existing gate.
- **Impact:** Moderate — significant loss of exercised code may go unnoticed during maintenance.
- **Fix:** Raise the floor with a justified runner-variation margin and add focused active-service expectations. Do not force headless GUI coverage or confuse export-format coverage totals with SwiftPM's aggregate.
- **Effort:** S.
- **Grade lift:** B− → B, by preventing erosion of demonstrated coverage.

## E — Security — B

Transcription and writing run locally; subprocess arguments and environment
boundaries are controlled (`Sources/Managers/MLDaemonManager+Process.swift:52`,
`:151`). Setup uses the shipped frozen Python lock (`UvBootstrap.swift:186`),
checksum verification for the bundled tool and pinned Parakeet/cleanup revisions
(`Sources/Models/ModelPins.swift:28`). Whisper's representative-file hash is
trust-on-first-use, not complete weight verification (`ModelManager.swift:67`);
that limit should be described accurately. No exploit or exhaustive dependency
security certification is claimed.

#### E1 — Require distribution signing and notarization before public upload

- **Where:** `Makefile:83`, `scripts/build.sh:478`, `:495`.
- **What's wrong:** `make release` calls the preview-capable build without requiring notarization before uploading. It can publish a locally/ad-hoc signed bundle. This is a command-path gap, not evidence of a current bad public release.
- **Impact:** Moderate — public users can receive a build that fails normal macOS distribution checks or has inconsistent identity.
- **Fix:** Require Developer ID signing, successful notarization/stapling and Gatekeeper assessment in the public release path. Retain a separately named local preview build path.
- **Effort:** M.
- **Grade lift:** B → B+, by making distribution requirements enforced instead of optional.

## F — Dependencies & Tech Currency — B+

Swift and Python dependencies are pinned, and weekly Dependabot updates cover
Swift, Actions and the uv project (`.github/dependabot.yml:3`). Python minor
upgrades have an explicit API/inference validation checklist
(`Sources/Resources/pyproject.toml:29`). Current publisher releases were checked;
some Python packages have newer releases, but a version gap alone is not a bug
and upgrading the ML runtime without inference checks would weaken reliability.

#### F1 — Monitor the bundled uv binary's release/advisory stream

- **Where:** `.github/dependabot.yml:3`, `scripts/prepare-uv.sh:7`.
- **What's wrong:** The shell-managed uv binary pin is outside the package ecosystems watched by Dependabot. Its updates need a separate signal; no known vulnerability in the shipped binary was established here.
- **Impact:** Moderate — an important setup tool can miss reviewed maintenance or security updates.
- **Fix:** Centralize the pin/checksum metadata and add a scheduled publisher release/advisory check that proposes a reviewed update. Retain checksum and packaging validation.
- **Effort:** S.
- **Grade lift:** B+ → A−, by covering the remaining manually pinned tool boundary.

## G — Performance & Scalability — B

Whisper uses incremental audio loading (`LocalWhisperService.swift:192`) and
Parakeet has bounded decoding/chunk handling. Library loading is paged and
search is debounced (`RebuildLibraryView.swift:107`); waveform/timer lifecycle
work stops while inactive. The current audit did not collect fresh startup,
UI-frame or large-library timings, so inferred stalls and previous engine times
are kept distinct from new measurements.

#### G1 — Move Library export work off the UI actor

- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:140`, `Sources/Stores/DataManager+Fetching.swift:42`, `Sources/Stores/DataManager.swift:114`.
- **What's wrong:** Paging limits memory, but the main-actor fetch loop has no suspension between pages. Formatting, file writes, synchronization and replacement also run on the UI actor. The source establishes blocking work; a large-library freeze duration was not measured here.
- **Impact:** Moderate — exporting a large local library can delay UI input and progress feedback.
- **Fix:** Fetch/export through an appropriate isolated model actor and worker using transferable values. Keep only the panel/status on the UI actor; stream pages with cancellation and write-error handling.
- **Effort:** M.
- **Grade lift:** B → B+, by keeping export responsive without losing bounded memory behavior.

#### G2 — Measure and correct serialized cold-model warmup scheduling

- **Where:** `Sources/Services/SpeechToTextService.swift:169`, `Sources/ml/rpc.py:103`, `Sources/Managers/MLDaemonManager.swift:94`.
- **What's wrong:** Swift launches writing warmup concurrently, but warmup and Parakeet requests share a sequential Python worker. A cold cleanup load can queue ahead of recognition, and the raw return also waits for warmup. “Parallel” does not mean parallel model execution in this implementation.
- **Impact:** Moderate — enabling optional writing can increase first-result delay even before correction runs. The actual penalty is not freshly measured.
- **Fix:** Measure cold/warm combined runs, then prewarm during idle setup or schedule warmup after recognition. Add a second worker only if measured latency benefit justifies extra memory.
- **Effort:** M.
- **Grade lift:** B → B+, by aligning setup scheduling with the actual worker model.

## H — Documentation & Onboarding — B−

The repository has useful implementation notes, machine-readable native
acceptance artifacts and reproducible VM scripts. However, the README names the
wrong cleanup default/location (`README.md:81`), and contribution instructions
still recommend launch/signing practices inconsistent with permission continuity
(`CONTRIBUTING.md:84`). These are practical onboarding errors, not missing
documentation for hypothetical features.

#### H1 — Reconcile user/developer instructions with the launched rebuild

- **Where:** `README.md:78`, `:109`, `CONTRIBUTING.md:40`, `:84`, `:298`.
- **What's wrong:** Docs mix old Dashboard/Space controls, the previous Qwen default, and bare `swift run` guidance that calls repeated permission prompts normal. The architecture list still names removed Alamofire/HotKey/API-key components.
- **Impact:** Moderate — users and developers follow instructions that recreate confusion or permission churn.
- **Fix:** Document actual Preferences shortcut setup and Writing model selection, the current default, persistent signed preview workflow and current stack. Keep CLI commands scoped to appropriate build/test use.
- **Effort:** S.
- **Grade lift:** B− → B, by making the existing documentation consistent with shipped behavior.

#### H2 — Describe network setup and model verification accurately

- **Where:** `README.md:127`, `CONTRIBUTING.md:54`, `docs/adr/0006-model-integrity.md`, `Sources/Services/UvBootstrap.swift:170`, `Sources/Services/ModelManager.swift:67`.
- **What's wrong:** “Network access only to download models” omits Python/package setup. “Verified” can imply complete weight authenticity although structural checks, successful loads and representative-file trust-on-first-use cover different guarantees.
- **Impact:** Moderate — privacy and readiness expectations are stronger or less clear than the actual setup contract.
- **Fix:** Explain initial runtime/package/model downloads separately from offline inference. Name structural/load verification and representative-file hashing, its first-download trust and which weights are revision-pinned.
- **Effort:** S.
- **Grade lift:** B− → B, by making privacy and verification promises precise.

## I — Developer Experience & Tooling — B

The Make workflow recovers the Xcode environment, packaging supports isolated
output paths and refuses a running output bundle, and the VM runners produce
reviewable evidence (`scripts/build.sh:158`, `scripts/vm/README.md`). Current CI
has multiple useful independent jobs. The analyzer recipe can nevertheless hide
an execution failure, and the installation target lacks the packaging guard.

#### I1 — Fail CI when SwiftLint analyze cannot execute

- **Where:** `.github/workflows/ci.yml:533`, `:547`, `:574`.
- **What's wrong:** Analyzer stderr is discarded and the pipeline ends with `|| true`; subsequent gates count strings in its report. The reproduced missing-log error produced analyzer exit 1, recipe exit 0 and an empty report that both gates treat as zero violations.
- **Impact:** Major — CI can claim clean analysis when analysis never completed.
- **Fix:** Retain diagnostics and check tool execution status/report validity. Distinguish a valid report containing rule violations from failure to read the compiler log or run the analyzer. Add a small gate regression for the missing-log/error case.
- **Effort:** S.
- **Grade lift:** B → B+, by making a green check represent completed analysis.

#### I2 — Guard the installed preview replacement path

- **Where:** `Makefile:32`, `scripts/build.sh:158`.
- **What's wrong:** `make run-dev` copies directly over `/Applications/AudioWhisper Rebuild.app` without checking whether that destination is running. The new build output guard protects a different path. Permission/signature churn from this exact case was not reproduced on the host.
- **Impact:** Moderate — a live process can continue using an app bundle whose resources have been replaced.
- **Fix:** Stop/wait for the exact installed target, stage a complete signed bundle, then replace it atomically while retaining the persistent development identity.
- **Effort:** S.
- **Grade lift:** B → B+, by extending safe packaging to the actual install command.
