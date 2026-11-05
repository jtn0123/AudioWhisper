# Codebase Grade Report

**Project:** AudioWhisper (fork `jtn0123/AudioWhisper`, branch `feat/aurora-waveforms` + uncommitted Aurora work)
**Audited:** 2026-11-03
**Stack:** Swift 6.2 / SwiftUI + AppKit macOS menu-bar app (live UI = `Sources/Rebuild`), SwiftData, WhisperKit (Core ML), embedded uv-managed Python JSON-RPC daemon (parakeet-mlx, mlx-lm)

**Measured:** 3,297/3,297 tests pass · SwiftLint 0 violations · clean build · coverage 55.6% overall (Rebuild 87.6%, Stores 89.5%, Services 77.9%, Managers 75.3%, App 60.8%, Views 26.5%)

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Architecture & Design | C+ | 4 |
| B | Backend Quality | B | 6 |
| C | Frontend Quality (UI/UX) | C+ | 12 |
| D | Testing & Reliability | B− | 6 |
| E | Security | B | 5 |
| F | Dependencies & Tech Currency | B+ | 3 |
| G | Performance & Scalability | B− | 4 |
| H | Documentation & Onboarding | B− | 3 |
| I | Developer Experience & Tooling | B+ | 4 |
| **Overall** | | **B−** | **47** |

**Top 5 highest-leverage fixes:** ~~C1, A1, D1, B1, E1~~ — all done 2026-11-04 (uncommitted)

---

## A — Architecture & Design — C+

The rebuild has a clean core: one `RebuildSession` owns recording, delivery and setup, and views never record or paste themselves. But about 34% of the Swift source (~12,700 of 36,918 lines, ~75 files) is the legacy shell that production never launches. `AppDelegate()` is only constructed in tests (`Tests/AppDelegateExtensionTests.swift:16`); production runs `RebuildApp.main()` (`Sources/App/AudioWhisperEntryPoint.swift:10`) with `RebuildDelegate`. Live code still reaches into the legacy folders (`RebuildRecorderView.swift:28` → `Views/.../WaveformContainer` → `App/AppStatus`), and there are 19 singletons with 185 `.shared` call sites.

#### ~~A1~~ ✓ done 2026-11-04 — Delete the unreachable legacy shell
- **Where:** `Sources/App/AppDelegate*.swift` (6 files, 831 lines), `Sources/Views/Dashboard/*` (22 files), `Sources/Views/ContentView*`, `WelcomeView`, `Sources/Views/Transcription/*`, `Sources/ViewModels/*`, `Sources/Managers/Windows/{DashboardWindowManager,HistoryWindowManager,WelcomeWindow,WindowController,WindowCoordinator}.swift`, `ErrorPresenter`, `NotificationCoordinator`, `HotKeyManager`, `KeyboardEventHandler`, `AudioRecorder`, `SoundManager`, `RecordingSetupState`, `ProviderSettingsState`, `MenuBarIcon`; plus `InkRippleView` and `UnifiedModelRow`, which nothing references.
- **What's wrong:** docs/rebuild.md says these "remain compiled temporarily", but nothing in `Sources/Rebuild` reaches them. They inflate build time and the test count, drag Views coverage down to 26.5%, and keep features alive in two places (the Aurora picker was added to both `DashboardVisualsView` and `RebuildRecordingTuningView`).
- **Fix:** Do A2 first. Then delete the files and their tests in staged commits (App/AppDelegate → Dashboard → Windows managers → ViewModels), running `make test` and `scripts/lint.sh` after each. Lower the analyzer's `unused_declaration` baseline to match.
- **Effort:** L
- **Grade lift:** C+ → B (removes a third of the codebase and its duplicate feature surface)

#### A2 — Move the live shared UI out of the legacy folders
- **Where:** `Sources/Views/Components/Waveform/**` (used by `RebuildRecorderView.swift:28`), `Sources/App/AppStatus`, `AppSetupHelper` and `PressAndHoldKeyMonitor` (used by `RebuildDelegate`).
- **What's wrong:** Live code depends on folders that otherwise hold dead code, so it is unclear what can be deleted.
- **Fix:** Create `Sources/SharedUI/` (waveforms, AppStatus) and move the live pieces there. Afterwards, anything left in `Views/` and `App/` that isn't reachable can be deleted (A1).
- **Effort:** M
- **Grade lift:** part of A1's lift (makes A1 safe)

#### A3 — Split `RebuildSession` state
- **Where:** `Sources/Rebuild/RebuildSession.swift:8-65` (~45 stored properties shared across 5 extension files)
- **What's wrong:** One observable object holds the state for recording, verification, installation, maintenance and meetings. Every change invalidates every observer, and the extension files are only split by file, not by state.
- **Fix:** Extract `@Observable` sub-models: `RecordingState`, `InstallState`, `MaintenanceState` and `MeetingState`, owned by the session. Views observe only the sub-model they need.
- **Effort:** M
- **Grade lift:** C+ → C+/B− (removes the god object, which also reduces re-renders; see G2)

