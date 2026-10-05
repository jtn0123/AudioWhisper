# macOS VM validation and recorder polish

Observed on 2026-10-04 local time (the guest clock uses UTC). This is a targeted
native acceptance and polish pass, not a new full UI/UX grade or release approval.
The previously reported B grade remains historical.

## Confirmed defects and fixes

| Finding | Before | Result after the fix | Plain meaning |
|---|---|---|---|
| Recorder collapsed | Native HUD was 76×205 points; controls were squeezed/clipped | SwiftUI root has a 380×230-point size; host fitting-size regression and native bounds pass | Cancel and Finish stay usable |
| Recorder partly off-screen | Origin (0,0) was retained because only its centre was checked, leaving controls behind the Dock | Placement requires the whole frame to fit in the visible display; otherwise it recentres | The buttons stay above the Dock and inside the screen |
| Recorder absent over full-screen destination | Recording started, but the regular NSWindow stayed on a desktop Space | Recorder is a nonactivating NSPanel eligible for other applications' full-screen Spaces | The small recording window appears over your full-screen app; Preferences stays on the desktop |

Adding the collection flag alone did not resolve the third native reproduction.
The panel type and nonactivation behavior were required. Cancel now leaves
TextEdit frontmost. Normal workspace window behavior is unchanged.

Product copy now says “PRIVATE DICTATION,” “Enable recording shortcut” and
“Open AudioWhisper at login.” Library guidance describes optional local saving
instead of claiming that the library is always empty.

## Native guest evidence

The guest is `audiowhisper-qa-tahoe`, macOS **26.6.2 (25G83)**, four CPUs, 8 GB RAM,
one 1024×768-point display at 2× scale. The base image resolved to
`sha256:87f3aa5ce21b5c876268f233bdfecf38b4c2a8116fe9bbb718e714cbae187377`.
Tart 2.40.1 was downloaded from its official release and checksum verified.

The tested app was a signed arm64 debug preview built from `77d85cd` plus this
pass's implementation changes. Binary SHA-256:
`3c2ce960bb40caddf3305401dabc332590e84081100b62f5bf0b58eea5d85a7f`.
The bundle identifier stayed `com.audiowhisper.rebuild`, and the existing local
development leaf certificate was reused across replacements. No private key
was copied to the guest. Strict/deep codesign verification passed before and
after actual inference.

| Native check | Result |
|---|---|
| Actual guest OS dispatch of `⌥⇧⌘R` | Pass |
| Ten start/cancel cycles | Pass: 380×230 HUD entirely visible, clipboard unchanged, TextEdit still frontmost |
| Start/stop, actual Whisper base transcription | Pass: public fixture sentence transcribed correctly |
| App-generated Smart Paste into TextEdit | Pass: exactly one transcript appended to the prepared document |
| Preferences open before TextEdit enters full screen | Pass: Preferences does not overlay that Space |
| Recorder and native Smart Paste over full-screen TextEdit | Pass |
| Consent across relaunch and signed code replacements | One guest microphone grant retained; no repeated microphone dialogs during final cycles; authenticated guest Accessibility worked across replacements |
| Physical left/right modifier hold/release | Incomplete: guest remote events omit device-specific modifier bits |

Screenshots and machine-readable results are retained in
[the evidence directory](ui-ux-audit/2026-10-04-vm/README.md).
The normal desktop report passes. The extra report deliberately has aggregate
status `incomplete` and exit 1 because the hold input capability is absent,
while its full-screen check passes.

Audio used guest-only BlackHole 2ch and `Tests/Resources/speech_sample.wav`;
the expected text is “The quick brown fox jumps over the lazy dog.”
There was no host microphone passthrough or private dictation. The host installed
app, permissions and data were not changed.

## Automated regression evidence

- Layout regressions failed before the fix: three tests, four assertions.
- The auxiliary-panel contract failed three assertions with the old NSWindow;
  the full-screen eligibility regression also failed before its flag was added.
- Thirty-two focused window/controller/layout checks pass after the fix.
- Final full Swift suite: **3,059 executed, 47 optional tests skipped, zero
  failures** (3,012 successful tests). Log:
  `/tmp/audiowhisper-vm-final-full-tests.log`.
- Final unattended acceptance: **137 tests, zero skips/failures**, including
  actual cold/warm Whisper inference. Setup 15, recorder layout 10, capture 35,
  delivery 8, paste destination 4, hold events 63, real Whisper 2. Log/report:
  `/tmp/audiowhisper-vm-final-acceptance/`.
- Strict SwiftLint on all eight changed Swift files has zero violations.
  Build-script syntax/ShellCheck (excluding pre-existing SC2181) and six
  acceptance reporter tests pass. The reporter's printed timeout is its
  deliberate hung-child test, not a failed product check.
- An older paste-target test assumed `NSRunningApplication.current` must be
  invalid. On this desktop it represented the test's launching app. The test
  now selects a live external target and verifies that target's PID.

Packaging now accepts `--output /path/AudioWhisper.app`, validates its destination
and refuses to overwrite a running target app. Separate signed QA bundles avoid
changing a live host app's resources and permission identity.

## Limits and next acceptance targets

Use Tahoe 26 for this repeatable primary QA baseline, and add Sonoma 14 for
minimum-version compatibility. Sonoma was not provisioned in this pass;
macOS 15 CI and a 27.2 beta host do not substitute for that native run.
Physical host modifier hold/release, physical audio-device changes, multi-display
Spaces and VoiceOver still need their own acceptance evidence. This run does
not certify a universal notarized distribution build.

Two Tart experimental-VNC crashes on the beta host were VM-control environment
failures, not AudioWhisper crashes. Removing experimental VNC and using the
guest agent produced stable final runs. Initial Smart Paste attempts preceded
completion of the guest's deferred Accessibility authentication sheet; after
normal authentication, native paste passed. No TCC database was edited and
Gatekeeper assessments stayed enabled.

The reusable setup and runners are documented in
[scripts/vm/README.md](../scripts/vm/README.md). The VM disk is retained for future
runs; its process is stopped after validation.
