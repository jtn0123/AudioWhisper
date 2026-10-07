# AudioWhisper Rebuild — fresh codebase grade

**Audited:** 2026-10-06
**Code:** `f30c081ed0bc324bf29c882052a6033d7028783b`, `rebuild/native-v2`
**Stack:** SwiftUI/AppKit, SwiftData, AVFoundation, WhisperKit/Core ML,
bundled uv/Python, Parakeet and MLX. Backend means the local speech/writing services.

This grades the installed rebuild after Qwen3.5/3.8 integration. The original
app and historical reports are separate. IDs belong to **f30c081 codebase**;
use “code B1” when referring to this report. This audit changes reports/evidence,
not application behavior, model preferences or host permissions.

**Remediation:** B1-B4/C3 and I1/E1/C1/G1/I2/G2/A1/D2/H1 are complete.
H2 was also corrected while updating setup instructions. C2 was removed with the
entire app-profile feature at the user's direction; code D1 is excluded and native
acceptance targets macOS 26/27. Remaining code items: **A2, E2, F1**.
[First five fixes](fixes-next5-2026-10-06/README.md) and
[the streamlined next ten](fixes-next10-2026-10-06/README.md) retain the evidence.
Letter grades and dimension counts below remain the audit baseline, not an automatic regrade.

## Summary

| ID | Category | Grade | Open items | Simply |
|---|---|---|---:|---|
| A | Architecture & Design | B | 2 | Clear session ownership, with hidden configuration and dormant app flows |
| B | Backend Quality | C+ | 0 | Engines work; some words can still be removed or rewritten incorrectly |
| C | Frontend Quality | B | 2 | Clear interface; Library resizing, installs and app mappings need work |
| D | Testing & Reliability | B | 2 | Strong regressions and real VM checks; hardware/minimum-OS gaps remain |
| E | Security | B− | 2 | Local processing and pinned setup; one vulnerable dependency and a weak release gate |
| F | Dependencies & Tech Currency | B | 1 | Current, locked model runtime; a known advisory and manual tool monitoring remain |
| G | Performance & Scalability | B | 2 | Fast short edits and bounded memory; export/cold scheduling need work |
| H | Documentation & Onboarding | B− | 2 | Useful evidence, mixed with incorrect default and development instructions |
| I | Developer Experience & Tooling | B | 2 | Good automation; analyzer errors and installed-app replacement are insufficiently guarded |
| **Overall** | | **B−** | **15** | A much better preview, still short of dependable transcript preservation |

The overall grade is judgment weighted toward delivered words, reliability and
security, not a numerical average. UI/UX is separately **B** in the
[UI report](ui-ux-grade-report-f30c081.md). Frontend code quality and the whole
user experience are distinct assessments.

## Ranked priorities

| Rank | Item | Plain meaning | Impact | Effort |
|---:|---|---|---|---|
| 1 | ~~B1~~ ✓ | Stop deleting real words in brackets and parentheses | Major | S |
| 2 | ~~B2~~ ✓ | Better grammar must preserve instructions, recipients and meaning | Major | M |
| 3 | ~~B3~~ ✓ | Give long transcripts a real content check | Major | M |
| 4 | ~~B4 / UI C1~~ ✓ | Keep the original and let users undo AI edits | Moderate | M |
| 5 | ~~C3 / UI E1~~ ✓ | Keep populated Library inside the screen | Moderate | M |
| 6 | ~~I1~~ ✓ | Fail CI when analysis cannot actually run | Major | S |
| 7 | ~~E1~~ ✓ | Patch the confirmed vulnerable dependency; no app exploit established | Moderate | S |
| 8 | ~~C1 / UI C2~~ ✓ | Show progress and real cancellation during big model installs | Moderate | M |
| 9 | D1 (excluded) | Complete minimum-macOS, physical-input and accessibility acceptance | Moderate | M |
| 10 | ~~G1~~ ✓ | Export a big Library without blocking the UI | Moderate | M |

## Evidence and limits

- [Exact-code CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37507974701)
  passed build/tests, lint, analyzer and bundle smoke. SonarCloud was **skipped**.
  A green analyzer job does not close I1; this audit reproduced its error-masking path.
- Exact-head source-only Swift coverage is **38.34% (14,775/38,535 lines across
  192 files)**, with a 27% gate. The suite discovers 3,060 Swift cases; optional
  real-engine cases are conditional. The preceding integration recorded 109
  Python passes. Test totals are not native acceptance or speech-quality scores.