#### A4 — Stop `DataManager` reaching into other stores
- **Where:** `Sources/Stores/DataManager.swift:118` (`nonisolated(unsafe)` with `MainActor.assumeIsolated`), `:271-272` (`deleteRecord` calls `UsageMetricsStore.shared` and `SourceUsageStore.shared`)
- **What's wrong:** It crashes if first touched off the main thread, and the persistence layer mutates metrics stores directly.
- **Fix:** Make `shared` `@MainActor static let`. Have the metrics stores react to `HistoryRevision` (or to an injected callback) instead of being called from `DataManager`.
- **Effort:** S
- **Grade lift:** small (makes the coupling explicit and removes a crash trap)

---

## B — Backend Quality — B

The daemon is carefully hardened:
- Environment allowlist and `F_SETNOSIGPIPE`.
- One write queue per session, with the reply handler registered before the write.
- 1 MiB payload cap and SIGTERM→SIGKILL reaping.
- A contract test that runs the real Python daemon (`Tests/MLRPCContractTests.swift`).

Error hygiene is good: 0 `try!`, 0 `as!`, about 4 force unwraps, and `fatalError` only in previews. The weaknesses are in process lifecycle edge cases, which show up to the user as "Parakeet stopped working until I relaunched".

#### ~~B1~~ ✓ done 2026-11-04 — Daemon restart limit never resets, and every request gets the same 60-second timeout
- **Where:** `Sources/Managers/MLDaemonManager+Process.swift:22,36`, `Sources/Managers/MLDaemonManager.swift:48,164,219`, `Sources/ml/correction.py:253`, `Sources/ml/parakeet.py:86`
- **What's wrong:**
  - After 3 failed starts, the counter can only be cleared by a successful reply or 10 seconds of uptime, both of which need a running process. Parakeet and cleanup then fail with `restartLimitReached` until the app is relaunched.
  - Every method shares one 60-second timeout, and on expiry the whole daemon is killed. A 4096-token correction on the 27B model, or a long Parakeet file job, can take longer than that.
- **Fix:**
  - Reset the restart counter after a cool-down (e.g. 60 s) and on any user-initiated Retry.
  - Give each method its own timeout, scaled by input (audio duration, `max_tokens`).
  - Add tests for both behaviours.
- **Effort:** M
- **Grade lift:** B → B+ (removes the main "stuck until relaunch" failure)

#### B2 — Cancelling doesn't stop Python, and each request leaves a 60-second sleep task running
- **Where:** `Sources/Managers/MLDaemonManager.swift:201-204,212`, `Sources/ml/rpc.py:106`
- **What's wrong:**
  - Swift drops the pending request, but the single-threaded daemon keeps generating, so the next dictation waits behind work nobody wants.
  - The per-request sleep task is never cancelled when a reply arrives.
- **Fix:** Store the timeout `Task` and cancel it on reply. On user cancel while a request is in flight, either send a `cancel` RPC (and check a flag between generation steps) or restart the daemon.
- **Effort:** M
- **Grade lift:** B+ → B+ (improves responsiveness after a cancel)

#### B3 — Blocking `waitUntilExit` / `readDataToEndOfFile` on the cooperative thread pool
- **Where:** `Sources/Services/UvBootstrap.swift:178,189`, `Sources/Services/UvBootstrap+Process.swift:49`, `Sources/Services/ModelVerificationService.swift:151-152`
- **What's wrong:** `uv venv` / `uv sync` can block a Swift-concurrency thread for minutes with no timeout, which can starve other tasks.
- **Fix:** Use `terminationHandler` with a continuation and `FileHandle.readabilityHandler` (the same pattern `ModelVerificationService` already uses for exit), plus a timeout.
- **Effort:** S
- **Grade lift:** small

#### B4 — Silent meeting-save failures and repeated write-error notifications
- **Where:** `Sources/Rebuild/RebuildMeetingSession.swift:117,185` (`try? store.save`), `Sources/Services/AudioEngineRecorder.swift:359`
- **What's wrong:**
  - Meeting transcripts can be lost without any message.
  - `recordingStartFailed` is posted on every failed buffer write instead of once.
- **Fix:** Show a save failure as a session notice, with a retry that keeps the in-memory document. Latch the write-error notification once per session.
- **Effort:** S
- **Grade lift:** small

#### B5 — Quit can hang
- **Where:** `Sources/Rebuild/RebuildApp.swift:180-187` (`terminateLater` has no deadline), `Sources/Managers/MLDaemonManager+Process.swift:261` (the reap loop after SIGKILL is unbounded)
- **What's wrong:** A wedged daemon can stop the app from quitting.
- **Fix:** Add a 3-second deadline to both paths, then reply `.terminateNow`.
- **Effort:** S
- **Grade lift:** small

#### B6 — The correction retry repeats the identical generation
- **Where:** `Sources/ml/correction.py:264-266`
- **What's wrong:** The retry rebuilds the same prompt and runs generation again. That doubles latency on the failure path and can never produce a different result.
- **Fix:** Either change the retry (a stricter prompt or a different stop rule) or remove it. Update `test_correction_sanitize.py`.
- **Effort:** S
- **Grade lift:** small

