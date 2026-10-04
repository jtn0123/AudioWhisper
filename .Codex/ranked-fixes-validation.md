# Ranked fixes and validation — 2026-10-04

User-selected ranks: **1–9 and 14–17**. Worktree: `/Users/justin/.t3/worktrees/AudioWhisper/native-v2`, branch `rebuild/native-v2`. Original checkout/app data are separate.

Later recording/permission follow-up: implementation `cb3bf44`, `c3646e5`, analyzer annotation `4d12ddd`. See [current breakout and verification boundaries](recording-permission-fixes.md). The current persistent-identity bundle is awaiting initial OS microphone consent; new live tests and Accessibility re-registration are incomplete. The results below retain their original build identities.

Final code/build source: **b47fe8e798ab5176afe8606e6327f43c1f11ca46**. Native shortcut, search and accessibility checks first ran on predecessor `3f66210`; the final bundle adds bounded Parakeet inference and neutral offline error advice. CI follow-ups `b81723e` and `98d77e6` resolve the runner test-binary layout and portable Python coverage paths. Report commits leave packaged behavior unchanged.

| Rank | Report ID | Plain-language result and status | Main commit |
|---|---|---|---|
| 1 | F1 | Updated the shortcut library; custom/cleared/disabled shortcuts work in the packaged checks below. | 2030c36 |
| 2 | D3 | **Partially verified:** filled in the native test checklist; permission, physical-key, full-screen and hardware rows remain open. | This report |
| 3 | B3 | Removed an unsafe memory-write pattern from audio decoding. | cbd5999 |
| 4 | D2 | Eight integration tests now check the rebuild's real clipboard, history and usage delivery wiring. | 513abc2 |
| 5 | UI I1 | Record shows your shortcut or explains why it is off/missing, with a direct Configure link; the menu uses the same key. | 2ae5423 |
| 6 | G1 | Audio preparation reads small pieces, responds to cancellation and removes unfinished output safely. | 4d22125 |
| 7 | F3 | Updated the Whisper engine and enabled reading long files in pieces, with matching short-speech results. | 8ddd67e |
| 8 | UI G1 | Measured long-file memory/cancellation and fixed the reproduced Parakeet long-file allocation failure. | 44d2442, a39eb1e, b47fe8e |
| 9 | UI D1 | Editors and repeated actions now say which transcript/profile they affect for assistive tools. | afc4807 |
| 14 | I1 | Development packaging reuses cached work: 6–9 seconds in measured debug runs, with complete resources/signing. | 772ee27 |
| 15 | G2 | The waveform avoids copying every small audio slice; the repeated-call benchmark is about 2.7× faster. | 9858868 |
| 16 | UI E1 | Library distinguishes No matching transcripts from an empty library and offers Clear search. | 2f943b7 |
| 17 | I2 | Sonar reuses the primary CI coverage reports and verifies their commit/run/content instead of rerunning tests. | 3f66210 |

Ranks 10–13 (E2, H2, F2, H1) were outside this batch.

## Local validation

- Full parallel coverage suite succeeds: **3,045 discovered Swift cases**. Opt-in engine/performance cases remain gated in the standard suite; they were run separately below. Sources-only line coverage **38.15% (14,550/38,142 lines, 190 files)**; 27% ratchet passes.
- **92 Python application tests**, **10 coverage-artifact tests**, strict Python typing of 11 source files, and strict SwiftLint pass.
- New delivery integration cases cover normal/corrected delivery, correction fallback, failed history save retaining clipboard/usage, canceled owned/borrowed audio, failed retry and retry cancellation.
- PCM regressions cover short-file sample parity, resampling, cancellation/partial cleanup, empty audio, malformed input and preserving an existing destination. Related daemon leases and session/setup tests pass.
- Before the final Parakeet follow-up, real-engine run: **4 tests pass** — Parakeet speech, Whisper cold/warm speech and load verification, exact full-file/incremental short-speech parity, and actual MLX writing correction. Public fixture: The quick brown fox jumps over the lazy dog. After the chunking fix, the short Parakeet fixture passes again; 22 focused Swift service/delivery tests and all 92 Python application tests pass. The final remote suite covers the final source.
- Swift LCOV is exported from the same test binary/profdata that produced the coverage JSON. Both real Swift and Python XML reports pass provenance creation/verification. Missing reports, empty/no-app-source reports, wrong commits/runs/attempts/types, and altered content are rejected.
- Workflow structure passes actionlint with shellcheck disabled. Full actionlint reports only the existing ls/globbing/unquoted-exit warnings in unchanged workflow steps.
- Debug packaging passed twice: **9.05 s** then **6.05 s** wall time (Swift build 4.42 s on first run). Host binary is arm64; complete signature, required bundles/English shortcut localization and headless diagnostics pass. `--debug --notarize` is rejected before packaging; `make build` retains universal arm64/x86_64 requirements.

