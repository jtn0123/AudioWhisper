# SwiftLint analysis performance

The analyzer uses SourceKit's type-checked information for both `unused_import`
and `unused_declaration`. The declaration rule gathers references across every
analyzed file, including tests. Splitting files into independent shards changes
that reference graph and can produce false findings. SwiftLint 0.65.0 deliberately
processes modern Swift analysis serially because concurrent SourceKit requests
have an upstream performance problem.

The existing hosted run spent 3m23s building its compiler log; analysis was still
running more than twenty minutes afterward. Building dependencies is a smaller
part of this job than the SourceKit pass.

## Reusing a complete result

CI caches a **successful complete report**, its diagnostics and a manifest with
checksums. The key includes:

- Every tracked file except root Markdown and the `docs/` and `.Codex/` evidence
  directories. This conservatively includes build recipes, configuration,
  dependency locks and resources.
- Generated and untracked files under `Sources/` and `Tests/`, including the
  actual generated `VersionInfo.swift`.
- SwiftLint version and binary checksum, Xcode/Swift/SDK and OS builds,
  architecture, workspace path and compiler-related environment settings.

The analyzer-only build uses stable version metadata, so documentation-only
commits do not change its generated Swift file. Other builds retain real commit
and date metadata. Generators must run before fingerprinting. After a cold build,
CI fingerprints again before publishing a report, accounting for inputs changed
by build or dependency resolution.

Only an exact key is restored. Cache hits recheck report integrity, successful
indexing, exit status, finding counts, zero unused imports and the unchanged
unused-declaration limit of 30. Invalid or incomplete cache data falls back to a
full build and analysis. Cache-service failures also fall back; the build and
analysis gates themselves remain required. Failed analysis never publishes a
report bundle.

This saves the build and analysis on identical-input reruns and documentation-only
commits. **A changed Swift/test graph still requires the full pass.** A cold run
does not become faster solely because this result cache exists.

## Progress and profiling

The wrapper streams per-file diagnostics immediately rather than buffering all
output until exit, and prints elapsed analysis time. Cold CI runs retain
`benchmark_files.txt` and `benchmark_rules.txt` alongside the report. These
profiles identify worthwhile follow-up changes to the expensive SourceKit work.

## Validation

Thirteen Python tests cover the original gate, complete-report reuse,
invalidation after source/test/lock/config/toolchain changes, generated and
removed files, corrupt/partial cache fallback, stricter gate validation and live
progress delivery. Actionlint has no new findings compared with `master`; its
five existing ShellCheck diagnostics remain.

A separate two-file Swift package was built with Xcode and analyzed with the real
pinned SwiftLint 0.65.0. Full analysis took 0.555s; cached report validation took
0.062s and retained the identical two declaration findings. Computing its full
toolchain/input fingerprint took 0.970s. A Swift edit invalidated the cache and
produced fresh, changed findings. These small-fixture measurements verify the
cache path, **not a full-repository cold-analysis speedup**. Hosted cache timing
remains to be measured.

Upstream references:

- [Serial analysis in SwiftLint 0.65.0](https://github.com/realm/SwiftLint/blob/0.65.0/Source/SwiftLintFramework/LintableFilesVisitor.swift)
- [Whole-analysis declaration references](https://github.com/realm/SwiftLint/blob/0.65.0/Source/SwiftLintBuiltInRules/Rules/Lint/UnusedDeclarationRule.swift)
- [Analyzer build-log requirements](https://realm.github.io/SwiftLint/#analyze)
