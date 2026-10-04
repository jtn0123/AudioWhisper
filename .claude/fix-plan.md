# Fix Plan — approved 2026-07-31

Working branch: `grade-fixes-2026-07`
Source report: `.claude/grade-report.md` (numbered action plan at top)

**Scope:** items 1–10, 12–20. Item **11** (nightly CI for E2E test) was NOT approved — leave alone.

**Rules for this run**
- One item = one commit. Never squash unrelated items.
- `swift build` must stay clean (0 warnings) after every item.
- Full test suite before any commit touching Sources/.
- Never push. Never touch the `upstream` remote (mazdak/AudioWhisper).
- If an item turns out bigger than estimated, STOP and flag it rather than half-doing it.

---

## Progress

Legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked / needs user input

### Phase 1 — Quick wins (low risk, fast)
- [x] **8** — Fix CI print() gate that can never fail (`ci.yml:134-150` subshell bug) → I1
      `ac5d407` · verified: seeded print() now exits 1, #if DEBUG-wrapped exits 0
- [x] **15** — Dark-mode sidebar hover/selection invisible (`DashboardView.swift:33-34`) → C4
      `e5c6270` · Color.black → Color.primary; added a regression test proven to
      fail against the old code
- [x] **16** — Stop logging Python stderr publicly (`MLDaemonManager+Process.swift:72`) → E2
      `b909c71` · public field now exception TYPE only; full text at `.private`.
      6 tests incl. one proving dictated text + home path can't reach the summary
- [x] **12** — Delete unused DependencyContainer (160 lines, 0 refs) → A1
      `5b029d7` · also deleted its 11-test suite (tests protecting dead code).
      Suite 2805 → 2801 (-11 +7 new). Build clean.
- [x] **4** — Correction runs Llama when UI recommends Qwen3 → B1
      `d0f3a70` · added `AppDefaults.defaultSemanticCorrectionModelRepo` as single
      source of truth; 5 production sites routed through it; one-time migration
      pins existing users w/ legacy model on disk (no surprise 1 GB download).
      ALSO FOUND: MLXModelManagementView badged Llama while DashboardCorrectionView
      badged Qwen3 — two screens disagreeing. Fixed. 8 tests. Suite → 2809.
- [x] **18** — Delete leftover OpenAI/Gemini dead code → A4
      `664c4e2` · ⚠️ AUDIT ITEM WAS PARTLY WRONG. The provider display mappings
      are NOT dead — `TranscriptionRecord.provider` is a persisted raw String, so
      pre-2.0 history still contains "openai"/"gemini". Kept + documented.
      Removed what IS dead: cloud prompt files written every launch,
      `AppDelegate.hasAPIKey` (0 callers) + its 5 tests, stale comments.
      Suite 2809 → 2804.
- [x] **19** — 3 always-on timers bypassing FrameTimer → C3/G1
      `ff91f68` · converted to FrameTimer + added custom SwiftLint rule
      `no_autoconnected_timer` (verified: valid config, 0 current violations,
      fires on reintroduction). Also fixed a trailing comma item 18 left behind.

**PHASE 1 COMPLETE** — 7/19. Build clean, strict lint clean, 2804 tests, 0 failures.

### Phase 2 — Documentation
- [x] **1** — Rewrite README (cloud providers removed, upstream links) → H1
      `81eff27` · KEY FACTS VERIFIED: jtn0123/AudioWhisper has ZERO releases and
      jtn0123/homebrew-tap does NOT exist → build-from-source is the only honest
      install path for this fork. Also corrected: Smart Paste needs Accessibility
      (not Input Monitoring — no IOHIDCheckAccess in codebase); real Dashboard tabs
      are Overview/Transcripts/Categories/Input/Models/Visuals/General/Permissions
      (README said Providers/Preferences/Correction — none exist); "storage cap
      slider" doesn't exist; Alamofire is no longer a dependency.

**PHASE 2 COMPLETE** — 8/19.

