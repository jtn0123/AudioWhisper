# Codebase Grade Report

**Project:** AudioWhisper
**Audited:** 2026-05-16
**Stack:** macOS 14+ menu-bar app — Swift 5.9 / SwiftUI + AppKit, AVFoundation audio, embedded uv-managed Python (MLX/Parakeet), WhisperKit/OpenAI/Gemini transcription, SwiftData persistence

## Summary

| ID | Category | Grade | Items |
|----|----------|-------|-------|
| A | Architecture & Design | B | 5 |
| B | Service & Data Layer Quality | B | 6 |
| C | Frontend / SwiftUI Quality | B− | 5 |
| D | Testing & Reliability | C+ | 4 |
| E | Security | B | 4 |
| F | Dependencies & Tech Currency | B+ | 4 |
| G | Performance & Scalability | B− | 6 |
| H | Documentation & Onboarding | A− | 4 |
| I | Developer Experience & Tooling | A− | 5 |
| **Overall** | | **B** | **43** |

**Top 5 highest-leverage fixes:** D1, D2, E1, G1, A2

---

## A — Architecture & Design — B

Layering is mostly clean: a real `Sources/` taxonomy (App/Services/Stores/Managers/Models/ViewModels/Views), Views→ViewModels→Services flows correctly, `RecordingViewModel` takes dependencies via constructor injection (`RecordingViewModel.swift:100-104`), no god objects (largest file ~548 lines), and `AppDelegate` is healthily split into 6 focused extensions. The drag: `.shared` singletons are pervasive (~18 across Services/Stores/Managers), a full `DependencyContainer` + `@Injected` wrapper was built but adopted in only one file each (dead infrastructure), and Views reach into store singletons directly ~16 times, bypassing the ViewModel layer.

#### A1 — Adopt or delete the unused DependencyContainer
- **Where:** `Sources/Utilities/DependencyContainer.swift:18-160`; `@Injected` used in 1 file, `DependencyContainer.shared` in 1.
- **What's wrong:** A complete DI container exists but is effectively unused — dead weight that gives a false impression of testability and leaves two competing DI styles in the codebase.
- **Fix:** Decide one way. Either migrate ViewModels/Services to resolve through the container, or delete `DependencyContainer.swift` + `@Injected` and standardize on the constructor injection already used by `RecordingViewModel`.
- **Effort:** M (delete) / L (adopt)
- **Grade lift:** B → B+ (removes a dead architectural pattern; one clear DI story)

#### A2 — Views bypass ViewModels to hit Stores directly
- **Where:** ~16 `.shared` references in `Sources/Views/` — `DataManager.shared` ×7, `UsageMetricsStore.shared` ×2, `SourceUsageStore.shared` ×3.
- **What's wrong:** Dashboard/History views call store singletons directly, breaking the Views→ViewModels→Stores direction and making those views hard to unit-test in isolation.
- **Fix:** Route store access through dedicated ViewModels passed via `@StateObject`/`@Environment`. Start with the Dashboard tabs.
- **Effort:** M
- **Grade lift:** B → B+ (restores a testable layering boundary)

#### A3 — Singleton sprawl + `nonisolated(unsafe)` shared
- **Where:** ~18 `static let shared`; `DataManager.swift:100-102` force-casts the singleton onto the main actor with `nonisolated(unsafe)`.
- **What's wrong:** Heavy global mutable state; the `nonisolated(unsafe)` accessor defeats concurrency checking — safe today, a footgun under future refactors.
- **Fix:** Reduce to a small set of genuinely-global services; inject the rest. Replace the `nonisolated(unsafe)` accessor with a `@MainActor` static or a lazy main-actor accessor.
- **Effort:** L
- **Grade lift:** B → B+ (less global state, sound concurrency)