- **Fresh current-build native VM acceptance passed:** ten global-shortcut
  start/cancel cycles, display containment, no clipboard delivery on cancel,
  preserved TextEdit focus, then actual Whisper transcription of a public audio
  fixture and exactly one Smart Paste. No new consent prompt occurred in this
  preauthorized guest. Deep strict code-signature verification passed before
  and after. [Report](ui-ux-audit/2026-10-06-f30c081/desktop/report.json).
- The guest was macOS **26.6.2 (25G83)**, one 1024×768-point display, four CPUs/
  8 GB RAM, virtual BlackHole microphone. Its binary SHA256 matches the installed
  `/Applications/AudioWhisper Rebuild.app` binary. Guest synthetic keys/virtual
  audio do not establish physical microphone, physical hold modifiers or Sonoma
  14 compatibility. [Identity](ui-ux-audit/2026-10-06-f30c081/identity.json).
- Fresh Record, Library, Models, Writing, Preferences and recorder screenshots
  supplement the preceding Qwen picker/relaunch evidence. Populated Library
  overflow was reproduced twice and is C3/UI E1; see `library-sizing.json`. Initial automated
  launch produced a hidden window; reopening showed it. This observation was
  recovered, has not been established as a product defect, and is retained in
  the capture notes rather than silently discarded.
- [Real production model integration](bench/2026-10-06-qwen-integration/README.md)
  completed **128 edits**, all in one generation, and packaged offline daemon
  switching 3.5→3.8→3.5. Swift rejected 2/64 9B and 3/64 27B edits; accepted
  semantic mistakes remain. Completion is **not correctness**. This was the
  immediately preceding implementation run, not repeated during this grade.
- Fresh exact-function Swift reproductions confirm bracket/code loss, weak
  long-input content checking and negation acceptance. The negation example
  illustrates the guard, not a claim that a model produced it. See
  [reproduction evidence](audit-f30c081/README.md).
- Full-screen normal-window/HUD behavior has earlier native evidence against
  unchanged window code. Current-run physical hold, hot-plug/sleep, multiple
  displays, VoiceOver, Increased Contrast/Reduce Transparency, cold end-to-end
  latency and large-export stall timing remain explicitly unverified.
- Qwen3.5 9B is recommended for new installations; existing explicit choices are
  preserved, with Qwen3.8 mixed 3-bit optional. Parakeet v2 remains the English
  recommendation and v3 remains an option. The host user's cleanup remains off
  and shortcut remains disabled, as before; VM acceptance uses guest settings.

## A — Architecture & Design — B

The rebuild's main-actor session owns recording/import jobs (`Sources/Rebuild/RebuildSession.swift:95`), captures immutable per-session settings (`:280`), and fences late results by session ID (`:297`, `:313`). Side effects are injectable via `RebuildSessionServices` and setup via `RebuildSetupServices`. Typed RPC, provider injection and a sole transcription pipeline are healthy boundaries. Remaining architectural weaknesses are implicit model configuration propagation and two complete UI/application paths compiled into one target.

#### ~~A1~~ ✓ completed — Pass captured provider settings explicitly

- **Where:** `Sources/Services/TranscriptionPipeline.swift:117-125`; `Sources/Services/SpeechToTextService.swift:161-176`; `Sources/Rebuild/RebuildSession.swift:65-68`.
- **What's wrong:** The pipeline accepts a config containing Parakeet model and correction settings, but its speech call passes only the provider. Speech reads `TranscriptionProgress.pipelineConfig` task-local or mutable defaults instead. Current live rebuild callers correctly supply the task-local, so no wrong-model UI event is claimed; direct pipeline callers can violate the supplied config.
- **Impact:** Moderate — a reused pipeline can run a different model from the configuration it accepts.
- **Fix:** Pass typed Parakeet selection and warmup settings through the speech API. Add a focused case with config differing from current defaults.
- **Effort:** M.
- **Grade lift:** B → B+, making configuration ownership explicit end to end.
- **Simply:** Run exactly the model selected for that recording.

#### A2 — Separate dormant legacy app assembly from shared engines

