# Unattended acceptance

Run from the worktree:

```sh
python3 scripts/run-unattended-acceptance.py --real-engines
```

The runner does not launch the GUI, request consent, listen to the microphone,
enable Accessibility, or send desktop keystrokes. Each invocation has isolated
settings. Delivery uses an in-memory Library and a named pasteboard. The real
Whisper stage uses the public speech fixture and may download the base model.
Omit `--real-engines` for a deterministic run without model downloads.

| Stage | What it verifies | Boundary |
|---|---|---|
| Setup | Repeated consent requests coalesce; denial does not re-prompt; missing/broken models block readiness | Injected permission/model responses |
| Recorder layout | Real SwiftUI hosting size, whole-frame placement, auxiliary panel and full-screen eligibility | Active WindowServer; no audio hardware |
| Capture | Start/stop/cancel, startup deadlines, repeated shortcuts, retry ownership, stale results and input routing | Injected hardware and session commands |
| Delivery | Real pipeline assembly, clipboard, history, usage, retry and cleanup | Stub speech provider; named clipboard and in-memory history |
| Paste destination | Exactly one paste for matching destination; no paste for a changed destination or retired session | Injected PID, permission and keystroke sink |
| Hold events | Duplicate down/up, left/right modifiers, local/global monitor wiring and missed-release watchdog | Injected events and physical modifier state |
| Real Whisper | Actual local transcription, warm-model reuse and incremental/full-file parity | Public file input; no physical microphone |

Logs and `report.json` go into a new `.build/acceptance/<uuid>` directory, or a
new directory specified by `--output`. The report records source commit, dirty
state, elapsed time, executed/skipped counts and remaining native boundaries.
A timeout, crash, test failure, zero executed tests or skipped tests makes the
command fail. Each stage has a 15-minute deadline (`--timeout` overrides it);
the runner terminates its own process group if a stage hangs. A blocked test
does not become an interactive request.

The full Swift suite and universal bundle CI remain separate checks. Physical
microphone capture, actual OS hotkey dispatch, paste into an external editor,
physical hold and permission persistence are not certified by this runner.
Prior live evidence remains in [the recording report](recording-permission-fixes.md).

## Observed run on 2026-10-04

All six stages pass: **127 tests, zero skips or failures** (15 setup, 35 capture,
8 delivery, 4 paste destination, 63 hold events and 2 real Whisper). The actual
engine transcribes the public sentence correctly on both cold and warm runs;
incremental/full-file outputs agree. This run used the implementation at
`067c03a` plus the new runner in a dirty working tree. Evidence is in
`/tmp/audiowhisper-unattended-acceptance-20261004/report.json` and adjacent logs;
these contain fixture output only. Reporter tests also exercise a real hung
child process to verify termination. The new runner's reporting tests run in CI.

## Latest observed run on 2026-10-04

All seven stages pass: **137 tests, zero skips or failures**, including the new
10-test recorder-layout stage. This used `77d85cd` plus the VM polish changes.
The report and adjacent logs are in `/tmp/audiowhisper-vm-final-acceptance/`.
The full Swift suite separately executed 3,059 tests with 47 optional skips and
zero failures (3,012 successful tests).

## Native VM acceptance

A disposable Tart Tahoe guest has now been provisioned and exercised. Actual
guest shortcut dispatch, ten start/cancel cycles, Whisper transcription, native
Smart Paste and full-screen recording pass. Physical modifier hold remains
incomplete because the remote input stream omits left/right device flags.
These checks use virtual guest audio and synthetic native OS events. They do
not certify physical host hardware or replace minimum-version compatibility.
See [the VM validation report](macos-vm-validation.md) and
[repeatable VM instructions](../scripts/vm/README.md).