---

## C — Frontend Quality (UI/UX) — C+

**Strengths:**
- `RebuildTheme` (`Sources/Rebuild/RebuildDesign.swift:8-104`) is a real token system with light, dark and high-contrast variants, plus shared components (`RebuildSection`, `RebuildCallout`, `RebuildFormRow`).
- Blocked actions always say why (`recordingBlockedReason`).
- Library empty, loading and error states are thoughtful (`RebuildLibraryView.swift:27-41,121-133`).
- Downloads show progress and offer Cancel.
- Destructive actions are confirmed.
- Phase changes are announced to VoiceOver.

**What holds the grade down:**
- The user is usually *in another app* when dictating, and that experience has blind spots: errors and paste fallbacks are only shown in the workspace window, Express Mode shows nothing at all, and clicking the waveform stops recording.
- Accessibility and typography are below the bar: 103 fixed `.font(.system(size:))` calls, and 1 `accessibilityHint` in the whole of Rebuild.
- Copy uses internal names ("Rebuild", "runtime", "Core ML").
- There is no localisation.

#### ~~C1~~ ✓ done 2026-11-04 — Show failures and paste fallbacks in the HUD, not just the workspace window
- **Where:** `Sources/Rebuild/RebuildSession.swift:195-198,213-215,293,310-312`, `RebuildDeliveryStatus.swift:12`, `RebuildRecorderView.swift`
- **What's wrong:**
  - On transcription failure, silent input, no audio or interruption, the HUD closes and the message goes to the workspace window, which the user can't see.
  - When Smart Paste fails, the status says "Paste manually with Command V", but the HUD has already closed.
  - A sound plays only on success.
  - Result: a full-screen user sees the HUD vanish and no text arrives.
- **Fix:**
  - Add HUD states `.failed(message)` and `.copiedPasteManually`, kept on screen for about 4 seconds (paused while hovered), with **Retry** and **Open** buttons.
  - Play an error sound.
  - Add tests in the `RebuildSession` suites for each terminal state.
- **Effort:** M
- **Grade lift:** C+ → B− (fixes the most damaging UX gap for a dictation app)

#### C2 — Express Mode has no recording indicator, and the menu bar icon never changes
- **Where:** `Sources/Rebuild/RebuildSession.swift:186` (`showRecorder()` skipped when `immediateRecording`), `Sources/Rebuild/RebuildStatusController.swift:14-16`
- **What's wrong:** The status item image is set once. In Express Mode the user cannot tell whether the app is recording or transcribing, which is also a privacy issue for a microphone app.
- **Fix:** Have `RebuildStatusController` observe the session phase and swap the symbol and tint for idle, starting, recording, transcribing and failed. Update the accessibility description to match.
- **Effort:** S
- **Grade lift:** + (meaningful privacy and feedback gain)

#### C3 — Clicking the HUD waveform stops the recording
- **Where:** `Sources/Rebuild/RebuildRecorderView.swift:33` (`onTap: session.toggleRecording`), `Sources/Views/Components/Waveform/WaveformContainer.swift:88` (wraps everything in a `Button`)
- **What's wrong:** The panel is `isMovableByWindowBackground`, so trying to drag it ends the dictation. VoiceOver reads "Microphone waveform, button" with no hint of what it does.
- **Fix:** Pass a no-op `onTap` in the HUD (it already has explicit stop and cancel buttons), or make the waveform button-free when there's no action. Add a test.
- **Effort:** S
- **Grade lift:** + (removes an accidental-stop trap)

#### C4 — Esc probably doesn't cancel, despite the tooltip
- **Where:** `Sources/Rebuild/RebuildRecorderView.swift:50,72` ("Cancel (Esc)"), `Sources/Rebuild/RebuildApp.swift:127` (non-activating panel, never key)
- **What's wrong:** `.onExitCommand` only fires once the panel is key, which happens only after the user clicks it.
- **Fix:** While the phase is busy, install an `NSEvent` Esc monitor scoped to the session (local plus global, if Accessibility is granted), or reword the tooltip. Verify by hand in a full-screen app.
- **Effort:** S
- **Grade lift:** + (a promised control works)

#### C5 — Nothing is visible during microphone start (up to 4 s)
- **Where:** `Sources/Rebuild/RebuildSession.swift:186`, `Sources/Rebuild/RebuildRecorderView.swift:12-13`
- **What's wrong:** The HUD appears only after the mic is ready. If it were shown during `.starting`, it would wrongly say "Transcribing…".
- **Fix:** Show the HUD at `.starting` with a "Connecting microphone…" title and a muted waveform.
- **Effort:** S
- **Grade lift:** small