#### A4 — A Store imports SwiftUI
- **Where:** `Sources/Stores/CategoryStore.swift`
- **What's wrong:** A persistence-layer Store importing SwiftUI inverts the dependency direction — Stores should be UI-agnostic.
- **Fix:** Move any UI types (e.g. `Color`) to a Model/Design type or expose raw values the view maps.
- **Effort:** S
- **Grade lift:** B → B (tidies a layering smell)

#### A5 — Dead parameter kept "for API compatibility"
- **Where:** `Sources/Stores/ProviderSettingsState.swift:41-42`
- **What's wrong:** A parameter is explicitly commented as no longer used but retained — misleading dead surface.
- **Fix:** Remove the parameter and update callers.
- **Effort:** S
- **Grade lift:** B → B (removes misleading API)

---

## B — Service & Data Layer Quality — B

A deliberate, well-typed layer. Typed errors are pervasive (`SpeechToTextError`, `ParakeetError`, `MLDaemonError`, `DataManagerError`); `MLDaemonManager` is a genuinely well-built actor with deadline-based request reaping and no double-resume races (`MLDaemonManager.swift:149-199`); `LocalWhisperService` has an LRU cache with memory-pressure eviction. Debt: vestigial cruft (dead `keychainService` params, twin `transcribe`/`transcribeRaw`), and a few data-layer hot paths that fetch the whole table.

#### B1 — Dead `keychainService` parameters across services
- **Where:** `SpeechToTextService.swift:38-40`, `SemanticCorrectionService.swift:47-49`
- **What's wrong:** Both inits accept a `keychainService` parameter explicitly "kept for API compatibility but no longer used," misleading callers into thinking keychain is involved.
- **Fix:** Remove the parameter; update call sites and mocks.
- **Effort:** S
- **Grade lift:** B → B (removes misleading API)

#### B2 — Redundant `transcribe` / `transcribeRaw` twins
- **Where:** `SpeechToTextService.swift:79-95`
- **What's wrong:** `transcribe(audioURL:provider:model:)` just forwards to `transcribeRaw(...)`; the duplication exists only to satisfy tests and obscures where correction happens.
- **Fix:** Collapse to one method; make `TranscriptionPipeline` the sole public entry point.
- **Effort:** M
- **Grade lift:** B → B+ (clearer single entry point)

#### B3 — `deleteRecord` does a full-table fetch + double store rebuild
- **Where:** `DataManager.swift:306-308`
- **What's wrong:** Deleting one row fetches *all* records and rebuilds both `UsageMetricsStore` and `SourceUsageStore` — O(history size) per delete; multi-select deletes become quadratic.
- **Fix:** Decrement metrics incrementally from the deleted record, or batch deletes and rebuild once.
- **Effort:** M
- **Grade lift:** B → B+ (removes a quadratic data-layer path)

#### B4 — Unused chunking constants in SemanticCorrectionService
- **Where:** `SemanticCorrectionService.swift:39-40`
- **What's wrong:** `chunkSizeWords`/`overlapSizeWords` are declared with detailed comments but never referenced — the whole transcript is sent to MLX in one request.
- **Fix:** Either implement chunked correction (see G3) or delete the dead constants.
- **Effort:** S (delete) / L (implement)
- **Grade lift:** B → B (removes dead code or closes a real gap)

#### ~~B5~~ ✓ done 2026-05-16 — Expiry cleanup runs synchronously on every save
- **Where:** `DataManager.swift:168`
- **What's wrong:** `saveTranscription` awaits `cleanupExpiredRecordsQuietly()` (another predicate fetch) on the critical path of every transcription save.
- **Fix:** Fire-and-forget cleanup in a detached Task, or throttle to once per session.
- **Effort:** S
- **Grade lift:** B → B (shortens the save critical path)

#### B6 — `nonisolated(unsafe)` singleton accessor
- **Where:** `DataManager.swift:100-102`
- **What's wrong:** The shared instance is force-cast onto the main actor with `nonisolated(unsafe)`, defeating concurrency checking.
- **Fix:** Use a `@MainActor` static or a lazy main-actor accessor.
- **Effort:** S
- **Grade lift:** B → B (sound concurrency)