- **Where:** `Sources/App/AudioWhisperEntryPoint.swift:7-9`; `Package.swift:23-39`; `Sources/App/AppDelegate*`; `Sources/ViewModels/RecordingViewModel*`; `Sources/Views/Dashboard/`.
- **What's wrong:** The executable entry selects RebuildApp, while the package still compiles the previous UI and full orchestration alongside it. Shared engines belong in both historical tests and rebuild, but duplicate app-level flows make changes/test evidence easy to apply to inactive code.
- **Impact:** Moderate — maintenance and acceptance can focus on code users never reach.
- **Fix:** Inventory callers, isolate shared services, then isolate/remove dormant app assembly in a staged change. Retain meaningful engine tests and migrate app-flow tests to rebuild.
- **Effort:** L.
- **Grade lift:** B → B+, reducing ambiguity about production ownership.
- **Simply:** Stop maintaining two versions of the app inside one build.

## B — Backend Quality — C+

The service layer has useful boundaries and safe fallbacks: injected speech providers (`Sources/Services/SpeechToTextService.swift:49`), typed/size-bounded RPC (`Sources/Managers/MLDaemonManager.swift:116`), and nonfatal cleanup failure (`Sources/Services/SemanticCorrectionService.swift:93`). Selected microphone routing is read back (`Sources/Services/Audio/AudioInputRouting.swift:67`), while Parakeet holds temporary PCM until its actual worker request finishes (`Sources/Services/ParakeetService.swift:60`). The new nonthinking first-pass and quote preservation fixes are present (`Sources/ml/correction.py:52`, `:234`), and all 128 saved production integration edits completed in one generation. These are real improvements, but deterministic transcript loss and accepted semantic changes still make the core words-delivered contract weaker than a B.

Layman: The engines work much better, but some of your words can still disappear or be rewritten incorrectly.

#### ~~B1~~ ✓ done 2026-10-06 — Preserve real parentheses, brackets and line structure

- **Where:** `Sources/Services/SpeechToTextService.swift:229-254`; `Tests/SpeechToTextServiceTests.swift`.
- **What's wrong:** The raw transcript cleaner deletes every bracketed/parenthesized span, then collapses all whitespace into a single line. Fresh pure-function reproduction: `Send the report (including taxes) to Jordan [the editor].` becomes `Send the report to Jordan .`; `let ids = [1, 2, 3]; print(ids[0])` becomes `let ids = ; print`. Both speech providers call this before optional cleanup, so a writing model cannot restore deleted context.
- **Impact:** Major — valid details and code can be lost even when optional AI cleanup is off.
- **Fix:** Replace broad regex deletion with a deliberate allowlist of acoustic/silence markers. Preserve ordinary brackets, parentheses, newlines and code punctuation. Cover nested valid content, line structure, recognized marker-only silence and ordinary bracketed text.
- **Effort:** S.
- **Grade lift:** C+ → B−, removing deterministic silent transcript loss.
- **Simply:** Keep the words in brackets instead of treating them all as noise.

**B1 validation:** 11 expected preservation failures before; 75 focused cleaner/service/integration tests pass after. Recognized acoustic markers still produce no-speech errors. Ordinary nested text, code, quotes and line breaks survive.

#### ~~B2~~ ✓ done 2026-10-06 — Protect meaning and keep cleanup from inventing content

- **Where:** `Sources/Services/SemanticCorrectionService.swift:118-129`, `:199-226`; `Sources/Models/CategoryDefinition.swift:79-162`; `.Codex/bench/2026-10-06-qwen-integration/results/qwen3.5-9b-production.delivered.jsonl:57`, `:63`; corresponding Qwen3.8 file `:57`.
- **What's wrong:** Edit-distance acceptance is not semantic protection. In the actual saved production run, 9B dropped `Do not replace -v with -d.` from the grep sentence and the guard accepted it; it also added `Best regards, [Your Name]` to an email that had no sign-off. The 27B model changed `Please let Siobhan know...` into an email directly addressed to Siobhan. These outputs passed the real Swift guard. A fresh pure guard reproduction also accepts `Do not delete the backup.` → `Delete the backup.`; that constructed example is a safeguard demonstration, not a claim either model generated it.
- **Impact:** Major — polished text may omit instructions or change who receives a message.
- **Fix:** Evaluate profile prompts against the preserved-name/number/negation/command cases; tighten prompts conservatively and verify changes qualitatively on both models. Add explicit invariant checks where reliable (protected flags, identifiers, amounts, negatives) and retain/review the original for uncertain edits. Do not treat simple token/term matching as proof of semantic correctness.
- **Effort:** M.
- **Grade lift:** C+ → B−; combined with deterministic cleaner/long-input guard fixes, toward B.
- **Simply:** Better grammar must not change what you meant.

