# Native current-build audit evidence

Audit date2026-10-06 (guest clock UTC screenshots show Oct7).
Code `f30c081ed0bc324bf29c882052a6033d7028783b`.

The exact installed persistent-signed build was copied to the already authorized
macOS26.6.2 Tart QA guest. Four CPUs/8GB, 1024×768-point display at2×.
`identity.json` confirms the guest/host executable hash matches. No host audio,
clipboard or USB device passthrough, no host permission changes.

`desktop/report.json`: all11 checks passed — ten real guest OS recording
shortcut/start/cancel cycles, then public fixture Whisper Base transcription
and exactly one app-generated Smart Paste into a disposable TextEdit document.
Cancel preserved destination focus/clipboard; HUD stayed on screen; strict
signature verification succeeded before and after. Prepared guest permissions
persisted without a new prompt. Cleanup was off; this is not a Qwen dictation
acceptance run or a physical hardware test.

Fresh native screenshots: Record, Models & setup, Writing profiles, Preferences,
populated Library, the live recording HUD and actual pasted document. Model
menu/relaunch captures from the preceding integration are linked separately.
Initial open did not produce a visible main window within30s (`blocked.png`);
reopening showed it. This recovered observation is not established as a product
startup defect. Early coordinate-based Library captures showed the wrong page;
the retained `library.png` was recaptured by the observed native AX button and
the LIBRARY header verified before screenshot review.

**Confirmed current layout bug:** `library-sizing.json` records two runs of
Record(reset870×620) → Library. Each grows the window to870×1,179 at X77,Y30,
well below the768-point screen. `library-overflow-1.png`/`2.png` corroborate it.
The intrinsic/fitting-size mechanism is an inference from hosting/layout code,
not an instrumented internal AppKit trace. `attempted-library-search.png` and
`library-search-sizing.json` are an unsuccessful automation follow-up: text was
not visibly entered. They do not establish empty/no-results layout behavior.

Bounds and text are disposable fixture data only. Full-screen behavior has
separate historical evidence; current physical hold, Sonoma14, multi-display,
hot-plug/sleep, VoiceOver/contrast and large-export timings remain unverified.
No app source changes were made in this grading pass.
