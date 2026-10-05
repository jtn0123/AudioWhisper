# Audit evidence for code 187eacd

Collected 2026-10-04 local time. [evidence.json](evidence.json) records audited
source SHA-256 values, CI identity/results/coverage and local reproductions.

## Transcript integrity

[text-integrity-repro.swift](text-integrity-repro.swift) copies the production
cleaner, long-text guard and edit-distance helper into a Foundation-only program.
It exercises the code without audio, model downloads or user data. From the repo:

```sh
swiftc -O .Codex/audit-187eacd/text-integrity-repro.swift -o /tmp/audiowhisper-text-integrity-repro
/tmp/audiowhisper-text-integrity-repro
```

Observed output:

```text
cleaner input: Send the report (including taxes) to Jordan [the editor].
cleaner output: Send the report to Jordan .
long unrelated rewrite accepted: true
short unrelated rewrite rejected: true
```

The timing prints in this small program are incidental; they are not app-level
latency benchmarks. A passing reproduction means the defects are present,
not that the behavior is correct. There is no actual ASR/LLM hallucination claim.

## CI analyzer failure handling

The local installed SwiftLint is **0.65.1**; CI pins **0.65.0**. The source recipe
suppresses execution errors independently of rule-version changes. A deliberately
missing compiler log produced tool exit 1, suppressed recipe exit 0, an empty
report and zero counts in both gates. The reproducer below runs from the repo
and only writes disposable files under `/tmp`:

```sh
bash .Codex/audit-187eacd/analyzer-error-repro.sh
```

This proves a gate weakness, not that it happened in the green remote run.
The [audited commit's CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37267004905)
passed its four active jobs. SonarCloud was skipped. Source-only Swift coverage
was 38.39% (14,780/38,498 lines, 192 files), with an enforced 27% floor.

## Native and research provenance

Native recorder/shortcut/paste/full-screen conclusions use the saved
[VM run](../macos-vm-validation.md). Historical Models/Writing screenshots have
their separate [source/binary provenance](../ui-ux-audit/2026-10-04-regrade/README.md).
New speech models were researched through linked primary publisher/runtime
documentation in [the model review](../model-review-2026-10-04.md); none was
downloaded, installed or benchmarked in this pass.
