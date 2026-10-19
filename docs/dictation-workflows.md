# Dictation workflows

The October 18 implementation pass follows the stable IDs in
[the product tracker](product-roadmap.md). The user authorized all listed
increments. Software completion and device/release acceptance remain separate.

## Modes, app rules and context

Preferences → Dictation modes supports named setups, editing/renaming,
duplication and JSON import/export. Existing mode files decode with automatic
language, conservative cleanup, empty task instructions and no context.
Whisper supports an explicit language; Parakeet uses the selected model's
language behavior. A style rewrite is an explicit writing task. Conservative
cleanup retains its edit-distance and detail checks. Rewrites permit formatting
changes but still check protected names, numbers, negation and literal code;
these checks are safeguards rather than semantic equivalence proof.

Select **Automatic · App rules** to use exact bundle-ID rules. A manually chosen
mode stays active until Automatic is selected again. Rules never rewrite global
settings. The destination, resolved mode and settings are captured once before
recording; a different resolved voice model gets its own runtime, installed-model
and prior-verification check before the microphone opens. Retries retain that
snapshot.

Reference text is opt-in per mode. Clipboard or selected text is captured once
before the recording overlay or transcript copy can change it. Its source, time
and preview appear on Record. Context is bounded to 4,000 characters and sent
only as local spelling/name reference to writing cleanup. It is never included
in ordinary history or recaptured during retry. Practice, file import, automation
and history reruns do not capture external context. Imported modes reset context
to off; context consent must be enabled locally. This feature does not promise
to replace a previously selected range in another app. Selected-reference mode uses
copy-only delivery so automatic paste cannot overwrite that reference. Mode archives
are bounded to 8 MB; import validates the complete file before changing preferences.

## Library writing versions

**Run writing cleanup…** starts with `originalText ?? text`. It bypasses audio
recognition and rule formatting, so vocabulary replacements are not applied
twice. Generation produces a preview. **Save version** attaches the result to
the same record, retaining the ten latest versions. The original text, date,
duration and recording/word counters remain unchanged. No audio retention is
introduced. Deleting or expiring a record also deletes its versions. Each run
is limited to 20,000 characters; failed/rejected generation preserves the source.

## Local automation

Use the installed app executable, for example:

```sh
AudioWhisper.app/Contents/MacOS/AudioWhisper --help
AudioWhisper.app/Contents/MacOS/AudioWhisper status
AudioWhisper.app/Contents/MacOS/AudioWhisper modes
AudioWhisper.app/Contents/MacOS/AudioWhisper transcribe /path/clip.wav --json
AudioWhisper.app/Contents/MacOS/AudioWhisper mcp --allow-directory /path/audio
```

`transcribe` accepts an optional `--mode <UUID>`. JSON includes original text,
final text, audio duration and an explicit writing-stage outcome. Automation
requires installed local voice assets/runtime. It never requests microphone
access, reads reference context, changes the clipboard, pastes, or adds library
records. Files must be readable regular files smaller than 256 MB.

The MCP server implements the
[2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
and [newline-delimited stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports),
with compatibility negotiation for 2025-06-18 and 2025-03-26. It offers `status`
and `transcribe_file`, requires an explicit allowed directory, resolves symlinks
before scope checks, bounds messages to 1 MB, permits one inference at a time,
and handles ping, cancellation, initialization, JSON-RPC errors and EOF. This
is a bounded 2025 protocol interface, not a claim of every newer extension.
Vendor stdout is redirected to stderr while protocol messages use the original
output pipe. No network listener is opened.

`audiowhisper://open?page=library` and the other page IDs in `--help` only open
the visible workspace. Links cannot start recording, import files, switch modes,
enable context, install models or paste. The URL scheme is registered in both
source and generated bundle plists.

## Delivery and announcements

Record distinguishes copied text, confirmed paste, unverified paste, and manual
fallback. Clipboard restoration is reported only when the loan marker still
matched and restoration actually occurred. A new user clipboard copy is never
overwritten or described as restored. **Copy text** remains available after a
restoration. Coarse recording/transcribing/error/delivery announcements belong
to the session and therefore work in Express Mode without a recorder HUD. Draft
words, waveform frames and timers do not trigger announcements. Actual VoiceOver
acceptance remains R4.

## Meetings

Meetings is a separate workspace page. Choose microphone and/or system audio,
start explicitly, then stop and process with installed local models. System audio
uses ScreenCaptureKit audio output; no screen images are saved. Both sources share
a host-time epoch, with their own source labels and timestamped CAF chunks. Use
headphones to avoid microphone pickup of system playback. This first version is
limited to 30 minutes. Closed chunks and atomic manifests support interrupted
capture recovery; unreadable folders do not hide readable meetings.

Optional local SpeakerKit models estimate clusters within each source. Labels are
not identified people or cross-track matches. Optional local notes use the installed
writing model and a dedicated bounded summary operation. Review speakers, decisions,
owners and dates against the transcript. Processing checkpoints preserve recognized
segments on later failure. Audio is retained on failure/interruption, and removed
only after successful processing unless Keep source audio was selected. Transcripts,
notes and retained audio are removed only by explicit meeting deletion. Export is
an explicit text-file action; meetings never automatically paste into another app.

## Validation

The identical-settings mode regression failed before the fix and passes after.
The latest full Swift run passed 3,258 tests, including configured skips. Focused
workflow tests exercise mode/schema migration, consent resets, rewrite safeguards,
app-rule readiness, one-time context capture/retry, real SwiftData versions,
meeting checkpoint/ordering/retention/recovery, and real executable MCP framing/EOF.
Coverage of new code must pass the existing 80% hosted gate before merge. Fixture
checks do not close physical microphone, system-audio, cross-Space delivery,
VoiceOver, matched performance or public distribution acceptance.

Meeting Stop drains buffers admitted before closing, and delayed capture failures
are scoped to their meeting. Notes generation owns a private local worker;
cancellation retains the dictation reservation until its process is reaped.
Automation preflight reads installed runtime state without creating a Python project.
