# Current AudioWhisper Rebuild audit

Audited code: `187eacdb55737ba8eb6b57c9bb59f5e0cc23c506`, 2026-10-04.

- [Overall codebase report](grade-report-187eacd.md): **B−**, 18 open improvements across nine categories.
- [UI/UX report](ui-ux-grade-report-187eacd.md): **B**, four concrete improvements and separately listed acceptance gaps.
- [English-first model review](model-review-2026-10-04.md): current options, ranked challengers, publisher evidence and a comparison plan.
- [Measured M5 Pro model comparison](bench/2026-10-05-m5-pro/README.md): nine speech and six cleanup models, local speed/quality/memory charts and semantic acceptance findings.
- [Qwen3.5 / Qwen3.8 follow-up](bench/2026-10-06-qwen/README.md): 64 English cleanup stress cases on four models; 27B improved results at a memory/latency cost, with confirmed quote and thinking-template integration defects.
- [Qwen quantized-build comparison](bench/2026-10-06-qwen-quants/README.md): 9B 8-bit and 27B mixed 3-bit/6-bit builds, with same-session 4-bit controls and separate prompt conditions.
- [Audit reproduction/CI evidence](audit-187eacd/README.md).
- [Native macOS VM validation](macos-vm-validation.md): completed recorder/paste/full-screen checks and remaining hardware/compatibility limits.

Highest priorities in the current codebase report: **B1, B2, I1, D1, C1**.
English among current Apple Silicon choices: **Parakeet v2**, with **v3 retained
for multilingual use**. The 2026-10-05 local benchmark retains that recommendation:
Granite wins warm speed but lost amount polarity and invented words during
non-speech; Cohere/Qwen ASR did not improve the sampled English tradeoff.
Keep **Qwen3 4B Instruct 2507** as the balanced optional writing default; every
tested writer made meaningful mistakes, including outputs accepted by the guard.
The Qwen follow-up retains that default pending output-handling fixes and broader
validation. Qwen3.5 9B is a balanced challenger; Qwen3.8 27B is a possible quality
option. Neither was adopted or added to the installed app by the benchmark.
The quantized-build follow-up makes mixed 3-bit 27B a lower-memory candidate:
it matched direct 4-bit acceptance using 18% less MLX allocation. The 8-bit 9B
gain depended on the prompt; 6-bit 27B did not justify its cost in this sample.
All six builds passed a basic installed-runtime load/correction smoke check.
This does not close the thinking-template, sanitizer, or app acceptance gaps.

Specify the report when requesting an item, for example **“187eacd codebase B1”**
or **“187eacd UI B1.”** Older canonical reports describe historical snapshots and
retain their original IDs/completion records. This audit did not modify the app,
its installed build, permissions or model selections.
