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

## VM feasibility

[Tart](https://tart.run/quick-start/) supports local Apple Silicon macOS guests
and automation through SSH; its documented starter image download is 25 GB.
The [guest agent](https://tart.run/blog/2025/06/01/bridging-the-gaps-with-the-tart-guest-agent/)
also supports command execution. No VM has been provisioned for this run. A
guest would provide a disposable desktop for future GUI testing but introduces
its own OS permissions and audio device behavior. It does not substitute for
physical-device acceptance on the user's Mac.