**B2 validation:** 10 failing assertions before; 67 focused guard/service/session tests pass after. The app now prepends an integrity instruction to every profile, checks literal flags/code/identifiers, names, numbers and polarity, rejects invented email structure, and visibly reports rejected cleanup. These conservative checks can retain a useful edit unnecessarily and are not proof of semantic equivalence; B4 supplies comparison/recovery.

#### ~~B3~~ ✓ done 2026-10-06 — Compare content for long corrections

- **Where:** `Sources/Services/SemanticCorrectionService.swift:208-226`.
- **What's wrong:** For >4,000 characters, the safety guard compares only length. Fresh exact-function reproduction: 3,600 characters of `alpha ` changed to equally long `bravo ` is rejected, but 5,400 characters of the same unrelated rewrite is accepted. This is a current guard defect, not an observed model generation.
- **Impact:** Major — long dictation loses the content-change safeguard applied to short dictation.
- **Fix:** Use a bounded chunk/token content comparison with an explicit runtime budget. Fail closed to the original when the comparison is inconclusive, and distinguish rejected cleanup from applied cleanup. Cover unrelated same-length rewrites, long truncation and small legitimate corrections.
- **Effort:** M.
- **Grade lift:** C+ → B−; together with B1/B2, toward B.
- **Simply:** Long transcripts need the same protection as short ones.

**B3 validation:** Three content-preservation assertions failed before; all 48 focused guard/service tests pass after. Long corrections now compare a bounded changed character span or token edit distance, and retain the original when the size/operation budget is inconclusive. Same-length unrelated rewrites fail, small long edits pass, and a 120k-character adversarial input stays within the test budget.

#### ~~B4~~ ✓ done 2026-10-06 — Retain the original so cleanup can be undone

- **Where:** `Sources/Services/TranscriptionPipeline.swift:9-16`, `:71-97`; `Sources/Rebuild/RebuildSession.swift:305-311`; `Sources/Models/TranscriptionRecord.swift:11`.
- **What's wrong:** The pipeline returns only final text on successful cleanup; session, clipboard and history then keep only that final text. Temporary audio is removed after success. An original recognized version cannot be recovered or compared if the model altered its meaning.
- **Impact:** Moderate — users cannot undo unwanted AI edits without recording/importing again.
- **Fix:** Carry original/final text and correction status separately. Offer Compare/Use original, persist the pair only when local history is on, and migrate SwiftData compatibly while preserving history-off privacy.
- **Effort:** M.
- **Grade lift:** C+ → B−; complements B1-B3 by making editing reversible.
- **Simply:** Give you an Undo button for AI wording changes.

**B4 validation:** Five original-propagation/recovery assertions failed before wiring the pipeline and live history path. All 68 focused pipeline/session/delivery/model checks pass after, including restore without another automatic delivery, one saved record/usage event, history-off privacy and a real SQLite reopen retaining both versions. A disposable SQLite created with the f30c081 model migrated through the new model in module AudioWhisper: the existing UUID/text remained, its original field was nil, and a new pair survived reopening. The workspace offers Compare with original/Use original; Library exposes Original transcript/Copy original. Native Library Original transcript/Copy original were exercised on the final package; restoring the current session is covered by live pipeline/session integration with fixture services.

## C — Frontend Quality — B

The rebuild has a recognizable shared theme and conventional native controls
(`Sources/Rebuild/RebuildWorkspace.swift:5`, `:97`, `:109`). One observable
session owns recording admission and delivery, while Library pages, debounced
search and committed history revisions keep state bounded and current
(`RebuildLibraryView.swift:6`, `:89`, `:133`). Fresh native screenshots at the
870×620-point minimum (except populated Library) show clear navigation, setup requirements, the actual
shortcut recorder and readable Qwen cost guidance. Compare/restore-original is
tracked under B4 and UI C1 rather than counted twice here.

#### ~~C1~~ ✓ completed — Connect correction-install progress and cancellation

