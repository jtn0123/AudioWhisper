# Native UI polish — October 7, 2026

The local Claude Code CLI actually ran `claude-opus-5-5` with `--effort high` for implementation, refinement and verified dead-code cleanup. [Agent metadata](agent.json) records the exact model and successful runs. Coding used the local worktree; model inference used the existing authenticated Anthropic account. Private prompts, tool transcripts, account metadata and host preference/history backups were not committed.

## Changed behavior

- A compact ink sidebar, paper content surface, restrained headings and aligned native controls across all five pages. Light/dark appearance remains selectable.
- Command-1 through Command-5 select Record, Library, Models & setup, Writing cleanup and Preferences. Native accessibility labels and selected/focus state are explicit.
- A prominent recording action, actionable shortcut link, file import/drop instructions, transcript copy/compare/restore actions and clear setup/retry states.
- Preferences groups recording, microphone, delivery, library, appearance and advanced support. Assigning new shortcut keys also enables that shortcut.
- Numbered microphone/model setup steps; Parakeet v2 is explicitly recommended for English and v3 remains an option. Existing saved selections are retained.
- Writing installs show progress and a real Cancel action. Terminal styling uses affirmative outcomes or authoritative verification results, never a broad match for “ready”/“installed”. Results belong to their selected model.
- Library search, readable bounded previews with matching expansion actions, original text, paged loading, export and native destructive confirmations remain available.
- The recorder retains its compact 380×230 frame with a large white monospaced timer and clear Cancel/Stop actions. Normal windows keep conventional desktop/Space behavior.

## Actual screenshot progression

All images are native screenshots from the retained macOS 26.6.2 guest (25G83), using public fixture audio/transcripts. Workspace bounds were 870×620 points. These are running builds, not mockups.

| Page | Before (b54a852 executable) | Installed UI (45632e5 executable) |
|---|---|---|
| Record | [Before](before/record.png) | [After](installed-candidate/record.png) |
| Models | [Before](before/models.png) | [After](final/models-english.png) |
| Writing | [Before](before/writing.png) | [After](installed-candidate/writing.png) |
| Preferences | [Before](before/preferences.png) | [After](installed-candidate/preferences.png) |
| Library | [Before](before/library.png) | [After](installed-candidate/library.png) |

[First-pass Record](pass1/record.png), [first-pass Preferences](pass1/preferences.png), [dark Record](final/record-dark.png), [dark Writing](final/writing-dark.png), [recorder over full-screen TextEdit](final/fullscreen/recorder-over-fullscreen.png), [install progress](final/writing-progress.png), [busy setup](final/models-busy.png), [search no results](final/library-no-results.png).

## Verification and limits

[Local checks](verification.json): the 2,979-case Swift suite passed after the UI and cleanup changes; strict SwiftLint 0.65.0 passed; Sources-only coverage was 40.52%, above the 40% floor. Python's configured isolated environment passed 121 tests; mypy 1.20.0 found no issues in 11 source files. The initial plain Python invocation lacked tqdm; rerunning with CI's pinned test dependencies passed. Native layout unit cases can skip without the host WindowServer; actual guest screenshots and journeys are separate evidence.

- First UI package: [10 start/cancel cycles and native transcription/paste](pass1/desktop/report.json).
- Reviewed b3dc14f package: [3 start/cancel cycles and exactly-once paste](final/desktop/report.json), [normal Preferences off the full-screen Space while recorder/paste worked](final/fullscreen/report.json), [real shortcut reassignment](final/shortcut.json), [search/export/appearance/install cancellation and honest busy setup](final/ui-checks.json).
- 7b839ae package: [signed executable identity](package/identity.json), [3 start/cancel cycles and exactly-once paste](package/desktop/report.json), [stale model-result fix](package/status-after.json). The leak was first [reproduced on b3dc14f](final/writing-status-before.json) and then removed after the actual model switch.
- [Read-only native AX inspector](../../scripts/vm/inspect-workspace.swift) verified navigation names, selected traits and keyboard focus. System Events' basic names omit some SwiftUI attributed descriptions; direct AX attributes supplied them. Native typing/clicks were used for search; setting AXValue alone does not update SwiftUI's binding.

The VM uses synthetic macOS events and a virtual microphone with a public speech fixture. This is not physical hold-key/device-disconnect/sleep acceptance, a complete VoiceOver/contrast certification, or notarized public-release acceptance. No host microphone/TCC reset or repeated user click request was used. Existing model/shortcut preferences, history, app identity and normal-window placement are retained.

## Analyzer cleanup

The SourceKit crash in a test diagnostic was reproduced in CI and removed without changing its assertion. Once indexing completed, the earlier source report exposed unused imports, old test-only protocols/mocks and dead private helpers. About 1,180 lines of verified unused scaffolding were removed; no test cases/assertions were deleted and production protocol requirements were retained.

The gate also treated SwiftLint's findings exit code as an execution failure, making its declared baseline unusable. [Upstream 0.65.0 implementation](https://github.com/realm/SwiftLint/blob/0.65.0/Source/SwiftLintFramework/LintOrAnalyzeCommand.swift) exits 2 after error-severity findings. The gate now accepts that only with completed indexing, valid report rows, matching finding/severity totals and a consistent exit status, then enforces zero unused imports and the unchanged 30-declaration baseline. Crashes, partial reports, missing logs and unknown error rules still fail. [Fail-before/pass-after fixture](analyzer-gate-regression.json) and real gate regression tests cover this distinction. The older import report flagged AppKit in Writing; it was already removed in the UI refinement. The sole necessary SwiftUI import is retained [without suppressing the rule](required-import.json).

## Installed final package

Production source `45632e5284bfe0a7dcba907493e369d68e029d5f` is installed at `/Applications/AudioWhisper Rebuild.app`, executable SHA-256 `5ecf93e58d60e282afca5461b23b49562af411924be0537449fc8e7fc077e206`. [Host install proof](host-install.json) confirms strict signature validity, the same designated requirement, exactly one running rebuild, 14 protected preference values unchanged, unchanged history and SQLite `quick_check: ok`. Host macOS is 27.2; recording acceptance used macOS 26.6.2 in the VM. No additional host microphone/Accessibility consent was requested.

[Final guest identity](installed-candidate/identity.json), [final recording/paste run](installed-candidate/desktop/report.json) and the five final page captures validate the exact installed executable. Selecting each page also kept keyboard focus on that navigation item and retained the 870×620 window. The latest verification/removal outcome now supersedes an earlier install message; starting a new install clears a prior local result.

Full local analysis on `7b839ae` completed 424 files with 24 unused declarations (within 30) and one residual Foundation import after its unused snapshot helper had been removed. The gate correctly failed for that import. The final follow-up removes it and the newly obsolete `RebuildPhase.title`; the final 34 focused Swift cases and strict lint passed. [Three-file import analysis](analyzer-final-imports-summary.json) indexed all changed files with zero findings. An initial path-filter invocation indexed zero files and was rejected; the configured follow-up supplied valid evidence. This scoped pass is **not** a full final-tree analyzer pass. [Earlier complete analysis](analyzer-7b839ae-summary.json) and the full final CI run retain that distinction.

The [full source CI run](https://github.com/jtn0123/AudioWhisper/actions/runs/37592283658) is still running as this report is finalized. This is a signed local development update; no PR merge, public release or notarization was performed. Historical B− code / B UI grades remain audit baselines; this batch closes UI B1/D1 without inventing a fresh grade.