### Phase 3 — Supply chain + dependency caps
- [x] **2** + **5** — uv.lock shipped & enforced; mlx-lm/parakeet-mlx caps raised
      `8f41f25` · done together (same files, one `uv lock`).
      FLAG SEMANTICS (verified, not assumed): `--frozen` = install exactly what's
      locked, never re-resolve; it does NOT validate lock vs pyproject (that's
      `--locked`). Drift fails closed. Added CI `uv lock --check` (verified: 0 in
      sync, 1 on drift).
      Now: mlx-lm 0.31.3, parakeet-mlx 0.5.2, mlx 0.32.0.
      ⚠️ REAL BREAK FOUND + FIXED: mlx-lm moved sampling from `generate(temp=,
      top_p=)` to an explicit `sampler=` callable. correction.py's existing
      `except TypeError` would have silently degraded EVERY correction to greedy
      decoding. Rewrote `_safe_generate` to use `make_sampler`, legacy kwargs and
      bare call as ordered fallbacks. Verified against a real 0.31.3 install.

**PHASE 3 COMPLETE** — 10/19.

### Phase 4 — Test infrastructure
- [~] **7** — Enable `swiftlint analyze` in CI → I2 — **PARTIAL, report-only**
      `435ce7e` · Analyzer rules had NEVER run (configured, but `lint` ignores them).
      Tooling notes: `swift build -v` produces an UNPARSEABLE log ("Cannot index
      file at path…"); must use `xcodebuild ... build-for-testing` (plain `build`
      makes every *ForTesting helper look unused).
      ⚠️ SCOPE FLAG: first run = ~214 unused_declaration + ~117 unused_import,
      many FALSE POSITIVES (mock members satisfying protocols, SwiftUI
      conformances, `import Cocoa` in an NSImage extension). Triage is an L-effort
      job, not the half-day scoped. Landed as `continue-on-error` reporting job,
      per the audit's own "non-blocking first" remediation. **Backlog triage +
      making it strict is still outstanding — needs a separate decision.**
- [~] **3** — Find and fix the flaky test → D1 — **NOT REPRODUCED**
      `0b0b92b` · 12 dedicated sequential runs + ~8 more during this branch: ALL
      GREEN. Original 3-failure log was truncated by `tail -200` so the test names
      were lost. NOTE: AudioWhisper.app was running (PID 2034) during that first
      run — same UserDefaults domain. Root cause is the same shared state as 17.
- [!] **17** — Enable parallel → D4 — **ATTEMPTED, REVERTED, NEEDS DECISION**
      Reproducible: `--parallel` fails EVERY run (4/4/2 failures), always in the
      6 classes with `enforcesStandardUserDefaultsIsolation = false`.
      TRIED: redirect `AppDefaults.defaults` to a pid-suffixed suite via env var.
      RESULT: WORSE — 12-14 failures. Only 6 of the 48 files that touch
      `.standard` are the racers; the other 42 WRITE `.standard` in setUp and
      assert production reads it back. Splitting the store breaks those 42.
      → Real scope: migrate all 48 onto scoped suites. Well beyond 1-2 days.
      Reverted rather than ship a regression. **Needs user decision on scope.**
      DELIVERED anyway: `run-tests.sh` exit-code bug fixed (it returned grep's
      status, so a red suite exited 0). Verified both directions.
- [~] **10** — Re-enable snapshot tests → D2 — **PARTIAL, report-only**
      `7d4237c` · 🔥 **FOUND A REAL CRASH**: `DialWaveformView` trapped
      "Index out of range" on empty `frequencyBands` — `max(1, count)` made
      `index % 1 == 0` subscript an EMPTY array. Renders at rest, so this was a
      shipped crash for anyone using the Dial waveform style. Fixed to match
      HaloWaveformView's guard. Added `WaveformEmptyInputRenderingTests` (proven
      to crash without the fix). Existing waveform tests only CONSTRUCT views, so
      `body` never ran — that's why it hid.
      Added `tolerance:` to assertSnapshot. MEASURED: 31/39 snapshots byte-identical
      across back-to-back recordings; 8 vary ≤1.9% (animated + `CGFloat.random`).
      ⚠️ CANNOT be blocking yet: exact RGBA match + baselines recorded on a
      different macOS → 14/36 differ from environment alone, and 3 waveform
      baselines were NEVER committed. CI job uploads renders as an artifact so
      baselines can be regenerated on the runner. **Did NOT commit my local
      baselines (macOS 27) — can't validate against CI's macos-15.**