---

## C — Frontend / SwiftUI Quality — B−

View decomposition is good — 69 small files, heavy `+Extension` splits, only ~2 files over 450 lines. Theming is disciplined (`DashboardTheme`, `WaveformPalette` consistently referenced) and state management is modern (`@AppStorage` fully replaced by the typed `@AppDefault` wrapper, stores use `@Observable`). The grade is held down by **accessibility**: only ~15 of 69 views carry any `accessibility*` modifier, and the control-dense Dashboard has near-zero VoiceOver coverage.

#### C1 — Dashboard accessibility gap
- **Where:** `Sources/Views/Dashboard/*` (e.g. `DashboardProvidersView.swift`, `DashboardCorrectionView.swift`)
- **What's wrong:** The most control-heavy screens lack `.accessibilityLabel`/`.accessibilityValue`/`.accessibilityHint`; VoiceOver users can't reliably distinguish toggles and pickers.
- **Fix:** Add labels/values/hints to interactive controls, prioritizing Providers, Correction, Preferences.
- **Effort:** M
- **Grade lift:** B− → B (closes the largest UX-quality gap)

#### ~~C2~~ ✓ done 2026-05-16 — `AppDefault` equality fallback is unsafe
- **Where:** `Sources/Stores/AppDefault.swift:44-56`
- **What's wrong:** `valuesEqual` returns `false` for any non-`AnyHashable` value, forcing a `DispatchQueue.main.async` write on every `update()`; the async re-read can also lag a frame.
- **Fix:** Constrain `Value: Equatable` (or add an `Equatable`-specialized path) and compare directly.
- **Effort:** S
- **Grade lift:** B− → B (removes redundant writes / a frame-lag risk)

#### C3 — Oversized `WaveformContainer`
- **Where:** `Sources/Views/Components/Waveform/WaveformContainer.swift` (~548 lines)
- **What's wrong:** The largest view file bundles glow, vignette, particles, status row, transition logic, shimmer, and helpers in one file.
- **Fix:** Extract the status row, vignette, and the small helper views into `+Extension`/subview files, matching the rest of the codebase.
- **Effort:** M
- **Grade lift:** B− → B (consistency with the established decomposition)

#### C4 — Loading/empty/error states are localized, not systematic
- **Where:** only `Transcription/TranscriptionHistoryEmptyState.swift` + `...LoadingView.swift`; dashboard sections gate on `isLoaded` booleans (`DashboardHomeView.swift`)
- **What's wrong:** No shared empty/error component; dashboard data-load failures surface no error UI at all.
- **Fix:** Add a reusable `ContentUnavailableView`-style component and surface load errors in the dashboard.
- **Effort:** M
- **Grade lift:** B− → B (consistent failure UX)

#### C5 — Aggregation logic lives inside views
- **Where:** `DashboardHomeView.swift` (`computeStreak`, `computeProviderStats`, etc. as static helpers on the view)
- **What's wrong:** Stat computation embedded in a view (only 3 ViewModels for 69 views) isn't cleanly unit-testable except via `testable*` shims.
- **Fix:** Move stat computation into a `DashboardHomeViewModel` or the relevant store.
- **Effort:** M
- **Grade lift:** B− → B (testable view logic)

---

## D — Testing & Reliability — C+

193 test files with a 60% CI line-coverage gate is real infrastructure, and a few genuine integration suites exist. But **depth is weak**: `TranscriptionPipelineTests.swift` — named for the app's core path — is mostly struct-field assertions, and its only real `transcribe()` calls swallow everything into `catch { XCTAssertTrue(true) }`. There are ~52 `XCTAssertTrue(true)` tautologies across the suite, and **zero** files use the declared `ViewInspector` dependency, so "view tests" are init-only smoke tests. CI honestly runs `--no-parallel` because the UserDefaults-isolation migration is incomplete.