#### C6 — Raw `localizedDescription` shown to users (37 sites)
- **Where:** `Sources/Rebuild/RebuildSession.swift:310`, `RebuildSessionSetup.swift:180`, `RebuildLibraryState.swift:60,71,79,106`, `RebuildWritingView.swift:13`, `RebuildPreferencesView.swift:76,84`, `RebuildStartup.swift:31`
- **What's wrong:** Errors from Python, MLX, Hugging Face and the file system appear verbatim.
- **Fix:** Add a `RebuildErrorText.userMessage(for:)` that maps known domains (daemon timeout, restart limit, disk full, network/offline, model missing) to plain sentences with a next step. Put the raw text behind a "Details" disclosure and in the copied diagnostics.
- **Effort:** M
- **Grade lift:** +

#### C7 — The denied-microphone state is mislabelled
- **Where:** `Sources/Rebuild/RebuildModelsView.swift:57,67-69`, `RebuildSessionSetup.swift:166-167`
- **What's wrong:** After a denial the button still says "Allow microphone", but it opens System Settings. The status reads the same whether access is undecided or denied.
- **Fix:** When access is denied, show "Microphone access is off" with an "Open Privacy Settings…" button and one sentence explaining how to turn it on.
- **Effort:** S
- **Grade lift:** small

#### C8 — The waveform picker is a flat 11-item dropdown with hidden Aurora options
- **Where:** `Sources/Rebuild/RebuildRecordingTuningView.swift:28-41`, `Sources/Views/Components/Waveform/WaveformStyle.swift:34-47` (descriptions that are never shown)
- **What's wrong:**
  - The picker has no preview.
  - The descriptions are never shown.
  - It's buried under "Advanced & support".
  - The Horizon/Lens shape control only appears once an Aurora style is chosen.
  - "Motion intensity" (Glow/Balanced/Burst) has no explanation.
- **Fix:**
  - Replace the dropdown with a grid of small live previews (`WaveformStylePreview` with a shared `LivePreviewSampler` already exists), grouped into "Classic" and "Aurora", with captions.
  - Put the shape segmented control inside the Aurora group.
  - Move the whole group to a visible "Recorder" section.
- **Effort:** M
- **Grade lift:** + (helps people find the new Aurora styles)

#### C9 — Fixed type sizes and accessibility gaps
- **Where:**
  - Fixed sizes: 103 `.font(.system(size:))` calls in `Sources/Rebuild`, including 8.5 pt "PRIVATE DICTATION" at `RebuildWorkspace.swift:131`.
  - No accessibility modifiers at all: `RebuildModelsView`, `RebuildMeetingsView`, `RebuildModeEditor`, `RebuildHistoryCleanupView`, `RebuildMicrophoneRankingView`, `RebuildRecordingTuningView`.
  - `RebuildMicrophoneRankingView.swift:29-39`.
- **What's wrong:**
  - Nothing scales with the user's text size, and some labels are below a readable minimum.
  - The microphone ranking buttons read "Move up" without saying which microphone.
  - Rebuild has only 1 `accessibilityHint`.
  - The waveform has no `accessibilityValue` (level).
- **Fix:**
  - Add semantic type tokens to `RebuildTheme` (`.rebuildBody`, `.rebuildCaption`, …) built on relative text styles, and replace the fixed sizes. Raise the minimum to 11 pt.
  - Label the ranking buttons with the mic name ("Move AirPods up").
  - Add a level value to the HUD waveform.
- **Effort:** M
- **Grade lift:** +

#### C10 — Internal names and inconsistent terms in user-facing copy
- **Where:**
  - "Rebuild": `Sources/Rebuild/RebuildStatusMenu.swift:22,25`, `RebuildWindowFactory.swift:12`, `RebuildStatusController.swift:15-16`.
  - Cleanup terms: `RebuildWritingView.swift:70,105`, `RebuildMeetingsView.swift:66,70`, `RebuildModeEditor.swift:38`.
  - Recorder terms: `RebuildPreferencesView.swift:130-131`, `RebuildModelsView.swift:129,227,243`.
- **What's wrong:**
  - "AudioWhisper Rebuild" and "Quit Rebuild" are shown to users.
  - The cleanup feature has five names: Writing cleanup, Correction model, correction weights, writing model plus a raw HF repo id, and "Local (MLX)".
  - The recorder has three names: Overlay, Recorder style, recorder.
  - Jargon: "runtime", "Core ML", "Cluster labels", and "Build <hash> · Development preview".
- **Fix:**
  - Pick "Recorder" and "Cleanup model". Show `displayName` instead of repo ids.
  - Rename the menu and window to "AudioWhisper" (keep the bundle id).
  - Replace string matching for status tone (`RebuildWritingView.swift:171-176`) with an enum.
- **Effort:** S
- **Grade lift:** small–medium

#### C11 — Navigation and menu bar menu gaps
- **Where:** `Sources/Rebuild/RebuildApp.swift:37` (Meetings comes after Preferences, so it gets ⌘6), `RebuildWorkspace.swift:93,119`, `RebuildStatusMenu.swift`, the setup checklist in `RebuildModelsView`
- **What's wrong:**
  - Meetings is out of order.
  - The menu bar menu has no readiness line and no Library or Settings items.
  - The setup checklist never covers the recording shortcut, which is off by default and is the app's main entry point.