## Long-file and waveform measurements

[Machine-readable results](ranked-fixes-validation/performance.json). Generated **three-hour, 16 kHz mono Float32 WAV**, 172,800,000 samples. Each loading mode ran in a separate XCTest process, sequentially. Peak RSS includes XCTest overhead and file preparation, not model inference.

| Loader | Process peak RSS | Largest delivered chunk | Preparation time |
|---|---:|---:|---:|
| PCM whole-file Float32 + Data reference | 1,413,300,224 B (1.32 GiB) | 172,800,000 frames | 0.197 s |
| Production streaming PCM converter | 31,096,832 B (29.7 MiB) | 4,096 frames | 0.251 s |
| Argmax full-file loader | 1,989,820,416 B (1.85 GiB) | 172,800,000 frames | 0.384 s |
| Argmax incremental loader | 62,390,272 B (59.5 MiB) | 480,000 frames | 0.284 s |

Streaming PCM peak is approximately **98% lower** than the whole-file reference; incremental Whisper loading peak is approximately **97% lower** than full-file loading. The PCM reference reproduces the former allocation shape, not a benchmark of the original exact decoder. This synthetic fixture is a loading benchmark, not speech-accuracy or total-app OOM proof.

Cancellation after work starts completes in **0.328 ms** for PCM, with the partial output removed, and **0.024 ms** for incremental Whisper consumption. These are preparation/consumption measurements, not model cancellation latency.

A native **30-minute repeated public-speech import** then exposed an actual Parakeet failure: its full-input attention path requested a **32,402,160,032-byte GPU allocation**, over the device limit. The UI also incorrectly advised checking an internet connection/API key for this local model. Commit `b47fe8e` reads and generates overlapping **120-second windows with 15-second overlap**, merges aligned tokens using the vendor logic, and removes that misleading advice. Four Python regressions cover short input, bounded long reads/tail/offsets, merge fallback and missing input.

The same actual model/30-minute fixture now succeeds in **33.13 seconds**, producing **5,778 words**. Python process peak RSS is **851,755,008 bytes (812 MiB)** and MLX reports **3,221,373,732 bytes (3.0 GiB)** peak. These are separately measured host/GPU metrics; they are not added or compared directly to the previously refused single allocation. Model weights, per-window scratch and accumulated transcript tokens still consume memory. [Inference results](ranked-fixes-validation/parakeet-long-inference.json), [failed native run sampling](ranked-fixes-validation/parakeet-long-failure-rss.json).

Final native cancellation returns to idle with no transcript/usage delivery. The same final bundle then imports the long fixture successfully; the copied/transcript state is observed by **33.57 seconds** after starting (an observation bound, not an exact completion timestamp). The existing daemon task continues until completion; its PCM lease remains present during that work and is deleted afterward. This protects the worker's input and does not claim immediate GPU cancellation.

Waveform benchmark: 10,000 downsampling calls, **0.0958 s** direct buffer versus **0.2579 s** copied slices (~2.7× faster in this debug benchmark). RMS/remainder and empty/short/invalid-target behavior match the previous implementation.

## Final bundle and native acceptance

The final universal build completed in **82.85 s** and passes strict/deep signature, Info.plist, both architecture and shortcut localization checks. Native Preferences reports the exact packaged hash **b47fe8e**. Predecessor `3f66210` delivered the short public speech fixture. Final `b47fe8e` completes the 30-minute native import and cancellation checks; strict/deep signature still verifies and no bundled bytecode/PCM lease remains after work completes. [Final native results](ranked-fixes-validation/native-long-acceptance.json). Test preferences (shortcut off, original ⇧⌘Space, history off) were restored; the disposable editor transcript was cleared and the app left idle; no transcript was saved in Library. The short fixture increased usage from 4 sessions/39 words to 5 sessions/48 words. A failed import and canceled import leave those totals unchanged. Final successful 30-minute native import delivers 5,778 words, advancing usage once to 6 sessions/5,826 words, with Library saving still off. An OS consent grant is not simulated by unit tests. Physical key presses, VoiceOver speech, two-input comparison and actual hardware/sleep interruptions require separate evidence.