**PHASE 4 DONE (with caveats)** — 14/19 attempted; 7, 17, 10 partial.

### Phase 5 — Performance + accessibility
- [x] **20** — Stop loading full history into memory on delete → B5/G2
      `ba38422` · added incremental `remove(record:)` to both stores + SwiftData
      batch delete for delete-all. 7 tests, key one asserts incremental == full
      rebuild. Caveat documented: SourceUsageStore.lastUsed left untouched
      (cosmetic sort-order only).
- [~] **13** — Accessibility labels (Dashboard + Welcome) → C1 — **PARTIAL (by design)**
      `cb2d79c` · Fixed the worst offenders: UnifiedModelRow (backs EVERY model
      list), WelcomeView style picker (8 identical-sounding buttons), sidebar nav
      (no .isSelected trait), Dashboard stat tiles. 7 tests assert composed
      strings, not modifier presence. Coverage 12/69→22/69 files, 52→93 calls.
      REMAINING: lower-traffic files; should be driven by an Accessibility
      Inspector audit rather than more grep-guessing.

**PHASE 5 DONE** — 17/19.
- [x] **14** — Honor Reduce Motion → C2
      `fa0893f` · KEY CONSTRAINT: `accessibilityReduceMotion` is a READ-ONLY
      environment key — cannot be injected in tests. So WaveformContainer reads it
      once and passes it down as a parameter (better layering anyway).
      Suppressed: celebration, transitions, shake, particles, ripples.
      NOT suppressed: waveform (functional feedback). 4 pixel tests.
      NOTE: "renders when OFF" is not pixel-testable (effects need onAppear;
      ImageRenderer captures one static frame) — documented in the test file.
      FOUND: `ViewInspector` is a declared test dependency that NO test imports.

### Phase 6 — Large migrations (highest risk, done last)
- [x] **9** — WhisperKit 0.15 → Argmax OSS SDK 1.0 → F1
      `3927872` · Turned out SMALL: new package still vends a `WhisperKit`
      product, so all imports/APIs unchanged — only the URL moved.
      VERIFIED: clean build (same 6 pre-existing warnings, none new), 2824 tests
      green, AND the universal arm64+x86_64 release build (the flagged risk).
      SIDE EFFECT: dep graph 7 → 4 packages; swift-jinja/transformers/collections
      gone. That invalidated the documented reason for Xcode 16 — now it's
      swift-argument-parser 1.8.x declaring tools-version 6.0. Updated the
      rationale in ci.yml, codeql.yml, sonarcloud.yml, README.
      AVAILABLE BUT NOT ADOPTED: SpeakerKit (diarization) + TTSKit ship in the
      same package now — a feature decision, not part of this migration.
- [x] **STT picker** (user request, outside original 20) — `109e642`
      Added `parakeet-tdt_ctc-110m` (0.46 GB vs 2.51 GB). Verified drop-in:
      parakeet-mlx 0.5.2 dispatches on config.json `target`; this model's
      `EncDecHybridRNNTCTCBPEModel` is supported. Fixed misleading v2 label —
      v2 is the MOST ACCURATE English option (6.05% vs v3 6.32% WER), not "the
      original". `description` was dead (never rendered); now shown.
      NOT drop-in (need mlx-audio, new Python): Qwen3-ASR, Nemotron streaming,
      Voxtral, Granite Speech. Canary (accuracy leader, 5.63%) has NO MLX port.
- [x] **6** — Benchmark correction models → F4 — **DONE, recommendation NOT applied**
      Full results + harness retained in `.claude/bench/`.
      WINNER: `Qwen3-4B-Instruct-2507-4bit` — 5/6 safeMerge, 5/6 homophones,
      0/6 filler left, and 1.8× FASTER than the current default despite being
      2.3× bigger (non-thinking Instruct → no think-then-retry round trip).
      Newer ≠ better: Qwen3.5-4B and gemma-4-e2b both scored 0/6.
      ⚠️ Catalog swap itself is still TODO — see New Issues below.
      Needs downloading 3-4 candidate models (~1-4 GB each) and benchmarking them
      on real transcripts. That spends the user's bandwidth and disk, so it needs
      explicit go-ahead. Prerequisite (item 5, mlx-lm 0.31) is already done, so
      newer architectures will now load.

