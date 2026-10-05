# Tahoe VM acceptance evidence

Captured 2026-10-04 local time. The guest clock displays 2026-10-05 UTC.
Only AudioWhisper UI and a disposable public-fixture TextEdit document are included.
See [the validation report](../../macos-vm-validation.md) for source/binary provenance,
regressions, scope and remaining boundaries.

| Artifact | What it shows |
|---|---|
| [recording-visible.png](recording-visible.png) | Usable 380×230-point recording HUD inside the visible desktop |
| [smart-paste-result.png](smart-paste-result.png) | Actual app-generated paste into TextEdit |
| [preferences-minimum-size.png](preferences-minimum-size.png) | Preferences and shortcut editor at the minimum workspace size |
| [overlay-over-fullscreen.png](overlay-over-fullscreen.png) | Only the recorder above full-screen TextEdit |
| [paste-in-fullscreen.png](paste-in-fullscreen.png) | Completed native paste in the full-screen destination |
| [desktop-report.json](desktop-report.json) | Ten cancellations and one successful recording/transcription/paste; signature verification and binary hash |
| [fullscreen-hold-report.json](fullscreen-hold-report.json) | Full-screen case passes; physical modifier hold is explicitly incomplete |
| [unattended-report.json](unattended-report.json) | Seven stages, 137 tests, zero skips/failures, with source dirty-state recorded |

No full desktop pass is claimed for the extra runner: it exits 1 when hold input
cannot be verified. Native events are synthetic guest events; audio comes through
BlackHole from the public speech fixture, not a physical host microphone.
