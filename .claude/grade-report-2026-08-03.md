# Codebase Grade Report

**Project:** AudioWhisper
**Audited:** 2026-08-03 (re-analyzed after opening PR #27)
**Graded:** `master` @ `47dc121` **and** `grade-fixes-2026-07` @ `a560305` (= [PR #27](https://github.com/jtn0123/AudioWhisper/pull/27))
**Stack:** macOS 14+ menu-bar app — Swift 5.9 / SwiftUI + AppKit, AVFoundation audio, SwiftData persistence, WhisperKit (Argmax OSS SDK) + Parakeet-MLX transcription, embedded uv-managed Python for MLX semantic correction
**Previous report:** `.claude/grade-report-2026-07-31.md` (overall B−, 42 items)

---

## Where we are

[PR #27](https://github.com/jtn0123/AudioWhisper/pull/27) is open — base `master`, head
`grade-fixes-2026-07`, 52 commits, 279 files, +4,691 / −3,099, **MERGEABLE** with no conflicts
(verified by `git merge-tree` before opening; the one commit master had that the branch lacked,
`47dc121`, does not touch the same lines).

That changes the answer to "where are we at" into two answers:

- **`master` today — C+.** Unchanged since 2026-05-19. Two CI gates that cannot fail, 24.5%
  coverage of its own sources, a README describing providers that do not exist.
- **What merges when #27 lands — B.** Verified locally against the branch, not taken on trust.

The remaining gap after the merge is concentrated in one place: **the app's own test coverage is
still 28.4%**, because the view layer is only reachable through snapshot tests that are deliberately
local-only.

---

## Verified: master vs. branch

Same commands, same machine, same toolchain (Xcode-beta, Swift 6.4).

| Measure | `master` | PR #27 branch | |
|---|---|---|---|
| Build | clean, 25.3s | clean, 26.9s | |
| **Build warnings** | **3** (Swift 6 concurrency) | **0** | ✅ |
| Tests (functions) | 2,807 | 2,841 | ✅ |
| Test execution | green, `--no-parallel` required | green, **`--parallel`** | ✅ |
| **Line coverage — `Sources/` only** | **24.47%** | **28.41%** | ▲ 3.9pp |
| Line coverage — all files (SwiftPM metric) | 43.44% | 53.66% | ▲ 10.2pp |
| `print()` CI gate | **cannot fail** | real | ✅ |
| Coverage CI gate | **cannot fail** | real, ratchets at 53 | ✅ |
| `swiftlint analyze` | configured, never run | **dedicated CI job** | ✅ |
| `try!` / `as!` / TODO / FIXME | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 | — |

**On the two coverage numbers.** They are different denominators, not a discrepancy. The CI gate
reads SwiftPM's codecov JSON, which counts every instrumented file including dependencies — that is
the 53.66% the ratchet is set against. The 28.41% is `Sources/**/*.swift` only, and it is the
number that reflects how well *this project's* code is tested. Both went up; only one is small.

---

## Summary — projected state after #27 merges

| ID | Category | master | after #27 | Items |
|----|----------|--------|-----------|-------|
| A | Architecture & Design | B | **B+** | 1 |
| B | Service & Data Layer Quality | B− | **B+** | 1 |
| C | Frontend / SwiftUI Quality | C+ | **B** | 2 |
| D | Testing & Reliability | C | **C+** | 3 |
| E | Security | B− | **B** | 1 |
| F | Dependencies & Tech Currency | C− | **B+** | 1 |
| G | Performance & Scalability | B− | **B+** | 0 |
| H | Documentation & Onboarding | D+ | **B+** | 1 |
| I | Developer Experience & Tooling | C+ | **B+** | 1 |
| **Overall** | | **C+** | **B** | **11** |

**Top 3 remaining after the merge:** D1, D2, A1

Overall lands at B, not B+, for one reason: D. Everything else is solid-to-strong, but 28.4%
coverage of the app's own source — with the view layer untested in CI by design — is a real
limitation, and the ratchet sits on a metric that dependency changes can move.

---

## What #27 actually fixed — verified, not assumed

Each of these was checked against the branch working tree, not inferred from commit messages.

**The two no-op gates.** The `print()` gate now reads from a process substitution
(`done < <(echo "$violations")`) with a `failed` flag instead of `exit 1` inside a pipeline subshell
— and carries a comment explaining precisely that bug. The coverage gate was rewritten to read
`swift test --show-codecov-path` JSON via Python rather than scraping column `$(NF-1)` out of
`llvm-cov report` (which was the missed-*branch* count, not line coverage). Missing coverage data is
now a hard error rather than a silent skip. The threshold is an honest ratchet at 53 against a real
53.66% — 0.66pp of headroom, so it will actually bite.

**Dead code.** `DependencyContainer` (160 lines) and its keep-alive test are gone. Enabling
`swiftlint analyze` — which had been configured but never invoked, since plain `swiftlint lint`
ignores analyzer rules — surfaced and removed **82 dead declarations**.

**The cloud-provider code was *correctly* not fully deleted.** The `"openai"` / `"gemini"` switch
arms remain, now with a justification I checked and agree with:
`TranscriptionRecord.provider` is persisted as a raw `String`, so history written by a pre-2.0 build
still contains those values, and dropping the cases would render old history as "Openai" with a
generic icon. That is the right call, and my original A2 finding was wrong to treat it as purely dead.

**Correctness.** Semantic correction ran `Llama-3.2-1B` while the picker badged `Qwen3-1.7B` as
RECOMMENDED — two defaults silently disagreeing. Both legacy fallbacks are removed, and the choice
is now backed by a documented benchmark (Llama scored 0/6 on homophones). Deleting one history
record no longer re-fetches the entire remaining history.

**Accessibility.** `accessibilityLabel` call sites 20 → 42. Reduce Motion support went from
**zero** references to 20 — confetti, particles, and ripples now honor it.

**Performance.** All three raw `Timer.publish(...).autoconnect()` animation timers converted to
`FrameTimer`, each with a comment naming the C3/G1 item.

**Security.** `uv sync` now passes `--frozen`, so the shipped `uv.lock` is a control rather than
documentation. Python stderr moved from `privacy: .public` to `.private` with only a classified
summary public — closing a path that could put transcript text into the system log. Known-good hash
verification added alongside TOFU. 4 Dependabot advisories patched in `uv.lock`.

**Dependencies.** WhisperKit 0.15 → Argmax OSS SDK 1.0; KeyboardShortcuts 1.17 → 3.x (with the old
Swift-6-language-mode justification retested and found not to apply); `mlx-lm` 0.26 → 0.31;
`parakeet-mlx` 0.3.5 → 0.5; unused ViewInspector dropped. All 3 Swift 6 concurrency warnings cleared.

**Docs.** README rewritten around the two engines that exist. The Privacy section now correctly
states audio never leaves the Mac. The four remaining `mazdak` references are now *correct* — a fork
notice, a warning that upstream's prebuilt binaries are not this code, and attribution. The build
self-heals when `xcode-select` points at Command Line Tools, which is the exact failure I hit on this
machine.

**CI.** `--parallel` tests enabled via per-process settings isolation. Dedicated `SwiftLint analyze`
job. SwiftLint version pinned (CI and local were on different versions). Nightly E2E workflow added.
Stale `grade-report-sweep` branch trigger removed. Snapshot baselines 13 → 35, and 13 that were blank
images asserting nothing were fixed.

---

## A — Architecture & Design — B+ (from B)

Layering was already good; removing `DependencyContainer` and 82 dead declarations clears the debt
that survived two prior audits, and the analyzer job now prevents recurrence. One item remains.

#### A1 — Views still reach global singletons directly
- **Where:** 10 app-owned `.shared` references in `Sources/Views/` — unchanged from master:
  `DataManager.shared` (×2), `UsageMetricsStore.shared`, `SourceUsageStore.shared`,
  `ModelManager.shared`, `CategoryStore.shared`, `AppCategoryManager.shared`,
  `HistoryWindowManager.shared`, `DashboardWindowManager.shared`, `ErrorPresenter.shared`
- **What's wrong:** #27 achieved parallel tests by isolating the *settings* store per process, which
  solves the flakiness but leaves the coupling. Views still cannot be rendered under test with a
  substituted store — which is a contributing reason the view layer sits at the bottom of the
  coverage numbers.
- **Fix:** Inject via `@Environment` or an initializer parameter defaulting to `.shared`, so call
  sites stay unchanged. `DataManager` and `CategoryStore` first — highest test value.
- **Effort:** M
- **Grade lift:** B+ → A− (and it is the structural precondition for D1)

---

## B — Service & Data Layer Quality — B+ (from B−)

Both correctness defects are fixed and the fixes are documented at the call sites. The protocol-first
design, in-memory test double, SwiftData pagination, and allowlisted subprocess environment were
already good.

#### B1 — `fetchAllRecords()` is still an unbounded public API — **scope revised, not done**
- **Where:** `DataManagerProtocol` in [DataManager.swift](Sources/Stores/DataManager.swift)
- **What's wrong:** The unbounded fetch that caused the delete-path bug is still on the protocol
  surface, with a doc comment steering callers to the paged variant — which is an admission it is a
  footgun. The specific bug is fixed; the shape that produced it remains.
- **Scope correction (2026-08-03):** I estimated this at **S**. It is not. The rename touches ~50
  call sites across 8 test files, past this report's own >10-file guardrail. Deliberately left
  undone pending a decision, rather than spending a large mechanical diff on a naming change.
- **What the audit of call sites actually found:** of three production callers,
  `UsageMetricsStore:239` is a legitimate one-time counter rebuild and `DashboardHomeView:235`
  genuinely aggregates over full history. The one that was wrong was
  `DashboardWindowManager` — now fixed (see G1). So the footgun has fired once and has been
  disarmed at the site; the protocol shape is what remains.
- **Fix (if taken):** make the paged fetch the only public surface; move the unbounded one to
  `internal` or behind an explicit `forExport:` label. Mechanical but wide.
- **Effort:** M (revised from S)
- **Grade lift:** B+ → A− (prevents the class of bug, not just the instance)

---

## C — Frontend / SwiftUI Quality — B (from C+)

Reduce Motion went from entirely unsupported to 20 call sites, accessibility labels more than
doubled, and the three stray animation timers are gone. What keeps it at B rather than B+ is that
the accessibility work was targeted at known gaps rather than driven by an audit.

#### C1 — Accessibility coverage is improved but unaudited
- **Where:** 42 `accessibilityLabel` call sites across `Sources/Views/`
- **What's wrong:** The labels added were the ones someone went looking for. Nothing enforces that a
  *new* icon-only control gets one, and no VoiceOver pass has confirmed the app is navigable
  end-to-end.
- **Fix:** Add a SwiftLint custom rule failing on an `Image(systemName:)`-only `Button` with no
  `.accessibilityLabel`. Then do one real VoiceOver pass over the Dashboard and Welcome flows.
- **Effort:** M
- **Grade lift:** B → B+

#### C2 — Snapshot baselines are environment-specific and local-only
- **Where:** `Tests/__Snapshots__/` (35 baselines); [ci.yml:318](.github/workflows/ci.yml:318)
  documents them as a local-only tool
- **What's wrong:** 35 committed baselines that CI never compares. The branch fixed 13 that were
  blank images asserting nothing — which is exactly the failure mode uncompared baselines have. They
  will drift again.
- **Fix:** See D2 — this is the same problem viewed from the UI side.
- **Effort:** M
- **Grade lift:** B → B+

---

## D — Testing & Reliability — C+ (from C)

This is where the remaining work is. The improvements are real: the coverage gate went from
decorative to genuinely enforcing, tests run in parallel, 34 more test functions, blank baselines
fixed, and a nightly E2E workflow now exists. But the headline number barely moved.

#### D1 — The app's own code is 28.4% covered
- **Where:** measured over `Sources/**/*.swift`: 34,389 lines, 24,618 missed → **28.41%** line,
  36.69% region (master: 24.47% / 34.47%)
- **What's wrong:** Nearly three quarters of the project's own source is unexecuted by the test
  suite. The bulk is SwiftUI view bodies, which are only reachable via snapshot tests that do not run
  in CI (D2) and are hard to render under test because views reach singletons directly (A1). 2,841
  test functions producing 28% coverage means the tests are concentrated in the layers that were
  already easy to test.
- **Fix:** Land A1 (injectable stores) → then D2 (snapshots in CI) → then ratchet on the
  `Sources`-only figure rather than the all-files one.
- **Effort:** L
- **Grade lift:** C+ → B (the single largest remaining gap in the project)

#### D2 — Snapshot tests still do not run in CI
- **Where:** [SnapshotTestCase.swift:45-51](Tests/SnapshotTestCase.swift:45) — opt-in via
  `SNAPSHOT_TESTS=1`; no CI job sets it
- **What's wrong:** A documented, deliberate decision — they are environment-sensitive and were
  causing false failures. But the consequence is 35 baselines that rot silently, and the least-tested
  layer of the app having its test mechanism switched off. The branch's own history shows the cost:
  13 baselines had degraded to blank images that asserted nothing.
- **Fix:** Run them on one pinned macOS runner image in a non-blocking job first, so drift is visible
  without gating merges. Promote to blocking once it is stable for a few weeks.
- **Effort:** M
- **Grade lift:** C+ → B

#### ~~D3~~ ✓ done 2026-08-03 — Python coverage is never reported to SonarCloud, so `Sources/ml/*.py` is structurally 0%

**Fixed in `401f767`, pushed to PR #27.** Added an "Export Python coverage for SonarCloud" step
running the same test invocation `ci.yml` already uses under `coverage.py`, and passed the report via
`-Dsonar.python.coverage.reportPaths`. Verified locally against the branch: 19 tests pass,
`correction.py` measures **30.9%** (was reported as 0.0%), `loader.py` 21.6%. A missing or empty
report now fails the step rather than letting the scan silently score `Sources/ml` as 0% — the same
silent-zero failure mode as the coverage gate fixed in `8561bee`.

- **Where:** [sonarcloud.yml:48-72](.github/workflows/sonarcloud.yml:48) exports **Swift only**
  (`llvm-cov export -format=lcov` → `scripts/lcov-to-sonar.py` → `sonar.coverageReportPaths`), while
  [sonar-project.properties](sonar-project.properties) sets `sonar.sources=Sources` and
  `sonar.python.version=3.11`
- **What's wrong:** Sonar analyzes the bundled Python under `Sources/ml/` but receives no Python
  coverage report, so those files can only ever measure 0%. `Sources/ml/correction.py` is the single
  largest contributor to the PR #27 quality-gate failure — **29 uncovered new lines at 0.0%** — and
  no amount of Python testing will change that number until a report is uploaded. #27 added
  `test_correction_sanitize.py` and made the Python tests actually run; Sonar still sees nothing.
- **Fix:** Run the Python tests under `coverage run`, emit `coverage.xml`, and add
  `-Dsonar.python.coverage.reportPaths=coverage.xml` alongside the existing `coverageReportPaths`.
- **Effort:** S
- **Grade lift:** C+ → B− (removes ~10% of the new-code coverage deficit and stops penalizing
  Python tests that do exist)

#### D4 — Three coverage standards that disagree
- **Where:** SonarCloud's default gate (≥80% on new code), [ci.yml:140](.github/workflows/ci.yml:140)
  (`THRESHOLD=53`, all-files), and the actual `Sources`-only figure (28.41%)
- **What's wrong:** Three numbers, three denominators, three thresholds, none reconciled. The Sonar
  gate will fail on essentially every substantial PR while the project's own gate passes — which
  trains everyone to ignore the red X, and a permanently-red check is worse than no check.
- **Fix:** Pick one denominator (`Sources`-only) and set both gates against it — Sonar's new-code
  threshold to something achievable for this codebase's view-heavy diffs, and the CI ratchet to the
  measured baseline. Then raise both together.
- **Effort:** S
- **Grade lift:** C+ → B−

#### ~~D5~~ ✓ done 2026-08-03 — The ratchet sits on a dependency-inflatable metric

**Fixed in `2d88314` on `grade-fixes-round2`.** New `scripts/coverage-gate.py` sums only files under
`<repo-root>/Sources`, anchored on the repo root (a substring match on `/Sources/` would readmit
`.build/checkouts/KeyboardShortcuts/Sources/...`). Threshold reset to 28, the measured baseline.
Verified end-to-end against a real instrumented run: reports **28.38%**, passes at 28, and fails
correctly on a bad repo root, a missing JSON, and a raised threshold.

<details><summary>original finding</summary>
- **Where:** [ci.yml:140](.github/workflows/ci.yml:140) — `THRESHOLD=53` against SwiftPM's
  all-files codecov total (53.66%)
- **What's wrong:** The all-files number includes dependency code. A dependency bump that adds
  well-covered code raises the number with no new tests; one that adds uncovered code can trip the
  gate with no code change of yours. With only 0.66pp of headroom, that is a live risk — the next
  dependency bump could redden CI for reasons unrelated to test quality.
- **Fix:** Filter the codecov JSON to paths under `Sources/` before computing the percentage, and
  reset the ratchet to the resulting number (~28%). Same mechanism, honest denominator.
- **Effort:** S
- **Grade lift:** C+ → B− (makes the gate mean what it says)

</details>

---

## E — Security — B (from B−)

The two open holes are closed: `uv sync --frozen` makes the shipped lockfile authoritative, and
Python stderr no longer goes to the system log in the clear. Known-good hash verification now
supplements TOFU. Keychain use, the allowlisted subprocess environment, `uv` binary SHA256
verification, the documented no-sandbox tradeoff in [ADR 0001](docs/adr/0001-no-sandbox.md), and
CodeQL on two languages were already sound.

#### ~~E1~~ ✓ done 2026-08-03 — First-fetch of user-supplied models is still trust-on-first-use

**Documented in `0bafeb0` (`docs/adr/0006-model-integrity.md`).** Correcting my own finding: this was
overstated. `DiskMutationSerializer.verify(at:modelIdentifier:)` already pins known-good hashes for
app-shipped models with a **hard fail** on mismatch — including on first download, with no TOFU
escape hatch — and falls back to TOFU only for user-added repos, where no prior hash can exist. That
is the design the item asked for. What was genuinely missing was the write-up, which now also records
that a stale pin fails closed and will look like a download bug if the reason is forgotten.

<details><summary>original finding</summary>
- **Where:** [MLXModelManager+Downloads.swift:304](Sources/Services/MLXModelManager+Downloads.swift:304)
  — "Best-effort integrity verification. TOFU on first hit"
- **What's wrong:** Correct and unavoidable for arbitrary user-supplied repos — you cannot pin a hash
  for a model you have never seen. Worth stating explicitly rather than leaving implicit: the trust
  boundary is Hugging Face over TLS on first download.
- **Fix:** No code change needed. Document the trust model in `docs/adr/` so the next audit does not
  re-flag it, and surface in the UI that a user-supplied model is not hash-pinned.
- **Effort:** S
- **Grade lift:** B → B+ (documentation of an accepted risk, not a vulnerability)

</details>

---

## F — Dependencies & Tech Currency — B+ (from C−)

The largest single-category jump. Every dependency that was pinned below a shipped major is now
current: WhisperKit 0.15 → Argmax OSS SDK 1.0, KeyboardShortcuts 1.17 → 3.x, `mlx-lm` → 0.31,
`parakeet-mlx` → 0.5. The KeyboardShortcuts pin is the nicest fix in the set — the old comment
claimed 2.x required Swift 6 language mode; #27 retested that on 3.0.1, found it false (3.x only
main-actor-isolates its own API), and documented the retest. Both lockfiles are committed, all
3 Swift 6 warnings are cleared, and unused ViewInspector is gone.

#### F1 — Three Dependabot PRs remain open
- **Where:** [#25](https://github.com/jtn0123/AudioWhisper/pull/25) msgpack,
  [#23](https://github.com/jtn0123/AudioWhisper/pull/23) idna,
  [#15](https://github.com/jtn0123/AudioWhisper/pull/15) urllib3
- **What's wrong:** #25 and #23 are mergeable with all real checks green — blocked only by a
  SonarCloud run that predates `47dc121`, the commit that skips Sonar on Dependabot PRs. A re-run
  clears both. #15 has a genuine `Analyze (swift)` CodeQL failure. Note #27 already patches 4
  advisories in `uv.lock`, so check for overlap before merging.
- **Fix:** Merge #27 first, then rebase and re-run #25/#23. Investigate #15's CodeQL failure separately.
- **Effort:** S
- **Grade lift:** B+ → A−

---

## G — Performance & Scalability — B+ (from B−)

Both items closed. The three always-on timers are on `FrameTimer` with lifecycle handling, and the
delete path no longer loads the full history. Performance tests still pass (1,000 records fetched in
1.7ms, searched in 8.1ms).

#### ~~G1~~ ✓ done 2026-08-03 — Status menu loaded the entire history to display three records
- **Where:** `DashboardWindowManager.refreshRecentRecordsCache()`, called from
  `AppDelegate+Lifecycle.swift:55` (launch) and `AppDelegate+Menu.swift:238` (every menu open)
- **What was wrong:** Found while scoping B1, not in the original audit. The method called
  `fetchAllRecordsQuietly()`, sorted the entire result in memory, then took `.prefix(10)` — while the
  only consumer, `AppDelegate+Menu.swift:89`, asks for **three**. Cost grew with history size for a
  permanently-bounded display.
- **Fix applied (`35c16db`):** use `fetchRecords(limit:offset:search:)`, which sorts by date
  descending via a `SortDescriptor` and applies `fetchLimit`, so the store returns exactly the wanted
  rows and the in-memory sort disappears. `?? []` preserves the old `...Quietly` failure behaviour
  exactly, making it a pure performance change.
- **Verified:** build clean (0 warnings), 2839/2839 tests, `swiftlint --strict` clean.
- **Note:** not covered by a test, because `refreshRecentRecordsCache` reaches `DataManager.shared`
  directly instead of taking an injected manager — that is A1, and it is why this went unnoticed.

---

## H — Documentation & Onboarding — B+ (from D+)

The second-largest jump. The README now describes the application that actually ships: two offline
engines, no API keys, and a Privacy section correctly stating audio never leaves the Mac. The fork
relationship is handled better than I would have specified — rather than scrubbing every `mazdak`
reference, it keeps four *deliberate* ones: a fork notice, a warning that upstream's prebuilt
binaries and Homebrew cask are a different build with cloud providers intact, and attribution. That
is more useful to a user than a clean scrub would have been. `CONTRIBUTING.md` was already strong;
CLAUDE.md's coverage advice is corrected and the snapshot workflow documented.

#### ~~H1~~ ✓ done 2026-08-03 — No ADR for the post-2.0 local-only architecture

**Written in `0bafeb0` (`docs/adr/0005-local-only-transcription.md`).** Records why cloud was removed
and — most usefully — why the `"openai"`/`"gemini"` presentation cases must *stay*, so a third audit
does not flag them as dead again. The ADR index was also stale (listed 0001–0003 while 0004 existed);
it now carries 0004–0006.

<details><summary>original finding</summary>
- **Where:** `docs/adr/` — four ADRs, none covering the cloud-provider removal
- **What's wrong:** Removing both cloud providers is the largest architectural decision in this
  fork's history and the reason for the `TranscriptionRecord.provider` legacy-string handling, the
  README fork notice, and the Keychain code retained for keys nothing uses. It is documented in the
  README as user-facing fact but nowhere as an engineering decision with rationale.
- **Fix:** Add `docs/adr/0005-local-only.md`: why cloud was removed, what remains for history
  compatibility, and when the store migration that would let the legacy cases go should happen.
- **Effort:** S
- **Grade lift:** B+ → A−

</details>

---

## I — Developer Experience & Tooling — B+ (from C+)

Both decorative gates are now real, and the fixes are better than the minimum: the coverage gate
treats missing data as an error rather than a silent skip, with a comment explaining why a gate that
cannot find its input is broken rather than passing. `swiftlint analyze` has a dedicated job, run
once instead of three times. SwiftLint is version-pinned via a single `env` var so CI and local
agree. Stale branch triggers removed, nightly E2E added, and `scripts/lib/xcode-env.sh` makes the
build self-heal on a Command-Line-Tools-only machine.

#### I1 — CodeRabbit cannot review changes this large
- **Where:** PR #27 check output — *"Review skipped: 238 files exceed the limit of 100"*
- **What's wrong:** The automated reviewer silently no-ops on large PRs and reports `pass`, so a
  green checks column overstates what was actually reviewed. This will recur on any large change.
- **Fix:** Nothing to fix in-tree — but treat CodeRabbit `pass` on a large PR as "not run", and
  prefer smaller PRs going forward so the tooling stays useful.
- **Effort:** S (process, not code)
- **Grade lift:** B+ → A−

---

## Status as of 2026-08-03 (end of session)

**The PR queue is empty.** `master` is at `8dee2a4`, all checks green.

The coverage ratchet now runs on the **CI-measured** baseline: **27.89% ≥ 27** over `Sources/` only.
It caught its own misconfiguration on first run — the threshold had been seeded from a local
measurement (28.35%), and CI reads ~0.5pp lower because environment-gated tests skip differently on
a clean runner. Fixed in `61070b5`; re-measure in CI, never locally, before moving it.

| PR | Outcome |
|---|---|
| #27 | **Merged** — 53 commits. CodeQL `Analyze (swift)` confirmed success (23m3s). |
| #25 / #23 / #15 | **Closed as obsolete** — `9067da8` in #27 already bumped all three in `uv.lock`. #23 would have *downgraded* `idna` 3.18 → 3.15. |
| #7 | **Closed** — goal achieved on master in 5 workflow locations; branch is a Jan debugging spiral, 4 months stale, conflicting across 147 files. |
| #28 | **Merged** (`8dee2a4`) — audit round 2, 5 commits. All checks green, including SonarCloud's quality gate, which passes on a 7-file PR where the 279-file #27 could not. |

**Zero open Dependabot alerts** (`gh api .../dependabot/alerts` → `[]`). The 4 vulnerabilities
(3 high, 1 moderate) that GitHub warned about on every push are cleared.

**Corrections made to this report during the session**, all recorded inline: E1 was overstated
(hash pinning already existed), B1 was mis-sized (M, not S — ~50 call sites), A2's retained
cloud-provider cases are correct rather than dead, and my earlier advice to "re-run and merge
#25/#23" was wrong — they needed closing, not merging.

## Next actions, in order

1. **Land [#27](https://github.com/jtn0123/AudioWhisper/pull/27)** once CI settles. Its SonarCloud
   quality gate fails on exactly one condition — `new_coverage` 51.0% vs a required ≥80% — while
   reliability, security, and maintainability all rate **A**, duplication is **0.0%**, and security
   hotspots are **100% reviewed**. Branch protection lists **no required checks**, so it does not
   block the merge. Root cause is D1/D3, not a defect in the PR: 189 of the 292 uncovered new lines
   are in `Sources/Views`, and 29 more are Python that Sonar can never see coverage for.
   Note CodeRabbit skipped review at 238 files — the human read is the only review this PR gets.
2. **Re-run checks on #25 and #23**, then merge. Check for `uv.lock` overlap with #27 first.
3. **Close or rebuild [#7](https://github.com/jtn0123/AudioWhisper/pull/7)** — 4 months stale,
   conflicting across 147 files. #27 supersedes its VersionInfo/build work.
4. **Delete the merged branches** — `bug-hunt-2-fixes`, `coral-palette-fix`, and the seven
   `worktree-agent-*` (0 unmerged patches each).
5. **Then D1 → A1 → D2**, which are one chain: injectable stores make views testable, testable views
   make snapshots viable in CI, and both together are the only way the 28.4% moves.

## Appendix — local branch inventory

| Branch | Unmerged | Last | Status |
|---|---|---|---|
| `grade-fixes-2026-07` | 52 | 2026-08-02 | **PR #27 open, MERGEABLE** |
| `grade-report-sweep` | 27 | 2026-05-15 | Stale, 24 behind. CodeQL path-injection fixes + ~311 tests — check overlap with #27 before reviving |
| `grade-fixes-top8` | 6 | 2026-05-16 | Stale, 19 behind. Model-hash pinning now largely superseded by #27 |
| `design-handoff-prototype` | 5 | 2026-05-15 | Content already in master via rebase — deletable |
| `design-fidelity-followups` | 3 | 2026-05-15 | Stale cosmetics, 20 behind |
| `a2-history-viewmodel` | 2 | 2026-05-17 | Stale, 18 behind |
| `bug-hunt-2-fixes`, `coral-palette-fix`, `worktree-agent-*` (×7) | 0 | 2026-05 | Fully merged — safe to delete |

"Unmerged" is by patch-id, which overstates across rebases — diff against master before reviving any.

---

*Next: `/grade-codebase show` for this report, `/grade-codebase <ID>` to execute items,
`/grade-codebase D` to re-drill the weakest category.*
