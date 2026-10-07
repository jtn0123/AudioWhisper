# Current AudioWhisper Rebuild audit

Execution update **2026-10-07**: [current report](grade-report.md) is **B+ overall**, with **7 remaining items**. The [original b64f707 audit](grade-report-b64f707.md) remains unchanged and retains its original B / Testing C+ result.

Completed saved batch: **D3, B1, C1, D2, G1**. Imported audio retains its duration and usage, microphone choices refresh without replacing saved inputs, history maintenance is background/cancellable, and real fixtures exercise Parakeet v2/v3 (including Spanish) plus Qwen3.5/3.8 and Whisper. Actual rebuild controls, startup, native menus and window policies have semantic behavioral coverage.

[Official Sonar](batch-2026-10-07/sonar-status.json) passes the unchanged **80%** requirement at **80.5%**, source `5c5a13d`. Full local suite exits 0 with **3,047 discovered cases**; pinned lint is clean. Exact `3312fd3` real-model tests pass together; that follow-up changes tests only. [Batch evidence](batch-2026-10-07/README.md) includes light/dark screenshots, ten recording/cancel cycles, native Stop/transcription/exactly-once Smart Paste, fixed native import duration and preserved host installation.

**Next five:** A1 (retire the old shell), H1 (reconcile instructions), D1 (physical hardware acceptance), E2 (guard public distribution), F1 (audit the branch's frozen runtime lock). E1 and I1 remain after those. Testing is **B** because physical hold/input interruptions and full VoiceOver acceptance remain open.

Parakeet **v2 remains the English recommendation**, with v3 retained. Qwen3.5 **9B 4-bit** remains the new-install writing recommendation and Qwen3.8 **27B mixed 3-bit** remains optional. Existing model/shortcut/cleanup choices and history were preserved; app profiles stay removed.

Native acceptance stays macOS **26/27**. The updated macOS 27.2 host package is the same binary accepted in the macOS 26.6.2 VM, with strict signature valid and all 19 checked preferences/history unchanged. No new host consent was needed; host live recording was not tested. VM proof is not physical hardware or notarized release acceptance. [PR #40](https://github.com/jtn0123/AudioWhisper/pull/40) remains open/unmerged; latest hosted checks are distinct from completed native/local proof.
