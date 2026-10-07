# macOS desktop QA

These helpers drive only a disposable macOS VM. They use a throwaway TextEdit
document and `Tests/Resources/speech_sample.wav`. They never operate the host
desktop. Results are synthetic guest input and virtual audio, not physical
keyboard/microphone acceptance.

## OS scope

| OS | Role | Current evidence |
|---|---|---|
| Tahoe 26 | Primary desktop QA guest | 26.6.2 (25G83): recording, cancel, transcription, native Smart Paste and full-screen window isolation pass |
| macOS 15 | Existing CI runner | Separate from native desktop acceptance |
| Host 27.2 beta | Optional environment comparison | Not the primary reliability baseline |

Native acceptance is scoped to macOS 26/27. Older-OS and broader compatibility work from audit D1 is excluded by user direction. Existing CI host versions remain build/test infrastructure.

## Prepared guest

The retained VM is `audiowhisper-qa-tahoe`: four CPUs, 8 GB RAM, 50 GB disk,
one 1024×768-point display (2× backing scale). It uses Tart 2.40.1 and the
Cirrus `macos-tahoe-base:latest` image resolved to
`sha256:87f3aa5ce21b5c876268f233bdfecf38b4c2a8116fe9bbb718e714cbae187377`.
The tag is mutable; record the resolved digest and `sw_vers` for each new guest.

Install Tart from its [official release](https://github.com/cirruslabs/tart/releases)
and verify the published archive checksum. On this host the formula installation
failed, so the signed release application is retained at:

```sh
AW_QA_TART="$HOME/.local/share/audiowhisper-qa/tools/tart.app/Contents/MacOS/tart"
AW_QA_ROOT="$HOME/.local/share/audiowhisper-qa"
```

For a new VM (not needed for the retained guest):

```sh
"$AW_QA_TART" clone ghcr.io/cirruslabs/macos-tahoe-base:latest audiowhisper-qa-tahoe
"$AW_QA_TART" set audiowhisper-qa-tahoe --cpu 4 --memory 8192 --disk-size 50 --display 1024x768pt --no-display-refit
```

Share only curated QA assets. Keep a stable local development signing identity
across app replacements; its private key stays in the host Keychain. Package to
a new path so a running app's signed resources are never overwritten:

```sh
mkdir -p "$AW_QA_ROOT/share"
cp Tests/Resources/speech_sample.wav "$AW_QA_ROOT/share/"
bash scripts/build.sh --debug --local-signing --output "$AW_QA_ROOT/share/current/AudioWhisper.app"
```

Compile the guest helpers on the Apple Silicon host using Xcode's Swift toolchain;
do not execute the input or audio-routing helpers on the host:

```sh
. scripts/lib/xcode-env.sh
ensure_xcode_toolchain
swiftc scripts/vm/probe.swift -o "$AW_QA_ROOT/share/probe-v2"
cp "$AW_QA_ROOT/share/probe-v2" "$AW_QA_ROOT/share/probe"
swiftc scripts/vm/input.swift -o "$AW_QA_ROOT/share/input"
swiftc scripts/vm/audio-route.swift -o "$AW_QA_ROOT/share/audio-route"
swiftc scripts/vm/inspect-workspace.swift -o "$AW_QA_ROOT/share/inspect-workspace"
```

Start the prepared guest in a separate terminal. The share is read-only and
audio, clipboard and USB passthrough are disabled:

```sh
umask 077
"$AW_QA_TART" run audiowhisper-qa-tahoe --no-graphics --no-audio --no-clipboard --no-usb-accessories \
  --dir="qa:$AW_QA_ROOT/share:ro" > "$AW_QA_ROOT/tahoe-run.log" 2>&1
```

For a fresh guest, complete its normal setup and consent UI inside the VM once.
The retained guest already has these prerequisites:

- `/Applications/AudioWhisper.app`, Whisper base installed and verified, shortcut
  `⌥⇧⌘R` enabled, Express Mode off, Smart Paste on, completion sound off.
- One disposable TextEdit document, with no save sheet open.
- AudioWhisper Microphone and Accessibility consent; Tart guest agent Screen
  Recording and Automation consent for screenshots/System Events. Wait for any
  deferred macOS authentication sheet and complete it before closing Settings.
- Guest-only [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole), with
  guest input and output routed to it using `audio-route`. This pass used the
  official signed/notarized 0.7.1 package, SHA-256
  `57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf`.
- Public Whisper base weights copied into the rebuild's guest Application
  Support model directory, or downloaded through its model setup UI.

Replace the guest app only after quitting it, using `tart exec` to run guest
`ditto` from the share to `/Applications/AudioWhisper.app`, then reopen it. Use a
fresh share subdirectory for each package to avoid stale shared-file caches.
No host permission changes, TCC database edits or security disabling are needed.
Gatekeeper assessments remained enabled during this run.

`inspect-workspace` reads the running workspace's native accessibility button
labels, selected state and focus in the retained guest. It refuses the host.
Use it through `tart exec`; SwiftUI attributed labels can be missing from
System Events' basic `name`/`description` properties even when direct AX
attributes contain the correct label. It does not change focus or settings.

## Repeatable runs

Choose new output directories for every run:

```sh
python3 scripts/vm/run-desktop-acceptance.py --tart "$AW_QA_TART" \
  --vm audiowhisper-qa-tahoe --cycles 10 --output "$AW_QA_ROOT/results/new-desktop-run"
python3 scripts/vm/run-extra-desktop-acceptance.py --tart "$AW_QA_TART" \
  --vm audiowhisper-qa-tahoe --output "$AW_QA_ROOT/results/new-fullscreen-run"
"$AW_QA_TART" stop audiowhisper-qa-tahoe
```

The first runner checks shortcut dispatch, recorder bounds, ten cancellations
without clipboard delivery or focus theft, actual Whisper inference, exactly
one app-generated paste into TextEdit, and the signature before/after inference.
The extra runner checks Preferences on the desktop, recorder visibility over
full-screen TextEdit, native paste there, then modifier hold/release capability.
Both capture evidence and exit nonzero on failure or incomplete coverage; they
do not ask the host user to click through a blocked step.

This guest's remote input produces logical Option (`0x80000`) without physical
Left Option (`0x20`). The hold case therefore reports **incomplete**, and the
extra runner exits 1 despite its full-screen case passing. Do not call that a
product failure or change left/right key semantics to make the VM pass.
The separate unattended Swift runner covers 63 hold-event cases.

`control.py` is an optional loopback VNC bootstrap helper requiring `vncdotool`
in a separate venv. It reads credentials from a private Tart log without printing
them. Experimental Tart VNC crashed on this beta host, so normal runs use the
guest agent instead. `read-screen.swift` performs OCR on guest screenshots only.

See [the validation report](../../.Codex/macos-vm-validation.md) for the observed
results and [Tart's quick start](https://tart.run/quick-start/) for VM lifecycle
details.