- **Where:** `Sources/Rebuild/RebuildWritingView.swift:54-77`, `:92`; `Sources/Services/MLXModelManager+Downloads.swift:21-82`, `:105-117`; `Sources/Rebuild/RebuildSession.swift:365-382`.
- **What's wrong:** Writing displays only “Installing…” for 6.0/12.7 GB downloads, without reading available structured progress or offering cancellation. Generic retry copy hides actionable model-manager errors. Maintenance blocks recording/import while the install runs. This is source-confirmed behavior; no slow-network duration is claimed.
- **Impact:** Moderate — an optional large download leaves users unsure whether the app is working and unable to get back to recording.
- **Fix:** Display structured stage/byte progress and actual failure details. Own the download task/process so cancellation ends it and releases maintenance, while retaining resumable partial files. Verify cancel/retry on a small disposable download.
- **Effort:** M.
- **Grade lift:** B → B+ for setup feedback, alongside C2 and continued native acceptance.
- **Simply:** Show the download moving and let you stop it.

#### ~~C2~~ removed by user direction — Name mapped apps clearly and refresh app choices

- **Where:** `Sources/Rebuild/RebuildWritingView.swift:118-151`; `Sources/Managers/AppCategoryManager.swift:74`.
- **What's wrong:** Stored profile rows and Reset accessibility labels use raw bundle IDs. The app picker snapshots running apps on view creation, without observing launch/termination or exposing Refresh. Populated mappings were not exercised in this fresh VM pass.
- **Impact:** Moderate — choosing and confirming an app-specific writing style takes avoidable guesswork.
- **Fix:** Resolve friendly names/icons with ID fallback; refresh from workspace notifications or an explicit action, and name the app in accessibility actions. Keep the ID as optional secondary detail.
- **Effort:** S.
- **Grade lift:** B → B+ for profile clarity, alongside C1.
- **Simply:** Show “Mail” and notice an app you just opened.

#### ~~C3~~ ✓ done 2026-10-06 — Keep populated Library from resizing the window off screen

- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:23-88`; `Sources/Rebuild/RebuildWorkspace.swift:46`; `Sources/Rebuild/RebuildApp.swift:109-121`.
- **What's wrong:** Twice in the current native guest, selecting Library after resetting Record to 870×620 changed the native window to 870×1,179 on a 1024×768-point screen. Bottom content and sidebar status moved below the display. No page-change frame mutation exists. The unbounded Library layout propagating fitting size through the default hosting controller is a source-supported mechanism inference; the off-screen growth itself is reproduced.
- **Impact:** Moderate — opening saved transcripts can leave part of the window unreachable on smaller screens.
- **Fix:** Make the native window own its size, bound the Library list viewport, and verify the hosting sizing policy instead of merely shrinking an already oversized frame. Exercise page transitions with populated/empty/loading Library, long transcripts and minimum-size windows; assert the full frame remains inside the visible display.
- **Effort:** M.
- **Grade lift:** B → B+, by fixing a confirmed native layout failure; C1/C2 remain.
- **Simply:** Opening history should not stretch the app below your screen.

**C3 validation:** A native hosting regression with 55 long transcripts reproduced a 870×1185 window and 1153-point content minimum under the default sizing policy. The workspace now disables content-driven hosting sizing and retains the native window's explicit minimum and user-selected bounds. All 8 layout/library tests pass after: five page transitions, populated/empty Library and the recorder. Library receives a real injected SwiftData store for layout coverage. Final packaged VM measurements repeat the two original Library repro attempts at 870×620, all five pages, a 55-long-record fixture and a genuine no-results search; each retains contained 870×620 bounds. See the new evidence report.

## D — Testing & Reliability — B

The 3,060 discovered Swift cases and 109 main Python cases include meaningful permission coalescing, stale setup, cancellation, failed history delivery and quote/template regressions (`Tests/RebuildSetupTests.swift:42`, `Tests/RebuildDeliveryIntegrationTests.swift:96`, `Tests/test_correction_sanitize.py:131`). The old audit's “only one speech sentence / no representative benchmark” finding is substantially resolved by the Oct5 fixed 48-natural-clip corpus plus noise/silence/long-form checks and Oct6 128 production cleanup edits (`.Codex/bench/2026-10-05-m5-pro/README.md:33`, `.Codex/bench/2026-10-06-qwen-integration/README.md:35`). Main CI still skips real engines unless `RUN_E2E=1`; the latest nightly is green for default-branch `f3adb17`, not current rebuild HEAD. Native Tahoe guest acceptance and current model settings evidence exist, while important physical/minimum-OS scenarios remain explicitly incomplete.

#### D1 excluded by user direction — Close the supported native compatibility matrix [FE]

- **Where:** `scripts/vm/README.md:10`, `.Codex/macos-vm-validation.md:85`, `docs/rebuild.md:86`.
- **What's wrong:** Evidence gap, not a reproduced failure: Sonoma 14 minimum support, physical hold keys/microphone changes and sleep, multiple displays/Spaces, and VoiceOver do not have completed native acceptance. The fresh current-build Tahoe recording/paste run and Qwen settings do not prove these cases.
- **Impact:** Moderate — the app promises more machines/input conditions than have been demonstrated.
- **Fix:** Provision the minimum-OS guest; extend disposable VM runs for available scenarios, then retain a distinct physical-device/hold and VoiceOver checklist with build identity and evidence. Reuse persistent signing and permissions.
- **Effort:** M
- **Grade lift:** B → B+, by closing product compatibility uncertainty.

#### ~~D2~~ ✓ completed — Ratchet coverage near its demonstrated baseline [both]

- **Where:** `.github/workflows/ci.yml:158`, `scripts/coverage-gate.py`.
- **What's wrong:** Exact-head CI reports source-only Swift coverage of **38.34% (14,775 / 38,535 lines, 192 files)** while the enforced floor remains 27%. The gate can lose more than eleven percentage points before failing. This is not dependency-inflated coverage and not proof every uncovered line is critical.
- **Impact:** Moderate — a substantial regression in exercised code can stay green.
- **Fix:** Ratchet from repeated clean-runner measurements with a small justified margin; prioritize focused active-session, hardware preparation and delivery regressions rather than cosmetic assertions or impossible headless snapshot checks.
- **Effort:** S
- **Grade lift:** B → B+, by protecting the existing test investment.

## E — Security — B−

Controls are substantial: local/offline inference, pinned shipped Qwen/Parakeet revisions, frozen Python setup, checksum-verified uv, private transcript-bearing stderr, and immutability/signature regressions (`Sources/ml/loader.py:57`, `Sources/Services/UvBootstrap.swift:189`, `Sources/Managers/MLDaemonManager+Process.swift:79`, `scripts/prepare-uv.sh:22`). Representative-file TOFU is honestly bounded and is not full weight authentication (`Sources/Utilities/DiskMutationSerializer.swift:100`, `docs/adr/0006-model-integrity.md:52`). A newly reviewed high-severity fsspec advisory applies to the CURRENT locked version; normal app reachability was not established. Public release signing requirements also remain optional in the upload command.

#### ~~E1~~ ✓ completed — Remove the known vulnerable fsspec version

- **Where:** `Sources/Resources/uv.lock:155`, `Sources/Resources/pyproject.toml:6`, `Sources/ml/loader.py:57`.
- **What's wrong:** Current rebuild locks fsspec **2025.7.0**, inside the affected range `>=0.9.0,<2026.6.0` of [GHSA-27vj-qcqg-25rc / CVE-2026-104851](https://github.com/advisories/GHSA-27vj-qcqg-25rc). Malicious reference/Kerchunk JSON can execute Python in the dependency. The app has no direct fsspec, `ReferenceFileSystem`, reference-protocol or xarray call in Sources; local model paths are used. This confirms vulnerable shipped code, **not a demonstrated recording or model exploit**.
- **Impact:** Moderate — a known risky dependency remains in the runtime, although the vulnerable feature is not an established app input path.
- **Fix:** Resolve a targeted fsspec update to at least 2026.6.0, preserve other compatible ML pins, verify the frozen lock, download/cache resolution and both Qwen/Parakeet offline loads. Record the bounded reachability assessment; avoid a broad unrelated runtime upgrade.
- **Effort:** S
- **Grade lift:** B− → B, by removing a confirmed advisory from the actual shipped lock.

#### E2 — Enforce distribution checks before public upload

- **Where:** `Makefile:87`, `scripts/build.sh:478`, `scripts/build.sh:495`.
- **What's wrong:** `make release` invokes preview-capable `build.sh` without `--notarize`, then uploads. It can publish a local/ad-hoc signed bundle. No current bad public release is alleged; the README says this fork publishes none.
- **Impact:** Moderate — the release command can distribute an app that fails normal macOS trust checks.
- **Fix:** Separate local-preview and public-release commands; require Developer ID, accepted notarization, successful stapling and Gatekeeper assessment before uploading.
- **Effort:** M
- **Grade lift:** B− → B+, in combination with E1, by enforcing a sound distribution boundary.

## F — Dependencies & Tech Currency — B

`Package.resolved` pins all three Swift packages, the Python lock has hashes, CI verifies lock consistency, and weekly Dependabot covers Swift, Actions and uv (`.github/dependabot.yml:3`, `Sources/Resources/pyproject.toml:25`). The installed MLX/Transformers versions have actual Qwen3.5/3.8 production inference evidence; a newer-version number alone is not a defect. The current fsspec advisory lowers this grade (tracked once as E1), and the shell-managed uv pin still lacks an update/advisory signal.

#### F1 — Monitor the bundled uv tool pin

- **Where:** `scripts/prepare-uv.sh:7`, `.github/dependabot.yml:3`.
- **What's wrong:** Dependabot package ecosystems do not watch `uv_version="0.12.23"` and its two archive checksums in the shell script. No vulnerability in that uv version was established in this audit.
- **Impact:** Moderate — runtime setup tooling can miss reviewed maintenance and security updates.
- **Fix:** Centralize version/checksum metadata and add a scheduled official-release/advisory check that proposes reviewed updates, retaining checksum verification and packaging validation.
- **Effort:** S
- **Grade lift:** B → B+, with E1 resolved, by covering the remaining manually maintained tool boundary.

## G — Performance & Scalability — B

Audio memory behavior is deliberate: WhisperKit uses incremental loading (`Sources/Services/LocalWhisperService.swift:192`) and Parakeet reads bounded overlapping chunks (`Sources/ml/parakeet.py:69`). Library reads are paged, and replacing a loaded MLX repository clears the old engine cache (`Sources/ml/loader.py:30-42`). The new first-pass thinking fix eliminates the prior extra-generation waste; 128 recorded integration edits confirm one pass each. The chosen 9B and mixed 27B options carry honest hardware-specific speed/memory guidance (`Sources/Services/MLXModelManager.swift:75-85`). This audit did not measure fresh UI stalls or combined cold speech/cleanup latency; the integration timing is explicitly not a controlled speed comparison.

Layman: Short edits are fast; cold startup and big library exports still need work.

#### ~~G1~~ ✓ completed — Keep large Library exports off the UI actor

- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:140-170`; `Sources/Stores/DataManager+Fetching.swift:42-65`; `Sources/Stores/DataManager.swift:114`.
- **What's wrong:** The export fetch loop runs on the main actor with no suspension between pages. Formatting, writes, synchronize and replacement execute there too. Pages bound memory but do not let the UI respond. The blocking work is source-confirmed; a fresh large-library freeze duration was not measured.
- **Impact:** Moderate — a large history export can delay clicks, cancellation and progress feedback.
- **Fix:** Move fetch/format/stream writes to an appropriate isolated model actor/worker using transferable data. Keep save panel/status on the UI actor and add cancellation/error propagation.
- **Effort:** M.
- **Grade lift:** B → B+, keeping large exports responsive while preserving paging.
- **Simply:** Export history without freezing the window.