- **Fix:**
  - Reorder the sidebar so Meetings sits next to Library and Preferences comes last.
  - Add a status line plus Library and Settings items to the menu.
  - Add checklist step 4, "Choose a recording shortcut".
- **Effort:** S
- **Grade lift:** small

#### C12 — No localisation, and design-token gaps
- **Where:**
  - No `String(localized:)`, `LocalizedStringResource` or `.xcstrings` anywhere.
  - Strings built as `String`: `RebuildReadiness.nextStep`, `RebuildDeliveryStatus`, `"Step \(number), …"`.
  - `padding(.horizontal, 28)` and `maxWidth: 860` repeated on each page; corner radii 7, 8, 10, 12 and 20.
  - `RebuildMeetingsView.swift:31,40,57` uses system styles instead of the theme.
- **What's wrong:** The app can't be translated. Spacing and radius drift between pages, and Meetings looks like a different app.
- **Fix:**
  - Add `RebuildTheme.Spacing` and `RebuildTheme.Radius` tokens, and restyle Meetings with `RebuildSection`.
  - Adopt a strings catalogue, starting with status and notice text.
- **Effort:** M (tokens S, localisation M)
- **Grade lift:** small

---

## D — Testing & Reliability — B−

**Strong points:**
- 3,297 tests passing; Rebuild at 87.6% coverage and Stores at 89.5%.
- A contract test against the real daemon (`Tests/MLRPCContractTests.swift`), about 128 Python unittests, and nightly real-engine runs (`.github/workflows/nightly.yml`).
- The session controller and Smart Paste are well covered.

**Weak points:**
- The snapshot suite is broken: every baseline viewed is AppKit's yellow "cannot render" placeholder, and there are no Rebuild baselines at all.
- Some tests can never fail.
- Negative checks are timed with sleeps.
- The CI coverage gate is a 40% ratchet.