---

## Notes / decisions log

_(append as work proceeds — this survives context compaction)_

- ⚠️ **BUILD REQUIRES `DEVELOPER_DIR`.** Mid-session, `xcode-select -p` flipped to
  `/Library/Developer/CommandLineTools`, which has no `actool`, so `swift build`
  fails on the asset catalog. Only `/Applications/Xcode-beta.app` is installed.
  Prefix every build/test command:
  `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
  Same Swift 6.4 either way, so results are comparable. NOT fixing this globally
  (`sudo xcode-select -s`) — that's a system-wide change to the user's machine.
  Worth raising with the user at the end.
- ⚠️ **CORRECTION to the grade report:** it claimed "clean build, 0 warnings". That
  was measured on an INCREMENTAL build. A true clean build (`rm -rf .build`) emits
  **6 distinct pre-existing warnings**, all Swift 6 concurrency diagnostics:
  `AppCategoryManager.swift:76`, `PressAndHoldKeyMonitor.swift:342`,
  `AudioEngineRecorder.swift:75`, `AudioRecorder.swift:29`,
  `MicTestCapture.swift:192`, `CategoryEditorSheet.swift:25`.
  Five say "…this is an error in the Swift 6 language mode."
  **This directly affects item 9/F2**: adopting Swift 6 language mode turns these
  into build errors. Budget for fixing them as part of that migration.
- 2026-07-31: Plan created. Baseline verified: `swift build` clean 0 warnings;
  `swift test --no-parallel` = 2805 tests, 37 skipped, flaky (1 of 5 runs had 3 failures).
- OUTSTANDING (not approved yet): fork safety fix — `upstream` remote is push-enabled
  and `gh` resolves default repo to mazdak/AudioWhisper. Offered, no answer yet.

---

## OUTSTANDING — as of 2026-07-31

### A. New issues found during the work (not in the original 20)

**A1. Think-stripper only understands one tag format** *(found by item 6 benchmark)*
`Sources/ml/correction.py` strips `<think>…</think>` and truncated `<think>…`.
But gemma-4 emits `<|channel>thought`, and Qwen3.5 emits bare `Thinking Process:`
with NO tags. Neither is stripped → chain-of-thought lands in the transcript →
safeMerge discards the whole correction. Both models scored 0/6 purely from this.
The retry path never fires because stripping leaves a non-empty (wrong) string.

**A2. Chat-template special tokens not stripped** *(found by item 6 benchmark)*
Phi-3.5-mini's correction is CORRECT but arrives as
`Remember to call the dentist tomorrow morning.<|end|><|assistant|> Remember to…`
— right answer, repeated, with template tokens. Ratio 0.6083, just past the 0.6
cutoff → discarded. Phi ships labelled "Premium quality"; users picking it get
corrections silently dropped 5 of 6 times.

**A3. safeMerge's 0.6 threshold fights the Terminal category** *(found by item 6)*
Perfect correction, discarded (ratio 0.664):
```
in : um so run suit oh apt update and then uh see dee into tilde slash documents…
out: sudo apt update && cd ~/Documents && grep -v error | less
```
Good terminal correction legitimately COMPRESSES rambling into terse commands.
Threshold is calibrated for prose. Fix: per-category `maxChangeRatio`
(prose ~0.6, terminal ~0.85), or compare against a normalised form.

**A4. Apply the benchmark recommendation** — swap default/RECOMMENDED to
`Qwen3-4B-Instruct-2507-4bit`; keep gemma-3-1b-qat as the fast/light option;
retire Phi-3.5-mini and Llama-3.2-1B. Needs the item-4 migration extended.

**A5. Six pre-existing Swift 6 concurrency warnings** — `AppCategoryManager:76`,
`PressAndHoldKeyMonitor:342`, `AudioEngineRecorder:75`, `AudioRecorder:29`,
`MicTestCapture:192`, `CategoryEditorSheet:25`. Five say "error in Swift 6
language mode". These BLOCK adopting Swift 6, which in turn blocks A6.

**A6. KeyboardShortcuts is 2 majors behind** (1.17.0 → 3.0.1) — was audit item F2,
never made the top 20. Blocked on A5. 3.0.1 includes a Swift 6.3 compiler crash fix.

**A7. ViewInspector is a declared test dependency no test imports.** Either adopt
it (it would let us test the Reduce-Motion "OFF" direction — see item 14) or drop it.

### B. Approved items that landed partial

- **7** — `swiftlint analyze` runs report-only. Backlog is ~214 unused_declaration
  + ~117 unused_import, many false positives. Triage, then drop `continue-on-error`.
- **17** — parallel tests. Needs all 48 files touching `UserDefaults.standard`
  migrated to scoped suites. The 6-file shortcut REGRESSES it (proven).
- **10** — snapshot baselines must be regenerated ON the CI runner (exact-RGBA
  comparison; 14/36 differ by environment, 3 never committed). CI job uploads
  renders as an artifact for adoption.
- **13** — accessibility: worst offenders fixed (12/69 → 22/69 files). Remainder
  should be driven by an Accessibility Inspector audit, not grep.

### C. Never approved
- **11** — nightly CI for the Parakeet E2E test (comment claims it runs nightly; no
  such workflow exists, so the core transcription path has zero automated coverage).

### D. Environment / repo hygiene (not code)
- **Fork safety, still pending user OK:** `upstream` remote is push-enabled and
  `gh` resolves the default repo to `mazdak/AudioWhisper`. One `git remote set-url
  --push upstream DISABLED` + `gh repo set-default jtn0123/AudioWhisper`.
- **`xcode-select` points at CommandLineTools** (no `actool`), so bare
  `swift build` fails. All work used
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
- **Nothing has been pushed.** 17 commits on `grade-fixes-2026-07`; `master` clean.

---

## SESSION 2 — 2026-08-01 — "do them all"

All items from the outstanding list attempted. Commits `fc5f737`..`e91e14f`.

- [x] **A1+A2+A3+A4** `fc5f737` — correction output handling + benchmark applied.
      Think-stripper now handles gemma-4's `<|channel>thought` and Qwen3.5's bare
      `Thinking Process:`; chat-template tokens stripped (fixed Phi's 0.6083
      near-miss); safeMerge threshold per-category (terminal/coding 0.85 vs prose
      0.6); default → Qwen3-4B-Instruct-2507. Also fixed two problems the catalog
      change CREATED: retired models would strand users (picker now lists
      downloaded-but-uncurated models) and the default flip would force a surprise
      2.3 GB download (migration generalised to all prior defaults).
- [x] **A5** `c28fe8d` — 6 Swift 6 warnings → 0. Five were @MainActor statics used
      as DEFAULT ARGUMENTS (evaluated in the caller's isolation). The sixth:
      @MainActor was the WRONG fix for PressAndHoldKeyMonitor (turned 1 warning
      into 5 — it's deliberately queue-based); `@unchecked Sendable` is correct.
- [x] **A6** `10d785b` — KeyboardShortcuts 1.17 → 3.0.1. The recorded reason for
      the pin was WRONG: not Swift 6 language mode, just main-actor API isolation.
- [x] **A7 + 11** `3095278` — dropped unused ViewInspector; added the nightly E2E
      workflow that a code comment had been claiming existed for months.
- [x] **17** `412745a` — parallel tests enabled. Full 48-file migration (244 refs)
      + production stopped touching `.standard`. 38s vs 67s. Two non-UserDefaults
      causes found: PressAndHoldSettings default arg, and
      `NSRunningApplication.current` being INVALID (pid -1) in parallel workers.
      Cleanup lesson: cfprefsd flushes async, so an EXIT-trap rm leaks (4,335
      plists / 17 MB before I caught it) — sweep at STARTUP instead.
- [x] **7** `9df3d88` — analyzer triaged against the compiler: 95 imports removed,
      20 verified false positives annotated, unused_import 116 → 0 and now GATED.
- [x] **13** `cb2d79c`, `e91e14f` — a11y 12/69 → 25/69 files, 52 → 102 annotations.
- [x] **Fork safety** — `upstream` push disabled (fetch preserved), `gh` default
      set to jtn0123/AudioWhisper. Verified: push fails, fetch works.
- [x] **STT picker** `109e642` — added parakeet-tdt_ctc-110m (0.46 GB vs 2.51 GB).

### Still open

- **unused_declaration** — 215 findings, 87 in Tests/Mocks (protocol conformances
  the analyzer can't see). Reported, not gated. Needs ~128 individual judgements.
- **10 / snapshots** — baselines must be regenerated ON the CI runner. Requires a
  push; I cannot complete it. CI job uploads renders as an artifact for adoption.
- **13 / accessibility** — remainder needs an Accessibility Inspector audit, not
  more grep.
- **`xcode-select`** — still points at CommandLineTools (no `actool`), so bare
  `swift build` fails. Needs `sudo xcode-select -s`; not run, it's a system-wide
  change to the user's machine.
- **Nothing pushed.** 26 commits on `grade-fixes-2026-07`; `master` untouched.

---

## SESSION 3 — 2026-08-01 — "fix all the blocked issues"

Every previously-blocked item resolved or reduced to a genuine external limit.

- [x] **xcode-select / actool** — could NOT be fixed the documented way (sudo needs
      an interactive password). Fixed better: `scripts/lib/xcode-env.sh` sets
      DEVELOPER_DIR per-process, sourced by run-tests.sh, build.sh and a new
      lint.sh. `make test` / `make build` now work from a clean shell, for anyone,
      without touching global config. Shell-agnostic (bash/zsh/sh).
      Two bugs en route: probed for xcrun at a path Xcode BETAS don't use; and
      `shopt` is bash-only.
- [x] **10 / snapshots** — the blocker was stale/missing baselines, not CI.
      24 were failing and 3 had never been committed. Re-recorded all 39, verified
      stable over 3 runs. Kept opt-in (SNAPSHOT_TESTS=1) because exact-RGBA
      baselines are inherently machine-specific — documented on SnapshotTestCase.
- [x] **7 / unused_declaration** — 82 more dead declarations removed by the same
      compiler-as-oracle method (215 → 141). Deliberately EXCLUDED protocol
      requirements and framework-positional declarations, where the compiler is
      not an oracle. The 141 residue is structural (87 = Tests/Mocks protocol
      conformances), so the rule stays reported-not-gated, with that reasoning
      recorded in .swiftlint.yml as an expected baseline.
      Removing declarations orphaned 4 imports, which would have broken the
      unused_import gate — pruned, gate genuinely at 0.
- [x] **13 / accessibility** — I was half-wrong to call this Inspector-only.
      MISSING LABELS are mechanically findable; a scan found 9 real gaps including
      the app's primary record button (a bare circle) and the whole recording
      window. Scan now reports ZERO. 12/69 → 30/69 files, 52 → 116 annotations.
      Recurring cause worth remembering: `.help()` is a MOUSE TOOLTIP and is not
      read by VoiceOver — 4 buttons looked labelled and were not.
      Still genuinely Inspector work: grouping, reading order, hint phrasing.
- [x] **`make build` was broken** — found by running it instead of assuming.
      SwiftPM moved the universal-build output from .build/apple/Products/Release
      to .build/out/Products/Release, so build.sh reported "binary not found"
      right after a successful build. Handles both layouts; also asserts the
      binary is actually universal. Verified a real bundle ships uv.lock.

### Genuinely remaining (external limits, not deferred work)
- **CI-generated snapshot baselines** — adopting them needs a push, which is the
  user's call. The `snapshots` job uploads a `snapshot-renders` artifact; the
  procedure is documented on SnapshotTestCase.
- **Accessibility Inspector pass** — needs a human listening to VoiceOver.
- **Nothing pushed.** 32 commits on `grade-fixes-2026-07`; `master` untouched.

### Final state
clean build 0 warnings · 2831 Swift tests green in parallel AND sequential ·
39/39 snapshots green · 19 Python tests green · strict lint clean ·
`make build` produces a valid universal bundle · 0 leaked preference domains.

## Session log — 2026-08-01: "Make a push to fix the Baseline"

The stated goal was to get CI to render authoritative snapshot baselines on
macos-15, download the artifact, and commit it. **That premise was false**, and
chasing it surfaced a much bigger problem.

1. Fixed the CI build failure blocking the `snapshots` job: three
   compiler-version-sensitive spots in Tests/ (ambiguous
   `UnsafeRawBufferPointer` subscript in `differingPixelFraction`, two
   `weak var` -> `weak let`, a redundant `nonisolated(unsafe)`), plus a missing
   `@unchecked Sendable` restatement. Test target now builds warning-free.

2. The `snapshots` job then went green and produced 34 PNGs. **Do not trust
   them.** Measured every one against the committed baseline: all 34 diverged by
   19-100% of pixels. The runner draws AppKit-backed controls as the yellow
   "cannot render" placeholder and drops materials. Committing that artifact —
   which is what this repo's own documentation instructed — would have replaced
   every baseline with a picture of a broken render. Corrected the instruction in
   SnapshotTestCase and relabelled the CI artifact as diagnostic-only.

3. While verifying, found that **13 of the 39 committed baselines were blank**,
   10 of them a SINGLE colour. Root cause: `ImageRenderer` does not draw
   `ScrollView` content — confirmed directly (plain VStack: 216 colours;
   identical content in a ScrollView: 1). Every Dashboard* snapshot was
   comparing an empty rectangle against an empty rectangle and had passed since
   the day it was recorded.

   Fixes:
   * `ScrollableContent` (Sources/Views/Dashboard/) — a ScrollView that flattens
     when `\.flattensScrollViews` is set. Only SnapshotTestCase sets it, so the
     app is unchanged, and no view body is duplicated into a test-only variant.
     Five views adopted it.
   * A flat-render guard in `assertSnapshot`: >99.5% one colour now fails, and
     is checked before the recording branch so a blank baseline cannot be
     written in the first place.
   * Re-recorded: 0 of 33 baselines are blank now (was 13 of 39).

4. Removed 6 dead baselines: 3 for waveform styles deleted in the redesign
   (circular/particles/pulseRings), 2 for XCTSkip'd History tests, 1 for
   DashboardTranscriptsView.

5. Patched 4 dependabot advisories in the shipped uv.lock (urllib3 2.6.3->2.7.0,
   msgpack 1.1.1->1.2.1, idna 3.10->3.18), verified with `uv sync --frozen`.

6. Wired Tests/test_correction_sanitize.py (19 tests) into CI — it was
   referenced by no workflow, script or Makefile target and had never run.

### Deferred (unchanged, still real)
* Deferred(G1): 3 snapshot tests skipped — TranscriptionHistoryView (x2) and
  DashboardTranscriptsView. All three need the async paged fetch to complete
  before capture. Re-enable together once the first load can be awaited.
* CI cannot render this app's UI faithfully, so snapshots stay local-only and
  the job stays report-only. Making it blocking requires a rendering path that
  works without a window server; ImageRenderer is not it.

### Outcome — CI fully green at 83011e44 (2026-08-01)

All five jobs pass: build-and-test, lint, SwiftLint analyze, UI snapshots,
bundle-smoke-test. Getting there took seven more fixes after the snapshot work,
each a real defect rather than a CI quirk:

1. Test target would not build on the runner's compiler (ambiguous
   UnsafeRawBufferPointer subscript + two warnings-as-diagnostics).
2. CI-rendered baselines are unusable (all 34 diverged 19-100%); the repo's own
   docs instructed committing them.
3. 13 of 39 baselines were blank images asserting nothing (ImageRenderer cannot
   draw ScrollView content).
4. Parallel test isolation was opt-in via an env var only run-tests.sh set, so
   CI raced UserDefaults.standard — 24 failures across 7 suites.
5. Global hotkey registration aborted headless processes — 42 SIGABRTs per run
   (CGSConnectionByID assertion). Gated on the test process, NOT on a
   WindowServer probe: both available probes are wrong in one direction or the
   other, and gating the app's core feature on one would kill hotkeys in
   clamshell mode.
6. `make build` broken on release Xcode 26 — `--arch` routes through XCBuild,
   which rejects argmax-oss-swift's duplicate product->target declaration.
   Fixed by building each slice with --triple and lipo-ing. This blocked
   producing a distributable app at all, not just CI.
7. The analyze job ran `swiftlint analyze` three times and was killed by its own
   30-minute timeout (28.5 min on the run that "passed"). Now one pass; 9.5 min.

The unused_import gate then fired for real and caught two imports (one of them
introduced by fix #3's test skip). The gate now prints offending paths — it
previously reported only a count, because GitHub strips file= from annotation
lines.

Final verification at HEAD: 2831 tests / 0 failures / 0 crashes under CI's exact
invocation (`swift test --parallel`, no env var); snapshots 36/3 skipped/0
failures; 19 Python tests OK; SwiftLint 0 violations in 355 files;
`make build` produces a universal binary (x86_64 arm64) with uv.lock bundled.

### Housekeeping
Disk filled during this session (xcodebuild DerivedData). Reclaimed ~10 GB:
AudioWhisper DerivedData plus six ~930 MB scratch dirs. Note the volume was
already ~182 GB of 228 GB full beforehand.

## Session log — 2026-08-01 (cont.): "fix as many things as you can, use judgment"

CI was green at this point; these are the things that were still wrong underneath.

1. **The coverage gate had never enforced anything.** It scraped
   `llvm-cov report | tail -1 | awk '{print $(NF-1)}'`, and on the TOTAL line
   $(NF-1) is MISSED BRANCHES — with no branch data the last fields are "0  -".
   It printed "Could not parse coverage percent; skipping" and exited 0 on every
   run, while the threshold was 60% and real coverage is 53.5%. Now reads
   SwiftPM's codecov JSON, errors on missing data instead of skipping, and
   ratchets at 53. All three paths verified locally.

2. **The suite ran twice per CI run** (parallel, then sequential for coverage).
   Measured: parallel 53.50% vs sequential 53.54% — 30 lines of 92,525. The
   .profraw-race belief was wrong. One run now. CLAUDE.md repeated that belief
   as instruction; corrected.

3. **Deferred(G1) resolved.** The seam it asked for already existed
   (TranscriptionHistoryViewModel takes an injectable DataManagerProtocol), so
   the first page is awaited before rendering. Also needed: pinned record dates,
   and TranscriptionRecordsList adopting ScrollableContent (its rows were inside
   a ScrollView and drew nothing). The third test, DashboardTranscriptsView, was
   REMOVED rather than fixed — which branch it renders depends on whether an
   earlier test called DataManager.shared.initialize(), so it was flaky by
   construction and its content is covered by the two above.
   Snapshots: 35 tests, 0 skipped, 0 blank (was 36 with 3 skipped, 13 blank).

4. **Removed the snapshots CI job.** It could never produce a meaningful
   comparison and published an artifact that looked authoritative while being a
   picture of a broken render.

5. **SwiftLint version drift.** CI used `brew install` (latest, 0.65.0), local
   is 0.63.2 — and unused_declaration reports 144 on 0.63.2 vs 46 on 0.65.0.
   CI now pins SWIFTLINT_VERSION; scripts/lint.sh warns on mismatch, reading the
   pin from ci.yml. unused_declaration is now ratcheted at 46 (valid only for
   that pinned version, stated in both ci.yml and .swiftlint.yml).

6. Removed dead code the above exposed: makePreviewContainer (orphaned when the
   DashboardTranscriptsView test went) and two unused imports.

### Verified at HEAD
CI all four jobs green, with gates reporting real numbers rather than skipping:
`Line coverage: 53.39% >= ratchet 53%`, `unused_import: 0`,
`unused_declaration: 46 (baseline 46)`, swiftlint 0.65.0.
Locally: 2830 tests / 0 failures / 0 crashes under `swift test --parallel`;
snapshots 35 / 0 skipped / 0 failures; SwiftLint 0 violations in 355 files.

### Open / needs the user
* Local SwiftLint is 0.63.2 vs the 0.65.0 pin — `brew upgrade swiftlint` for
  parity. Not done here: system-level change on the user's machine.
* The 4 dependabot alerts are already fixed on this branch but stay open until
  it merges (alerts are computed on the default branch).
* nightly.yml (Parakeet E2E) cannot run or be dispatched until it exists on the
  default branch, so it remains unproven until merge.
* No PR opened — not requested.