#### ~~G2~~ ✓ completed — Schedule cold writing-model warmup around the sequential worker

- **Where:** `Sources/Services/SpeechToTextService.swift:169-185`; `Sources/Managers/MLDaemonManager.swift:94-98`; `Sources/ml/rpc.py:103-117`.
- **What's wrong:** Swift launches warmup concurrently, but Parakeet and correction warmup share a Python worker that dispatches one request at a time. Warmup can queue before recognition; the raw result also explicitly waits for warmup. This is not parallel model execution. No new numeric cold-start penalty is claimed.
- **Impact:** Moderate — enabling cleanup can delay the first recognition result before correction itself begins, especially with the larger option.
- **Fix:** Measure cold/warm combined workflows, then prewarm during idle setup or prioritize recognition ahead of warmup. Consider a separate worker only if measured benefit justifies additional memory. Update comments to match actual scheduling.
- **Effort:** M.
- **Grade lift:** B → B+, aligning work scheduling with the real daemon execution model.
- **Simply:** Load the editor at a time that does not hold up hearing your words.

## H — Documentation & Onboarding — B−

Rebuild notes, six ADRs, reproducible benchmark artifacts and the VM guide give useful architecture and evidence boundaries. The new Qwen troubleshooting paragraph is accurate (`README.md:168`) but contradicts the untouched cleanup setup paragraph and older developer launch advice (`README.md:81`, `CONTRIBUTING.md:84`). These are concrete wrong instructions, not a lack of prose.

#### ~~H1~~ ✓ completed — Reconcile setup and development instructions

