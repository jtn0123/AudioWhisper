# Current AudioWhisper Rebuild audit

Audited code: `187eacdb55737ba8eb6b57c9bb59f5e0cc23c506`, 2026-10-04.

- [Overall codebase report](grade-report-187eacd.md): **B−**, 18 open improvements across nine categories.
- [UI/UX report](ui-ux-grade-report-187eacd.md): **B**, four concrete improvements and separately listed acceptance gaps.
- [English-first model review](model-review-2026-10-04.md): current options, ranked challengers, publisher evidence and a comparison plan.
- [Measured M5 Pro model comparison](bench/2026-10-05-m5-pro/README.md): nine speech and six cleanup models, local speed/quality/memory charts and semantic acceptance findings.
- [Audit reproduction/CI evidence](audit-187eacd/README.md).
- [Native macOS VM validation](macos-vm-validation.md): completed recorder/paste/full-screen checks and remaining hardware/compatibility limits.

Highest priorities in the current codebase report: **B1, B2, I1, D1, C1**.
English among current Apple Silicon choices: **Parakeet v2**, with **v3 retained
for multilingual use**. The 2026-10-05 local benchmark retains that recommendation:
Granite wins warm speed but lost amount polarity and invented words during
non-speech; Cohere/Qwen ASR did not improve the sampled English tradeoff.
Keep **Qwen3 4B Instruct 2507** as the balanced optional writing default; every
tested writer made meaningful mistakes, including outputs accepted by the guard.

Specify the report when requesting an item, for example **“187eacd codebase B1”**
or **“187eacd UI B1.”** Older canonical reports describe historical snapshots and
retain their original IDs/completion records. This audit did not modify the app,
its installed build, permissions or model selections.
