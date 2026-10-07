# Current AudioWhisper Rebuild audit

Audited code: `f30c081ed0bc324bf29c882052a6033d7028783b`, 2026-10-06.

- [Current codebase grade](grade-report-f30c081.md): **B−**, 20 open improvements.
- [Current UI/UX grade](ui-ux-grade-report-f30c081.md): **B**, 7 concrete improvements.
- [Current native VM evidence](ui-ux-audit/2026-10-06-f30c081/README.md): exact
  installed executable identity, 10 start/cancel cycles, fixture transcription,
  exactly-once Smart Paste, all five workspace screens and reproduced Library
  window overflow. Guest synthetic input is distinct from physical acceptance.
- [Current reproduction/CI evidence](audit-f30c081/README.md).
- [Qwen3.5/3.8 adopted integration](bench/2026-10-06-qwen-integration/README.md):
  fixed thinking/quote handling, 128 one-pass edits and packaged offline model
  switching. Successful completion does not guarantee preserved meaning.
- [M5 Pro model comparison](bench/2026-10-05-m5-pro/README.md),
  [Qwen follow-up](bench/2026-10-06-qwen/README.md), and
  [quantized-build comparison](bench/2026-10-06-qwen-quants/README.md) retain
  measured speed/memory/quality evidence and benchmark-specific limits.
- [Earlier native compatibility evidence](macos-vm-validation.md) retains
  full-screen and consent checks with their original build identities.

Parakeet **v2 remains the English recommendation**, with v3 retained as an
option. Qwen3.5 **9B 4-bit is now recommended/default for new installations**;
Qwen3.8 **27B mixed 3-bit is optional**, and three lightweight legacy choices
remain. Existing explicit preferences are preserved. The host user's selected
cleanup model is 3.5, but cleanup remains off and shortcut disabled as before.

Highest code priorities: **B1, B2, B3, B4, C3** — preserve bracketed words,
preserve meaning, protect long dictation, retain the original, fix Library
window overflow. Then **I1, E1, C1** for analyzer execution, dependency patch and
model-install progress/cancellation. See the report's ranked list.

Specify **“f30c081 code B1”** or **“f30c081 UI C1”** for these current items.
[Prior codebase](grade-report-187eacd.md), [prior UI](ui-ux-grade-report-187eacd.md)
and canonical historical reports retain their original IDs/completion records.
This grade changed reports/evidence only, not app behavior or host permissions.