| Scenario | Result |
|---|---|
| Final universal bundle/signature/resources | Pass: x86_64 + arm64; strict/deep codesign; English shortcut resources |
| Cold launch/readiness/consent | Final launch/readiness pass: correctly blocked for microphone; no automatic request. Predecessor explicit request awaited the OS grant; final build consent has not been granted. |
| Start/cancel repeat and stop/transcription | Follow-up: microphone granted; four live start/cancel cycles succeed, fifth start fails with CoreAudio error 1852797029. Further repeat attempt hangs during input-node initialization. Stop/transcription remains unverified. |
| Configure shortcut / custom / cleared / disabled display | Pass on predecessor `3f66210` (UI unchanged in final): ⌥⇧⌘R captured/displayed; cleared and off explained; original preferences restored |
| Menu equivalent while open | Unperformed: status-bar native control unavailable; source binding implemented; no physical event proof |
| Writing/transcript contextual AX labels | Pass on predecessor `3f66210` (UI unchanged in final) for transcript, profile action and instructions; full VoiceOver and populated Library labels unperformed |
| Filtered-empty Library / Clear search | Pass on predecessor `3f66210` (UI unchanged in final), native empty Library: query shows No matching transcripts; Clear search restores Room for your next idea; history returned off |
| Native mounted Library save | Unperformed; real isolated live-assembly SwiftData/observation tests pass |
| Smart Paste captured destination | Follow-up: user approved and authenticated Accessibility; Settings shows exact rebuild entry enabled, but app's actual AX trust check remains false after relaunch. Smart Paste test remains unperformed; test toggle is on and could not be restored after native-control failure. |
| Normal window / recorder over full-screen | Incomplete: entered Finder full screen and reopened the final app/Preferences; Mission Control/Dock inspection timed out, so actual Spaces placement is not certified. Finder was restored to normal mode. Recorder overlay remains unperformed without microphone consent. Prior evidence/tests are not substituted. |
| Final native long-file cancel / late delivery / PCM cleanup | Pass: returns to idle; 5 sessions/48 words unchanged; no late transcript; owned PCM removed after daemon completion |
| Final native long-file success | Pass: 5,778-word transcript/copied state observed by 33.57 s; usage increments once to 6 sessions/5,826 words; no Library save; PCM removed; signature remains valid/no bundled bytecode |
| Cold relaunch retains consent | Pass in follow-up on unchanged b47fe8e: microphone allowed and ready after cold relaunch, no repeated consent prompt during attempted cycles. |
| Physical shortcut/hold and full VoiceOver navigation | Unperformed |
| Two distinguishable physical microphones | Unperformed: one attached input |
| Actual input disconnection / sleep-wake capture | Unperformed: no external input available; host sleep not induced |

## Remote CI and sync

[Initial code CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37218545306) passed all Swift tests, Python/lint and the **38.18% (14,598/38,230)** coverage gate, then failed the newly added export step: native SwiftPM names its bundle `AudioWhisperPackageTests`, while local XCBuild names it `AudioWhisperTests`. CI-only fix `b81723e` discovers exactly one complete test bundle and adds both-layout/missing/ambiguous regressions. The Python report also now uses a project-relative source root before hashing, so its macOS producer path is not carried into the Linux scanner. Superseded CI runs were canceled after their failure was diagnosed. [Final code CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37219846937) tests `b47fe8e` and **passes**: build/full Swift suite, coverage export/gate, Python/lint, SwiftLint analyzer and universal bundle smoke/packaged diagnostics. [Final job results](ranked-fixes-validation/ci-result.json). Sonar retains its former master push/PR scope, so its scan is skipped on this rebuild branch. Both primary producer jobs pass: final Swift run discovers 3,045 cases and passes the **38.18%** Sources-only line-coverage gate. Their downloaded Swift/Python artifacts also verify against the final commit/run/attempt and content hashes ([provenance evidence](ranked-fixes-validation/ci-coverage-provenance.json)). The Python XML source root is portable (`.`). Local fail-closed checks pass; a master/PR Sonar consumer run remains a remote integration boundary.

All selected implementation commits and these reports are committed and pushed on `rebuild/native-v2`; the original checkout is clean and unchanged. The final app bundle remains the tested `b47fe8e` source, since these last commits only record evidence.

The historical B reports retain their audit grades; implementation completion is tracked by IDs and this validation report. These changes are a local development preview, not Developer ID/notarized distribution acceptance.
