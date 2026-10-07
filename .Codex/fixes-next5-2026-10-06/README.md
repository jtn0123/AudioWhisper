# Five ranked fixes — 2026-10-06

Implements f30c081 code B1–B4/C3 and UI C1/E1. Original letter grades remain
historical baselines; 15 code and five UI improvements remain.

| Item | Result | Regression evidence |
|---|---|---|
| B1 | Preserve ordinary parentheses/brackets, line breaks and internal spacing; remove only recognized acoustic tags | Preservation checks failed before; 75 cleaner/service/integration checks passed after |
| B2 | Stronger production instructions and conservative checks for negation, amounts, names, literal code/flags and invented message framing; warn when edits are rejected | Ten unsafe-output assertions failed before; service/session checks pass; real model review also found and fixed four false rejections |
| B3 | Compare long content with a finite character/token operation budget; uncertainty retains the original | Unrelated equal-length edits and truncation rejected, small long edit accepted, 120k-character adversarial input bounded |
| B4 / UI C1 | Compare with original / Use original in Record; Original transcript / Copy original in Library | Live pipeline/session/history integration proves restore/copy without a second delivery, saved pair and history-off privacy; SQLite reopen and old-schema migration pass |
| C3 / UI E1 | Native window owns its size instead of adopting page fitting size | Native hosting test reproduced 870×1185/1153-point content minimum; fixed test and packaged guest retain 870×620 |

Each ranked item has its own implementation commit. Verification also repaired
history tests that accidentally initialized the live database and a late queued
download-progress callback. A native layout test now initializes AppKit before
creating its window. Hosted macOS 15 workers still aborted inside this native
fixture after that bootstrap. The repository documents false-positive display
probes in headless runners, so this one desktop fixture is explicitly skipped
on GitHub-hosted runners and runs on interactive desktops. Its window assertions
remain intact. The exact aborting framework frame was not captured; this is a
native-test environment limit, not macOS 15 app acceptance. Native proof comes
from the separate real guest, while all service/data regressions remain in CI.

## Local verification

[checks.json](checks.json) records the implementation head, full Swift suite
(3,073 discovered cases, zero failures), 109 main Python checks, six unattended
harness checks and ten benchmark-scoring checks. Optional real-engine Swift
cases remain gated; the native hosting fixture requires an interactive desktop. Strict local SwiftLint 0.65.1 passes; CI pins 0.65.0.

Original propagation/recovery failed five assertions before implementation,
then 68 focused pipeline/session/delivery/model tests passed. A disposable
SQLite made with the f30c081 model in module AudioWhisper retained its UUID/text
through migration; the added optional original field was nil on the old row,
and a new original/final pair survived reopening. The actual packaged guest
also migrated its nine existing history records without losing any.

## Real Qwen outputs

[production/results](production/results) retains 64 actual MLX edits per model
using the app's installed Python and pinned cached builds, with current
production prompts and the actual Swift guards extracted from source. Both
models completed every case in one generation. Six edits per model retained
the source after guard rejection. Source hashes are in
[production-text-source.json](production/production-text-source.json).

Review identified ordinary missing-apostrophe corrections and already dictated
email sign-offs that the first guard rejected; four regression assertions
failed and now pass. The previously observed dropped command warning is either
retained by the model or rejected by the guard. The relay/refund instruction
now survives without an invented greeting/sign-off in both models.

These checks are conservative, not a semantic correctness score or a controlled
speed benchmark. Build/desktop activity overlapped inference. The 9B output for
qwen-17 still reformats a label directive undesirably, and both models omit the
explicit "Keep this tentative" wording in qwen-25 while retaining "may" and the
need for more tests. Original comparison/recovery covers remaining editing
mistakes; the guard cannot prove roles or every clause's meaning.

[packaged-daemon.json](packaged-daemon.json) records a real offline packaged
RPC ping and model switching 3.5 → 3.8 → 3.5 using production prompts, without
loader/template replacements. Grammar outputs succeeded; the raw command
output still dropped its warning, which the separately tested Swift guard
rejects. Deep strict signature verification passed afterward, with no bundled
bytecode cache files.

## Native VM

The retained Tahoe 26.6.2 (25G83) guest uses a 1024×768-point display. The final
package reuses the same leaf-bound local signer, with no TCC reset or new consent
prompt. [desktop/report.json](native/desktop/report.json) records ten actual
guest shortcut/start/cancel cycles and one Whisper fixture transcription with
exactly one native Smart Paste. This is synthetic guest input and virtual audio,
not physical host microphone/hold-key acceptance or notarization.

[workspace-checks.json](native/workspace-checks.json) and screenshots establish
contained 870×620 bounds for both original Library repro attempts, all five
pages, 55 added long transcripts and a genuine no-results search. The saved
oversized frame from the old build also reopened inside the visible display.
The native Library disclosure reveals both versions; Copy original copies the
expected source and leaves the app focused. [short-original-copy.json](native/short-original-copy.json)
and [the screenshot](native/library-short-original-visible.png) record this
with disposable fixture pairs. Workspace Use original is covered by live
pipeline/session integration; no real guest MLX inference is claimed.

The first AX-only search click did not focus the field. A native guest mouse
click at the observed field bounds plus real key events produced the verified
no-results screenshot. Artifacts prefixed `attempted-` document unsuccessful
automation, not app failures or accepted state coverage.