#### ~~D1~~ ✓ done 2026-05-16 — Core pipeline tests assert nothing on the happy path [test]
- **Where:** `Tests/TranscriptionPipelineTests.swift:90-136`
- **What's wrong:** The only `transcribe()`/`transcribeRaw()` tests catch all errors into `XCTAssertTrue(true)` — a broken transcription pipeline still passes CI.
- **Fix:** Inject a mock provider; assert the returned transcript text and the progress-step sequence on the success path.
- **Effort:** M
- **Grade lift:** C+ → B− (the app's core path gets real coverage)

#### ~~D2~~ ✓ done 2026-05-16 — Purge `XCTAssertTrue(true)` cop-outs [test]
- **Where:** ~52 occurrences repo-wide across `Tests/`
- **What's wrong:** A tautology that passes regardless of behavior; each one masks a potential regression and inflates the apparent test count.
- **Fix:** Replace each with a concrete assertion, or `XCTFail` in the unexpected branch.
- **Effort:** M
- **Grade lift:** C+ → B− (test count starts reflecting real coverage)

#### D3 — No real view tests despite the ViewInspector dependency [test]
- **Where:** `Package.swift:17` declares `ViewInspector`; 0 `inspect()` usages in `Tests/`
- **What's wrong:** View "tests" only construct views; rendered state, bindings, and conditional UI are never asserted.
- **Fix:** Use ViewInspector to assert rendered state on a few high-value views (recording window states, dashboard tabs), or drop the dependency.
- **Effort:** M
- **Grade lift:** C+ → B− (view behavior actually verified)

#### D4 — Finish IsolatedXCTestCase migration to re-enable `--parallel` [test]
- **Where:** `ci.yml:66-70`; only ~52/193 test files subclass `IsolatedXCTestCase`
- **What's wrong:** Tests share `UserDefaults.standard` and fail nondeterministically in parallel, so CI is forced serial — slower loop, latent isolation bugs.
- **Fix:** Migrate all UserDefaults-touching tests to suite-scoped defaults, then drop `--no-parallel`.
- **Effort:** L
- **Grade lift:** C+ → B− (faster CI, catches isolation bugs)

---

## E — Security — B

Solid fundamentals. `KeychainService` uses the Security framework directly with `kSecAttrAccessibleWhenUnlocked`. The embedded-Python path is **not** injection-prone — `MLDaemonManager` passes `repo`/`pcm_path` as JSON-RPC params over a pipe (never shell-interpolated) and the subprocess uses `executableURL` + `arguments`. The bundled `uv` binary is SHA-256 verified at launch. Weaknesses: model integrity is trust-on-first-use only, there is no entitlements/hardened-runtime/sandbox config in the repo, the Python daemon inherits the full parent environment, and SwiftData transcripts are stored unencrypted.

#### ~~E1~~ ✓ done 2026-05-16 — Trust-on-first-use accepts a poisoned first model download
- **Where:** `Sources/Utilities/DiskMutationSerializer.swift:75-87` (`ModelIntegrity`)
- **What's wrong:** With no sidecar, the first download is trusted unconditionally and its hash persisted — a tampered initial download is silently accepted forever.
- **Fix:** Ship known-good SHA-256s for the app's shipped model repos (as already done for `uv`); keep TOFU only for user-added models.
- **Effort:** M
- **Grade lift:** B → B+ (closes the model supply-chain hole)

#### E2 — No hardened runtime / app sandbox / entitlements in the repo
- **Where:** no `.entitlements` file in the repository
- **What's wrong:** Hardened runtime and sandboxing aren't declared in-repo, so notarization hardening and least-privilege depend on ad-hoc local build steps.
- **Fix:** Add an entitlements file enabling hardened runtime + sandbox with explicit microphone/network exceptions; wire it into the build.
- **Effort:** M
- **Grade lift:** B → B+ (defensible, reproducible security posture)

#### ~~E3~~ ✓ done 2026-05-16 — Python daemon inherits the full process environment
- **Where:** `Sources/Managers/MLDaemonManager+Process.swift:27`
- **What's wrong:** The subprocess merges all of `ProcessInfo.environment`, exposing the parent's full environment to bundled Python.
- **Fix:** Pass a minimal allowlisted environment (`PATH`, `HOME`, `PYTHONUNBUFFERED`, required venv vars).
- **Effort:** S
- **Grade lift:** B → B (least-privilege subprocess)

#### E4 — Transcripts stored unencrypted with no file protection
- **Where:** `Sources/Stores/DataManager.swift:128-137`
- **What's wrong:** `TranscriptionRecord` is plain SwiftData with no file protection — transcribed text (potential PII) sits in cleartext on disk.
- **Fix:** Apply file protection to the store, or document the threat model and offer an opt-in.
- **Effort:** M
- **Grade lift:** B → B+ (PII at rest is protected)

---

## F — Dependencies & Tech Currency — B+

Only 3 direct dependencies, all reasonably current: KeyboardShortcuts `1.17.0`, WhisperKit `0.15.0`, ViewInspector `0.10.3`. The KeyboardShortcuts `<2.0` pin is a genuine, well-documented constraint (2.x needs Swift 6 language mode, incompatible with the universal Swift-5 release build). Main friction: `swift-tools-version:5.9` lags the effectively-Swift-6 toolchain, and there's no automated dependency-alert config.

#### F1 — No Dependabot / automated dependency alerts
- **Where:** no `.github/dependabot.yml`
- **What's wrong:** Stale pins and dependency CVEs only surface by manual inspection.
- **Fix:** Add a `dependabot.yml` covering Swift Package Manager and GitHub Actions.
- **Effort:** S
- **Grade lift:** B+ → A− (continuous dependency-currency signal)

#### F2 — `swift-tools-version:5.9` lags the toolchain
- **Where:** `Package.swift:1`
- **What's wrong:** A 5.9 tools-version against an effectively Swift-6 toolchain is an avoidable straddle that blocks newer manifest features.
- **Fix:** Bump to a 5.10/6.0 tools-version (keep `.swiftLanguageVersions = [.v5]` if needed for the release build).
- **Effort:** S
- **Grade lift:** B+ → B+ (reduces version straddle)

#### F3 — CLAUDE.md lists dependencies the project no longer uses
- **Where:** `CLAUDE.md` "Key Dependencies" (claims Alamofire + KeychainAccess; neither is in `Package.swift`/`Package.resolved`)
- **What's wrong:** Stale dependency docs mislead future security/dependency audits.
- **Fix:** Correct the dependency list to the actual 3 packages.
- **Effort:** S
- **Grade lift:** B+ → B+ (accurate dependency picture)

#### F4 — Track the KeyboardShortcuts 2.x upgrade path
- **Where:** `Package.swift:9-12`
- **What's wrong:** The `<2.0` pin is sound today but indefinitely blocks a maintained major version.
- **Fix:** Track migrating the universal release build to Swift 6 language mode so the pin can eventually lift; record a target.
- **Effort:** L
- **Grade lift:** B+ → A− (no indefinitely-frozen dependency)

---

## G — Performance & Scalability — B−

The audio hot path is handled well — the recorder tap writes unthrottled and throttles only the level *publish* to 60 Hz; `ParakeetService.loadAudio` streams via `ExtAudioFile` in chunks. The drag is the waveform layer: nine separate views each install their own always-on 30 fps `Timer.publish`, plus several blocking-I/O and full-recording-in-memory paths.

#### ~~G1~~ ✓ done 2026-05-16 — Always-on 30 fps timers in every waveform view
- **Where:** all 9 waveform views — e.g. `SpectrumWaveformView.swift:79`, `ConstellationWaveformView.swift:70`, `HeartbeatPulseView.swift:82`, plus `LivePreviewSampler`
- **What's wrong:** Each `Timer.publish(every: 0.033)` autoconnects on view init and never stops — even when `isActive == false` or the window is hidden. The Visuals grid animates all 8 styles at once = ~240 main-thread updates/sec; constant wakeups drain battery.
- **Fix:** Gate each timer on `isActive`/visibility, or drive all styles from one shared `TimelineView(.animation)`.
- **Effort:** M
- **Grade lift:** B− → B (removes constant idle main-thread churn)

#### G2 — `loadAudio` materializes the entire recording in memory
- **Where:** `ParakeetService.swift:137-143`
- **What's wrong:** A 10-minute 16 kHz recording is ~38 MB of `[Float]`, then copied again into `Data` before writing a temp file — roughly 2× peak memory.
- **Fix:** Stream PCM chunks straight to the temp file inside the read loop instead of buffering all samples.
- **Effort:** M
- **Grade lift:** B− → B (bounded memory for long recordings)

#### G3 — Whole transcript sent to MLX correction in one request
- **Where:** `MLXCorrectionService.swift:57-64` + the unused chunking constants (B4)
- **What's wrong:** Long dictations can exceed the model context window; correction then silently fails or truncates with no chunking.
- **Fix:** Implement the declared word-chunking with overlap, or cap input and degrade gracefully.
- **Effort:** L
- **Grade lift:** B− → B (correctness for long-form audio)

#### G4 — Blocking `waitUntilExit()` on cooperative threads
- **Where:** `UvBootstrap+Process.swift:44`, `PythonDetector.swift:62,90`, `MLXModelManager+Downloads.swift:172,409`
- **What's wrong:** Synchronous `process.run()` + `waitUntilExit()`; if invoked from an `async` context without a detached executor, it stalls a cooperative-pool thread during venv sync / model downloads.
- **Fix:** Wrap in `Task.detached`, or read pipes asynchronously with a `terminationHandler`.
- **Effort:** M
- **Grade lift:** B− → B (no thread-pool starvation during setup)

#### G5 — `getDailyActivity` / streak recompute on every read
- **Where:** `UsageMetricsStore.swift:136-168`
- **What's wrong:** Called from SwiftUI views, these rebuild date dictionaries and loop calendars on each access — and with `@Observable` can recompute per re-render.
- **Fix:** Memoize, invalidating on `persist`.
- **Effort:** S
- **Grade lift:** B− → B− (cheaper dashboard renders)

#### G6 — `MicTestCapture.handleBuffer` allocates per audio callback
- **Where:** `Sources/Views/Components/Waveform/MicTestCapture.swift:139-169`
- **What's wrong:** Every ~64 ms it allocates a fresh sample array, a downsample array, and FFT bands, then hops to `@MainActor` via a new `Task` — allocation churn driven by the realtime audio thread.
- **Fix:** Reuse preallocated scratch buffers; coalesce the main-actor hop.
- **Effort:** S
- **Grade lift:** B− → B− (steadier realtime audio path)

---

## H — Documentation & Onboarding — A−

Documentation is a clear strength. `README.md` accurately covers all three install paths, system requirements, per-engine setup, and a Parakeet/MLX troubleshooting section. The embedded-Python/`uv` story is documented and there's a real `docs/adr/` directory with 4 ADRs (including 0004 documenting the `@AppDefault` migration the code reflects). `CONTRIBUTING.md` and `Tests/README.md` are substantial; core services carry useful inline docs.

#### H1 — README clone URL + missing redeploy caveat
- **Where:** `README.md` (Option 3 build steps)
- **What's wrong:** The `git clone` URL points at the upstream `mazdak/AudioWhisper` fork parent, and the build section omits the `pkill`/`rm -rf` redeploy + Accessibility re-grant step documented in `CLAUDE.md`.
- **Fix:** Point the clone URL at the canonical repo and note the redeploy/permission caveat.
- **Effort:** S
- **Grade lift:** A− → A− (accurate onboarding)

#### H2 — `MLDaemonManager` under-documented
- **Where:** `Sources/Managers/MLDaemonManager.swift`
- **What's wrong:** A long-lived Python subprocess manager with non-obvious lifecycle/restart/IPC behavior has only light inline docs.
- **Fix:** Add a class-level doc block covering process lifecycle, failure recovery, and the request protocol.
- **Effort:** S
- **Grade lift:** A− → A− (the trickiest subsystem becomes legible)

#### H3 — ADR 0004 status is stale
- **Where:** `docs/adr/0004-app-storage-migration.md:3`
- **What's wrong:** Marked **Proposed**, but the migration is fully implemented (`@AppStorage` has zero occurrences in `Sources/`).
- **Fix:** Update the status to **Accepted/Implemented** with a completion date.
- **Effort:** S
- **Grade lift:** A− → A− (ADR reflects reality)

#### H4 — No architecture diagram / module map
- **Where:** `docs/` (only ADRs)
- **What's wrong:** `CLAUDE.md` has a prose architecture section, but there's no contributor-facing doc tying Services/Stores/Managers/Views together.
- **Fix:** Add `docs/ARCHITECTURE.md` with a component map and a data-flow sketch.
- **Effort:** M
- **Grade lift:** A− → A (a reference-quality onboarding doc)

---

## I — Developer Experience & Tooling — A−

Tooling is genuinely strong. `ci.yml` gates `swiftlint --strict` in a dedicated job, enforces a 60% coverage threshold, bans production `print()`, and runs a `bundle-smoke-test` that validates the `.app` end-to-end. CodeQL and SonarCloud (with lcov export) are both wired. `.swiftlint.yml` is well-tuned. Two real weaknesses: the suite is forced `--no-parallel` by test-isolation debt, and there are no git pre-commit hooks.

#### I1 — Test-isolation debt forces `--no-parallel`
- **Where:** `ci.yml:66-77`, `scripts/run-tests.sh`
- **What's wrong:** Shared `UserDefaults.standard` makes tests fail nondeterministically in parallel; the suite runs serially, slowing the loop and signaling latent flakiness. (Same root cause as D4.)
- **Fix:** Complete the `IsolatedXCTestCase` migration, then enable `--parallel`.
- **Effort:** L
- **Grade lift:** A− → A (faster, more honest CI)

#### I2 — No pre-commit hooks
- **Where:** `.git/hooks/` (empty)
- **What's wrong:** Lint, format, and `print()` violations only surface in CI, lengthening the feedback loop.
- **Fix:** Add a pre-commit hook (or `lefthook`/`pre-commit`) running `swiftlint --strict` on staged Swift files.
- **Effort:** S
- **Grade lift:** A− → A− (faster local feedback)

#### I3 — `.swift-format` config exists but is never run
- **Where:** root `.swift-format`; no CI step or script invokes `swift-format`
- **What's wrong:** A formatter config exists but formatting is unenforced — config drift with no payoff.
- **Fix:** Add a `swift-format lint` step to the `lint` job (or a Makefile target), or remove the config.
- **Effort:** S
- **Grade lift:** A− → A− (formatting actually enforced)

#### I4 — Brittle `print()`-detection shell logic in CI
- **Where:** `ci.yml:133-150`
- **What's wrong:** The `#if DEBUG` detection re-implements preprocessor scanning in ~50 lines of bash with a lookback heuristic — fragile and hard to maintain.
- **Fix:** Replace with a SwiftLint custom rule for `print(` outside `DEBUG`.
- **Effort:** M
- **Grade lift:** A− → A− (robust, declarative check)

#### I5 — VersionInfo generation duplicated across 3 places
- **Where:** `ci.yml:44-59`, `sonarcloud.yml:34-44`, `scripts/build.sh`
- **What's wrong:** The same `sed`-substitution block is copy-pasted in three workflows — drift risk.
- **Fix:** Extract to a single `scripts/gen-version.sh` invoked everywhere.
- **Effort:** S
- **Grade lift:** A− → A− (one source of truth for versioning)
