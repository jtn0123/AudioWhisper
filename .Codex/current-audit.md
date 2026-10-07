# Current AudioWhisper Rebuild audit

Fresh regrade: **2026-10-07**, source `b64f7071688a705d380e6ace5fb2382c92205f5c` (unchanged app sources from `224473e` / `a9a0fed`), after opening [PR #40](https://github.com/jtn0123/AudioWhisper/pull/40) against this fork's `master`.

- [Current codebase report](grade-report-b64f707.md): **B overall**, 12 ranked items with evidence and short plain-language explanations.
- [Fresh native/verification evidence](regrade-2026-10-07/README.md): full local suite, exact-head CI/coverage, ten light/dark page captures, ten recording/cancellation cycles, fixture Stop/transcription and exactly-once Smart Paste.
- Frontend quality within this codebase audit is **B+**. This is not a separate nine-dimension UI/UX audit; the historical [f30c081 UI report](ui-ux-grade-report-f30c081.md) retains its scope/IDs.
- [Complete visual/contrast evidence](opus-visuals-2026-10-07/README.md) and [fullscreen/shortcut/install/export evidence](ui-polish-2026-10-07/README.md) retain source provenance and acceptance limits.
- [Prior canonical report](baseline-pre-pr-2026-10-07/grade-report.md) and [previous audit pointer](baseline-pre-pr-2026-10-07/current-audit.md) are preserved. Old IDs do not refer to the new report.

Top five: **D3** reliable rebuilt-UI coverage, **B1** imported duration, **C1** microphone picker refresh, **D2** real offered-model fixtures, **G1** background history maintenance. Testing is **C+**: PR #40 fails the established new-code coverage gate (45.7% against 80%). The fresh headless semantic probe failed to expose a usable button and is preserved as an experiment. The provisional [224473e report](grade-report-224473e.md) is retained; its earlier B+ is superseded.

Fresh import reproduced B1: a 2.67075-second public fixture saved correct text with a NULL duration. Missing-tool checks reproduced I1. Other findings are labeled source risks, hardening work or acceptance gaps; they are not all asserted runtime bugs. This regrade did not execute its newly listed fixes.

Parakeet **v2 remains the English recommendation**, with v3 retained. Qwen3.5 **9B 4-bit** remains the new-install writing recommendation and Qwen3.8 **27B mixed 3-bit** is optional. Existing model, shortcut and cleanup choices were not changed by this audit. App profiles stay removed.

Native acceptance remains macOS **26/27**. Hosted CI OS versions are build/test infrastructure. The host and QA guest package share SHA-256 `58e531e1bc1e19dcadac4aa34af0330363897bcb34691dc85444b4f5f3e6b218`; current tests needed no new host permissions. Physical hold keys, hardware interruptions and full VoiceOver acceptance remain open. Developer signing is not notarized public-release proof. Host live capture remains unverified. Live PR checks are on PR #40; it remains unmerged with the coverage gate unresolved.

Use **2026-10-07 code D3**, **B1** or another new ID for this report's work.