#### ~~D1~~ ✓ done 2026-11-04 — Snapshot baselines are "cannot render" placeholders, and the live UI isn't covered `[FE]`
- **Where:** `Tests/__Snapshots__/*.png` (35 files, last touched in 825cefc). `WaveformContainer-classic-recording.png`, `WaveformContainer-error.png`, `Waveform-neon-dark.png` and `DashboardView-light.png` all show the yellow fill with a red ⃠. The single-colour guard is in `assertSnapshot`.
- **What's wrong:** CLAUDE.md forbids exactly these baselines, and the >99.5%-single-colour guard doesn't catch them. Every baseline is of a legacy view or a waveform; none covers a Rebuild screen or Aurora.
- **Fix:**
  - Add a placeholder detector to `assertSnapshot`: a large share of yellow (≈#E6C300) plus red pixels → fail.
  - Re-record on a real WindowServer.
  - Add Rebuild baselines: Record idle/recording/failed, Models with mic denied, Preferences, Library empty, the HUD, and the Aurora Horizon and Lens shapes.
  - Delete the legacy baselines when A1 lands.
- **Effort:** M
- **Grade lift:** B− → B (visual regressions become detectable for the shipping UI)

#### D2 — Remove tests that can never fail `[FE]`
- **Where:** `Tests/Views/Dashboard/DashboardViewTests.swift:10-84` (40 `XCTAssertNotNil` calls on non-optional `Color`s), `Tests/Views/Components/CelebrationEffectsTests.swift:8-46`
- **What's wrong:** They inflate the test count and coverage without checking anything.
- **Fix:** Delete them, or assert on semantic output with ViewInspector, which is already a dependency.
- **Effort:** S
- **Grade lift:** small (an honest signal)

#### D3 — Replace sleep-then-assert-nothing and fixed sleeps with polling or injected clocks `[both]`
- **Where:** `Tests/RebuildSmartPasteTests.swift:82,100,111`, `Tests/PermissionManagerTests.swift:426,443`, `Tests/TranscriptionHistoryIntegrationTests.swift:78` (117 sleep/`asyncAfter` sites in total)
- **What's wrong:** A negative check after a 60 ms sleep passes even when the code is just slow. Positive waits with fixed sleeps are a classic source of flaky tests.
- **Fix:** Use the existing `waitFor` polling helper (`RebuildSmartPasteTests.swift:161`). For negative checks, expose a completion hook or inject a clock so the test asserts after the guarded path has definitely run.
- **Effort:** M
- **Grade lift:** small–medium (reliability)

#### D4 — A missing fixture skips instead of failing `[BE]`
- **Where:** `Tests/AudioDecodeTests.swift:22` (`XCTSkip` when `test_audio.wav` is missing), `Tests/ParakeetServiceTests.swift:93,116`, `Tests/ModelManagerCoverageTests.swift:66,87,92` (skip based on which models are on the machine)
- **What's wrong:** A packaging mistake quietly turns tests green, and results differ between machines.
- **Fix:** Make the missing fixture an `XCTFail`. Inject the cache root through `AUDIOWHISPER_APP_SUPPORT_DIR` with a temp directory, so the model-state tests are deterministic.
- **Effort:** S
- **Grade lift:** small

#### D5 — Untested live types `[both]`
- **Where:** `RebuildStatusController`, `RebuildDiagnostics` (also the MCP `status` payload), `RebuildDeliveryStatus`, `RebuildReadiness`/`RebuildPhase`, `Sources/App/RecordingDiagnostics.swift`; `PublicAutomation` path-scope checks have only one test file.
- **What's wrong:** User-visible status text and the MCP security boundary have no direct tests.
- **Fix:**
  - Table-driven tests for phase → status title/tone/icon, which also covers C2.
  - Path-scope tests for symlinks, `..`, `$HOME` and relative paths.
- **Effort:** S
- **Grade lift:** small

#### D6 — Run the Python tests on the shipped interpreter, and raise the ratchet `[both]`
- **Where:** `.github/workflows/ci.yml:337,367` (the runner's default `python3`, while the app ships `>=3.11,<3.12` per `Sources/Resources/pyproject.toml`), `ci.yml:191` (40% gate with 0.57 points of headroom)
- **What's wrong:** CI tests a different Python than the one users get. The gate sits far below the actual 55.6%.
- **Fix:** Add `actions/setup-python` with 3.11. Raise the gate to about 50% now, and higher once A1 removes the poorly covered legacy Views.
- **Effort:** S
- **Grade lift:** small

---

## E — Security — B

**Good posture for an unsandboxed app (ADR 0001):**
- Release signing uses hardened runtime and notarization.
- The bundled `uv` is SHA-256 checked when it is prepared (`scripts/prepare-uv.sh:12-23`), and models are pinned by commit (`Sources/Models/ModelPins.swift`).
- Every `Process` uses a fixed argv, with no shell.
- Python stderr is logged as `.private`, and no transcript logging was found.
- Smart Paste marks its clipboard writes as transient.
- Deep links are validated.

**Main gap:** which `uv` binary runs.

#### ~~E1~~ ✓ done 2026-11-04 — An unverified `uv` from PATH or Application Support wins over the verified bundled copy
- **Where:** `Sources/Services/UvBootstrap.swift:104-106` (prefers `which uv`; hash checked only for the bundled path), `:136` (Application Support copy runs unchecked), `:315`
- **What's wrong:** Any user-writable `uv` earlier on PATH, or in `~/Library/Application Support/<dir>/bin`, is run, and it then installs and runs the Python environment.
- **Fix:**
  - Use the bundled `uv` first and always verify it.
  - Accept other copies only if their hash matches the bundled one.
  - Gate the `AUDIOWHISPER_APP_SUPPORT_DIR` override (`:315`) behind `#if DEBUG` or a test flag.
  - Add tests.
- **Effort:** S
- **Grade lift:** B → B+

#### E2 — Trim the entitlements
- **Where:** `scripts/build.sh:70-71` (`com.apple.security.automation.apple-events`, `network.client`), `scripts/prepare-uv.sh:33` (`uv` signed with the full app entitlements)
- **What's wrong:**
  - Nothing sends Apple Events.
  - `network.client` only applies to sandboxed apps.
  - The helper binary carries entitlements it doesn't need.
- **Fix:** Remove both entitlements, sign `uv` with no entitlements, and re-run the bundle smoke test.
- **Effort:** S
- **Grade lift:** small

#### E3 — Ad-hoc and dev builds leave out hardened runtime
- **Where:** `scripts/build.sh:485`
- **What's wrong:** Local and CI builds behave differently from release (library validation, DYLD environment), so release-only failures show up late.
- **Fix:** Add `--options runtime` to the ad-hoc path too.
- **Effort:** S
- **Grade lift:** small

#### E4 — The notarization password is visible in the process list
- **Where:** `scripts/build.sh:531-534`
- **What's wrong:** `--password` on the command line can be read with `ps`.
- **Fix:** Use `xcrun notarytool store-credentials` and `--keychain-profile`.
- **Effort:** S
- **Grade lift:** small

#### E5 — MCP path scope and the plain-copy clipboard
- **Where:** `Sources/App/PublicAutomation.swift:143,151-157`, `Sources/Managers/PasteManager.swift:67-71`
- **What's wrong:**
  - `directory()` accepts `$HOME` as a root.
  - There is a check-then-use race between the symlink check and the read.
  - Copy-only delivery puts transcripts into clipboard-history apps without the transient marker.
- **Fix:** Reject `$HOME` and other overly broad roots, and open with `O_NOFOLLOW` before reading. Make transient marking a preference, defaulting to on.
- **Effort:** S
- **Grade lift:** small

---

## F — Dependencies & Tech Currency — B+

- Few direct dependencies, all current: argmax-oss-swift 1.1.0, KeyboardShortcuts 3.1.0, ViewInspector 0.10.5 (pinned exactly).
- The Python lock is enforced with `uv sync --frozen`, and Dependabot covers Swift, uv and Actions.
- No deprecated AppKit calls were found (no `activate(ignoringOtherApps:)`, no `NSUserNotification`).
- Remaining issues are declaration drift and supply-chain pinning.

#### F1 — Declared minimums don't match reality
- **Where:**
  - `Package.swift:1` (tools 5.9, `.macOS(.v14)`) against `README.md:32,35` (macOS 26/27, Swift 6.2 toolchain).
  - CLAUDE.md "Swift 5.9+" and "Only two direct SwiftPM dependencies"; ViewInspector and SpeakerKit are also used.
- **What's wrong:** The real requirements are stated in one place and contradicted in another.
- **Fix:** Raise `swift-tools-version` to 6.2, choose a deployment target and state it once, and update CLAUDE.md.
- **Effort:** S
- **Grade lift:** B+ → A−

#### F2 — Pin GitHub Actions by commit SHA
- **Where:** `.github/workflows/*.yml` (`actions/checkout@v4`, `SonarSource/sonarqube-scan-action@v7`, …)
- **What's wrong:** A moved or compromised tag would run in CI with repository secrets.
- **Fix:** Pin each action to a SHA with a `# vX` comment. Dependabot already updates them.
- **Effort:** S
- **Grade lift:** small

#### F3 — Small currency nits
- **Where:**
  - `uv.lock` (certifi 2025.8.3).
  - `Sources/Resources/pyproject.toml` comment "Dependabot does not manage this file", which is no longer true.
  - `Sources/Rebuild/RebuildRecorderView.swift:115` (`Text + Text` and `.foregroundColor`, deprecated on current SDKs).
- **What's wrong:** A stale CA bundle, a misleading comment and deprecated SwiftUI calls.
- **Fix:** Bump certifi, fix the comment, and use `Text` interpolation with `.foregroundStyle`.
- **Effort:** S
- **Grade lift:** small

---

## G — Performance & Scalability — B−

**Strengths:**
- The audio tap uses a preallocated ring buffer, a lock, and FFT setup created once.
- Model scans run off the main thread.
- History is paged in bounded chunks, and search is debounced.

**Weaknesses:**
- Every SwiftData fetch runs synchronously on the main actor.
- The audio callback allocates on every buffer and republishes three `@Published` values.
- The new Aurora view likely never pauses and does a lot of offscreen compositing per frame (it isn't committed yet, so it's cheap to fix now).

#### G1 — Aurora: make the pause real, cap the frame rate, cut per-frame work (uncommitted code)
- **Where:**
  - `Sources/Views/Components/Waveform/Aurora/AuroraWaveformView.swift:17,22,25`
  - `Sources/Views/Components/Waveform/Aurora/AuroraRenderer.swift:59,76,100,122,132`
- **What's wrong:**
  - The pause condition `!isActive && engine.isAtRest` is only re-evaluated when `body` re-runs, and `AuroraEngine` isn't observable, so the timeline probably never pauses once the mountains settle.
  - `.animation` without `minimumInterval` runs at 120 Hz on ProMotion.
  - Each frame does about 13 `drawLayer` offscreen composites, rebuilds about 21 gradients and 12+ arrays, and computes the deep field twice per lobe.
  - `@State` with a default value creates a throwaway `AuroraEngine` every time the parent view is rebuilt.
  - It ignores the visual-intensity setting.
- **Fix:**
  - Make `AuroraEngine` `@Observable` with a published `atRest` that is set when the mountains settle.
  - Use `.animation(minimumInterval: 1/60, paused:)`.
  - Reuse the deep field per lobe, and cache `xs`, `zero` and the alpha ramps per size.
  - Initialise the engine lazily.
  - Map intensity to amplitude.
  - Add a test that the view stops ticking after it settles.
- **Effort:** S
- **Grade lift:** B− → B (with G2)

#### G2 — Audio tap allocations and broad view invalidation
- **Where:** `Sources/Services/AudioEngineRecorder.swift:267-336`, `Sources/Services/FFTProcessor.swift:118,124,175`, `Sources/Rebuild/RebuildRecorderView.swift`
- **What's wrong:**
  - Each callback (about 47 per second) allocates `monoSamples` plus 3 or more FFT arrays and spawns a `Task`.
  - The 60 Hz throttle never drops anything.
  - Three separate `@Published` writes invalidate the whole HUD.
- **Fix:** Reuse scratch buffers, and publish a single `MeterFrame` struct. Isolate the waveform in a child view that observes only the meter.
- **Effort:** M
- **Grade lift:** +

#### G3 — SwiftData reads run on the main actor
- **Where:** `Sources/Stores/DataManager+Fetching.swift:150-162` (OFFSET paging plus a `localizedStandardContains` full scan)
- **What's wrong:** Every fetch, search and page creates a `ModelContext` on the main thread. Fine for hundreds of records, but it will stutter at thousands.
- **Fix:** Move reads to a `@ModelActor` that returns value snapshots, and keep writes on the main actor.
- **Effort:** M
- **Grade lift:** +

#### G4 — The Library list resets and fetches twice
- **Where:** `Sources/Rebuild/RebuildLibraryView.swift:44-49`, `Sources/Rebuild/RebuildLibraryState.swift:70`
- **What's wrong:** Any history change resets the list to 50 rows, so loaded pages are lost and the scroll position jumps. A delete triggers two fetches.
- **Fix:** Apply deletes and inserts to the loaded array in place, and skip the revision-triggered reload when the change came from this view.
- **Effort:** S
- **Grade lift:** small

---

## H — Documentation & Onboarding — B−

**Strengths:**
- The README clearly states this is a local-only fork.
- Six indexed ADRs (`docs/adr/`), plus CONTRIBUTING and SECURITY.
- Unusually good inline rationale (`ModelPins.swift`, the comments on the `ci.yml` coverage gate, `.swiftlint.yml`).

**Weaknesses:** The two docs an agent or new contributor reads first are wrong about the core of the app.

#### H1 — CLAUDE.md's architecture describes the legacy shell
- **Where:** `CLAUDE.md` "Architecture" (`Sources/App/AudioWhisperApp.swift`, which no longer exists; the AppDelegate split) and "Key Dependencies" / "Code Patterns"
- **What's wrong:**
  - `Sources/Rebuild/` (53 files, the whole live app) isn't mentioned, nor is the MCP/CLI automation path.
  - New work gets steered into dead code. This already happened: the Aurora picker was added to `DashboardVisualsView`.
- **Fix:** Rewrite the section around `AudioWhisperEntryPoint` → `RebuildApp`/`RebuildDelegate` → `RebuildSession`, list which folders are legacy, and correct the dependency and toolchain lines.
- **Effort:** S
- **Grade lift:** B− → B

#### H2 — docs/rebuild.md and README contradictions
- **Where:**
  - `docs/rebuild.md` describes a "warm paper/ink palette with restrained rust accents", but the code uses slate with a teal accent (`RebuildDesign.swift:4-6`).
  - Its intro is written as if the rebuild still lived on a separate branch and worktree.
  - `README.md:32` disagrees with `Package.swift` on the OS minimum.
  - ADR 0004 is still "Proposed".
- **What's wrong:** The design and requirements docs have drifted from the code.
- **Fix:** Update the palette and branch statements, decide ADR 0004, and state the macOS minimum in one place.
- **Effort:** S
- **Grade lift:** small

#### H3 — Stale `mypy.ini` header
- **Where:** `mypy.ini:1-9`
- **What's wrong:** It says "574 lines… a single unit test" and refers to a "python-typecheck CI job". The package is now 820 lines with 10 test files, and the check is a step in the `lint` job.
- **Fix:** Update the header or make it describe the setup without numbers.
- **Effort:** S
- **Grade lift:** small

---

## I — Developer Experience & Tooling — B+

**Strengths:**
- The Makefile covers the whole loop: build, build-dev, run, test, typecheck and release (release forces `--repo`).
- `scripts/lib/xcode-env.sh` recovers automatically from the Command Line Tools/`actool` trap.
- SwiftLint is pinned to 0.65.0 and runs with `--strict`, with only 20 inline disables.
- An analyzer ratchet, `mypy --strict`, `uv lock --check`, duplicate-run preflight and job timeouts in CI.

**Remaining issues:** friction and repo hygiene.

#### I1 — Builds dirty tracked files
- **Where:** `scripts/build.sh:~143-152` (rewrites the tracked `Info.plist` version fields), `Sources/Utilities/VersionInfo.swift` (tracked but listed in `.gitignore:128`)
- **What's wrong:** Every `make build` leaves a modified `Info.plist`; this happened during the Aurora work. `VersionInfo.swift` drifts.
- **Fix:** Stamp the copy of `Info.plist` inside the built bundle instead of the source. Run `git rm --cached Sources/Utilities/VersionInfo.swift` and generate it during the build.
- **Effort:** S
- **Grade lift:** B+ → A−

#### I2 — 178 MB of audit evidence tracked in git
- **Where:** `.Codex/` (644 tracked files)
- **What's wrong:** It bloats every clone and CI checkout.
- **Fix:** Move it to Git LFS or release artifacts, and keep only the READMEs that docs link to. Removing it from history is optional and needs a separate decision.
- **Effort:** M
- **Grade lift:** small

#### I3 — Two overlapping pre-commit systems
- **Where:** `.pre-commit-config.yaml` (`no-debug-print` at line 15 fails on any line-leading `print(`, even inside `#if DEBUG`), `.githooks/pre-commit`
- **What's wrong:** It's unclear which hook runs, and the print hook contradicts its own message.
- **Fix:** Keep one system and fix the print rule.
- **Effort:** S
- **Grade lift:** small

#### I4 — The `lint` CI job has no timeout
- **Where:** `.github/workflows/ci.yml:220-224`
- **What's wrong:** A hung step would run until GitHub's 6-hour default.
- **Fix:** Add `timeout-minutes: 15`.
- **Effort:** S
- **Grade lift:** small