- **Where:** `README.md:81`, `README.md:123`, `README.md:138`, `CONTRIBUTING.md:60`, `CONTRIBUTING.md:84`, `CONTRIBUTING.md:298`.
- **What's wrong:** README still sends correction selection to Models & setup and calls Qwen3 1.7B the default; the active location is Writing profiles with Qwen3.5 9B recommended. CONTRIBUTING says Swift 5.9, bare `swift run`, repeated permissions “normal,” and lists removed Alamofire/HotKey/API-key components. These conflict with current build requirements and persistent signed development packaging.
- **Impact:** Moderate — readers can choose the wrong settings or repeat the permission churn the rebuild repaired.
- **Fix:** Update the current screens/default, Swift 6.2 tooling and architecture; make `make run` with persistent signing the native UI workflow and reserve bare Swift CLI for build/tests. Correct old Dashboard/Space directions.
- **Effort:** S
- **Grade lift:** B− → B, by making the main entry instructions dependable.

#### ~~H2~~ ✓ completed — State setup network needs precisely

- **Where:** `README.md:128`, `CONTRIBUTING.md:54`, `Sources/Services/UvBootstrap.swift:178`, `Sources/Services/UvBootstrap.swift:189`.
- **What's wrong:** “Network access only to download models” omits first-time Python/runtime and PyPI package downloads. Offline transcription itself is supported; the setup promise is incomplete.
- **Impact:** Moderate — users on restricted/offline networks receive the wrong preparation expectations.
- **Fix:** Distinguish initial runtime, dependency and model downloads from subsequent local inference; link the already explicit pinned/TOFU verification boundaries rather than calling every file cryptographically authenticated.
- **Effort:** S
- **Grade lift:** B− → B, by accurately describing privacy and offline readiness.

## I — Developer Experience & Tooling — B

Strict SwiftLint/mypy, independent CI jobs, fail-closed coverage artifacts, Xcode environment recovery and packaged resource checks are effective (`.github/workflows/ci.yml:214`, `scripts/lib/xcode-env.sh`, `scripts/build.sh:466`). Exact-head CI completed, but a green analyzer job is weaker than it appears because its tool failures are swallowed. Build output protection does not cover the actual installed destination replaced by `make run`.

#### ~~I1~~ ✓ completed — Make analyzer execution errors fail CI

- **Where:** `.github/workflows/ci.yml:542`, `.github/workflows/ci.yml:557`, `.github/workflows/ci.yml:594`.
- **What's wrong:** Analyzer stderr is discarded, and `| tee analyze.txt || true` masks tool failure. The follow-up gates interpret an empty report as zero findings. Fresh read-only reproduction with a nonexistent compiler log returned exit 1 and zero stdout; this exact CI structure converts that failure into apparent success. No claim is made that the current successful run actually failed analysis.
- **Impact:** Major — CI can certify analysis that never ran.
- **Fix:** Retain stderr and inspect the analyzer exit/report validity; distinguish a completed rule-violation report from compiler-log/indexing execution failure. Add a small missing-log/error gate regression.
- **Effort:** S
- **Grade lift:** B → B+, by making this green signal meaningful.

#### ~~I2~~ ✓ completed — Protect the installed app during replacement

- **Where:** `Makefile:34`, `scripts/build.sh:158`.
- **What's wrong:** Build packaging guards its output path, but `make run-dev` immediately dittos into `/Applications/AudioWhisper Rebuild.app` without ensuring that destination is stopped. A live process can retain old code while signed resources beneath it are replaced. Permission churn from this exact case was not reproduced.
- **Impact:** Moderate — ordinary development installs can create inconsistent running app resources.
- **Fix:** Add a scoped install helper: stop/wait for the exact target, stage and validate the complete signed bundle, replace it safely, then relaunch with the same persistent identity. Reject unexpected paths.
- **Effort:** S
- **Grade lift:** B → B+, by carrying safe packaging through installation.

## Changes from the prior audit

The old cleanup-model guidance item is substantially resolved: current native
Writing shows friendly names, the recommendation, speed/memory and separate
download size. The representative-benchmark gap is retired after the Oct5
speech corpus and Oct6 production cleanup suite. Thinking-template and quote
sanitizer defects are fixed and have actual packaged inference evidence.
Broader semantic correctness, native compatibility and the analyzer
gate remain open. The newly verified dependency advisory explains the lower
security/dependency assessment; no newly demonstrated app exploit is claimed.
Historical reports retain their original IDs and completion records.
