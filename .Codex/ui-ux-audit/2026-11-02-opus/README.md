# Native evidence — 2026-11-02 (Opus 5.5 independent UI/UX review)

Source pin: `b98045bd7e8ffe20a55f735bcc43676ed31bc039` (no `Sources/` diff against the pin at capture time).
App: `/tmp/audiowhisper-ui-review-20261102/AudioWhisper.app`, bundle `com.audiowhisper.rebuild` 2.0.0, locally signed (build log `/tmp/audiowhisper-ui-review-build.log`).
The user's running legacy `com.audiowhisper.app` (PID 1495) was not touched.

## How it was captured

1. Launched with `open -n -F --env …` so LaunchServices owned the process, with
   `CFFIXED_USER_HOME`/`HOME=/tmp/aw-uireview-home`,
   `AUDIOWHISPER_DEFAULTS_SUITE=com.audiowhisper.uireview20261102` and
   `AUDIOWHISPER_APP_SUPPORT_DIR` under the fake home. `lsof` confirmed the SwiftData
   `history.store` opened under `/tmp/aw-uireview-home`, so no real library/transcripts were read.
2. Pages were reached only through the app's navigation-only deep links
   (`open -a <staged path> "audiowhisper://open?page=<id>"`), then captured with
   `screencapture -x -o -l 225` (single window; no screen recording of other apps).
3. The app was quit with SIGTERM. No permission was granted, no model installed, nothing recorded.

## Files

| File | State |
|---|---|
| `native-record-setup-needed-dark.png` | Record, first launch, inactive window, runtime/model missing |
| `native-record-dark-key.png` | Record, same state, key window |
| `native-library-dark.png` | Library with saving off |
| `native-models-dark.png` | Models & setup, runtime not installed |
| `native-writing-dark.png` | Writing cleanup, no correction model |
| `native-preferences-dark.png` | Preferences top (first ~2,000 px of the window) |
| `native-meetings-dark.png` | Meetings, no Whisper model installed |

All are dark appearance (system setting), window 870 × 1084 pt (restored from the existing
`NSWindow Frame RebuildWorkspace` autosave), Retina 2×.

## Failures and limits (raw)

- REA `observe_native_ui` on the raw-exec launch: `process-identity-unavailable: Selected application does not expose a launch time`.
- REA `observe_native_ui` after the LaunchServices launch (pid 25349, window 225), twice:
  `window-mismatch: Selected window is absent or belongs to another process`.
  Consequence: **no accessibility tree, no clicks, no scrolling, no keyboard traversal**.
- Light mode: writing `rebuild.appearance=light` into the per-PID scratch suite from outside the
  process did not propagate; no light native capture. Light evidence is the 2026-10-19 offscreen render only.
- Small window: not attempted natively (would require resizing via AX or rewriting the real frame autosave).
- Recording, processing, cancel, retry, the HUD, installed-model, mode editor, populated library and
  meeting capture/processing states were **not** exercised natively.

## Isolation caveat — report to the user

`CFFIXED_USER_HOME` did **not** isolate `UserDefaults.standard`: the real
`~/Library/Preferences/com.audiowhisper.rebuild.plist` mtime changed to 19:09:44 during this session.
Product settings go through `AppDefaults` and landed in the scratch suite, so model selections,
modes, Smart Paste, history and usage keys were not written by the app logic. Framework-owned keys
in `.standard` (likely `NSStatusItem VisibleCC Item-0` and/or the window frame autosave; possibly
`KeyboardShortcuts_rebuild.recording` initial value) may have been rewritten. The prior values were not
snapshotted, so the exact change cannot be proven. No key was deleted (key list inspected by name only).

## Implementation follow-up

The `feat/session-diagnostics` branch addresses C1 with installed-model admission before capture and processing, C2 with an optional recording-key setup step and clear single-modifier/Fn guidance, I1 with product window/menu names and qualified benchmark captions, and D1 with HUD labels. E1 now has an automatic-stop countdown. B1's page names and permission-dependent copy are corrected; the broader repetition/layout recommendation and A1/B2 remain open. C3's unsupported global Esc promise was removed from the tooltip; no global Esc interception was introduced.

These are source/test changes, not a regrade. Policy regression tests reproduce the old late Space-following behavior and pass after removing it. Current isolated QA launches use their own app identity, standard preferences and Application Support; the new archive was observed in that scratch directory. Further native inspection hit `timeoutReached`; Finder inspection returned `cgWindowNotFound`, and the optional native `launch_app` API was unavailable. Full-screen interaction, physical Fn/Globe and new diagnostics-sheet visual acceptance remain open. The isolated processes were closed; the legacy installed app was not replaced. See `docs/local-diagnostics.md` for semantics and acceptance limits.
