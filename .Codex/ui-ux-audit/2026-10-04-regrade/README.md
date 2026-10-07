# AudioWhisper Rebuild — fresh regrade evidence

Captured: 2026-10-04. Branch: rebuild/native-v2.
Audit checkout: 2d3e058; packaged source: f0cc89a40dd380668c432ec186826772f3cd2b03.
Bundle ID: com.audiowhisper.rebuild. Universal, completely ad-hoc signed preview.

All PNGs and accessibility trees were captured from the actual native app using the native-control tool. Screenshots were inspected visually. No generated mockup, emulator simulation or browser rendering is presented as app evidence.

| Artifact | What it establishes |
|----------|---------------------|
| record-ready.png / record-ready.ax.txt | Primary workspace, Ready and generic shortcut guidance |
| library-off.png / library-off.ax.txt | History-off privacy and empty state |
| models-ready.png / models-ready.ax.txt | Allowed microphone and installed Parakeet v3 setup |
| writing.png / writing.ax.txt | Installed optional correction model and repeated profile actions |
| preferences.png / preferences.ax.txt | Current shortcut disabled, Cmd+Shift+Space configured, system-default microphone, history/Smart Paste off |
| verification-start.ax.txt | Explicit Verify model entered disabled Verifying state |
| writing-during-verification.ax.txt | Writing view captured after starting voice verification; concurrent maintenance was not proven to remain active |
| verification-result.png / verification-result.ax.txt | Actual Parakeet model load returned Model ready (offline) |
| recording-start.ax.txt | Live recording started; Models action became Finish recording |
| writing-during-recording.ax.txt | Entire Writing view disabled during recording; suspected busy-recording button mismatch was disproved |
| recording-cancel.ax.txt | Cancel restored Ready; no consent prompt appeared during this start/cancel check |
| code-ci.json | Fresh success/job metadata for packaged source CI run 37178898261 |

The fresh capture check used Cancel, so it produced no transcript or Library save. Preferences stayed unchanged. Earlier same-build actual transcription, repeated capture and cold relaunch results are documented separately in ../../recommended-fixes-validation.md.

After fresh native verification and recording/cancel, strict/deep codesign verification again reported valid on disk and satisfied Designated Requirement. A bundle inventory found zero .pyc or __pycache__ entries. This is signature integrity evidence, not notarization.

Not exercised here: physical global shortcut/hold, Smart Paste, VoiceOver, actual sleep/disconnect, two distinguishable microphones, native save while Library remains mounted, full-screen Spaces matrix, minimum-size/light-mode stress and quantitative startup/frame/long-file memory benchmarks.

manifest.json binds these stored artifacts to their SHA-256 hashes; it is evidence provenance, not a model-integrity claim.
