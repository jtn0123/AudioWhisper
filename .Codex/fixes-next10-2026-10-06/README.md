# Streamlined app and nine improvements

The requested app-profile feature is removed and the other nine ranked items
are implemented. Production code/package revision: `b54a852`; later evidence
commits preserve this source tree. The prior B− code / B UI grades remain
historical baselines; this implementation batch does not automatically regrade.

| Item | Result in plain language | Evidence |
|---|---|---|
| C2 / UI C3 | No app mappings, custom profile editor or category prompt overrides. One conservative cleanup policy everywhere. About 2,900 obsolete lines removed. | 58 affected checks plus unified-prompt integration; native Writing screenshot |
| I1 | Analysis cannot quietly pass when its tool or compiler indexing fails. | Three gate regressions; stderr/report retained in CI |
| E1 | Patched fsspec without moving unrelated ML packages. | Frozen lock check, isolated runtime, then actual installed runtime and packaged offline inference |
| C1 / UI C2 | Real download progress, Cancel install and useful setup errors; partial files survive retry. The sidebar shows setup activity instead of Ready during maintenance. | Real subprocess cancellation/retry, instant failures, prelaunch cleanup; actual guest progress and cancellation |
| G1 / UI G1 | Export works in a background worker with progress and Cancel export. Cancelling preserves an existing destination. | Real 1,001-record SwiftData export/cancel tests and native 67-record export |
| I2 | Updates validate a staged signed app before stopping the installed one, keep a previous build and roll back replacement/launch errors. | Five installer checks, actual host installation and stable signing requirement |
| G2 | Speech recognition finishes before the writing model gets the serial worker. | Real pipeline routing with injected providers; no raw-speech editor warmup RPC, writing skipped after ASR failure |
| A1 | The model chosen when recording starts is passed explicitly, so later or unrelated settings cannot replace it. | Captured v3 beats conflicting v2 defaults/task-local state |
| D2 | Coverage cannot fall from about 40% to 27% unnoticed. CI now requires 40%. | Clean CI measured 40.57% (14,870/36,657 application lines); three malformed/dependency-inflation gate checks |
| H1 | Setup and developer instructions match the signed rebuild, its current screens and model choices. | README, CONTRIBUTING, rebuild and VM guides updated; H2 initial-download/offline wording corrected too |

Code D1 is excluded by user direction. Native acceptance targets macOS 26/27;
the existing macOS 15 GitHub worker remains build/test infrastructure. Remaining
code audit items are A2/E2/F1; UI B1/D1 remain separate IDs.

## Validation

[checks.json](checks.json) records 2,971 local Swift cases, 44 skips and zero
failures, 120 Python checks, six unattended-harness checks, strict lint and
mypy. The final small sidebar change additionally passed 11 focused tests and
packaged native acceptance. Full local suite runs exposed a stale setup-error
expectation and a mismatched voice-error test edit; the voice path now surfaces
the useful error too and the final suite is green. Optional engines and native
headless-render limitations are not concealed by the case count.

The fsspec lock moves only 2025.7.0 → 2026.6.0. The affected version range and
patched version are documented in [the GitHub advisory](https://github.com/advisories/GHSA-27vj-qcqg-25rc).
No ReferenceFilesystem exploit path in this app was established.

[packaged-daemon-final.json](packaged-daemon-final.json) uses the **actual
app-managed patched Python environment**, the signed packaged daemon, cached
model resolution and offline flags. It verifies Parakeet v2 fixture speech and
Qwen3.5 → Qwen3.8 → Qwen3.5 cleanup, including preserved negation. There are no
loader or chat-template replacements. Deep strict signature verification passes
afterward and no bundled bytecode cache is created. [verify_packaged.py](verify_packaged.py)
reproduces it. The earlier [packaged run](packaged-daemon.json) used an isolated
frozen QA runtime before the final sidebar polish.

## Writing policy and models

[Production results](production/results) retain 64 actual MLX edits per model
with the unified prompt and the production Swift guards extracted from source.
All 128 cases completed in one generation; three 9B outputs and four 27B
outputs retained the source after guard rejection. Corpus category labels are
historical test labels, all mapped to the same prompt; they are not app profiles.
[Source hashes](production/production-text-source.json) identify the guard and
cleaner used. The benchmark's loader resolves the pinned inventory directory;
the separate packaged check above proves actual offline cache resolution.

The new prompt retains both the label/parenthetical directive (qwen-17) and
"Keep this tentative" (qwen-25) after delivery. This is **integration evidence,
not a semantic correctness score or a controlled speed benchmark**. Build and
VM activity overlapped inference. Remaining accepted mistakes include Qwen3.5
turning ambiguous dictated words into `dd`, inventing an attached `[file]`
placeholder and removing "sure thing" from a sarcastic phrase; Qwen3.8 can also
misread dictated technical names and drop informal wording. Cleanup remains
optional and original comparison/recovery is still necessary. Profile removal
does not make a language model infallible.

Parakeet v2 remains the English recommendation, with v3 available. Qwen3.5 9B
4-bit remains the new-install cleanup recommendation; Qwen3.8 27B mixed 3-bit is
optional. Existing explicit model selections and the cleanup toggle survive.

## Native and installed app

[Initial desktop run](native/desktop/report.json) passes ten shortcut/start/cancel
cycles and one actual Whisper transcription with exactly one native Smart Paste.
[Final desktop run](native/final-desktop/report.json) rechecks two cycles and
record/stop/transcribe/paste after the sidebar change, on the exact final binary.
Both use Tahoe 26.6.2 (25G83), public fixture audio and guest-only virtual routing.
They are synthetic guest input, distinct from physical host microphone/hold-key
acceptance, and need no repeated host consent.

[Workspace checks](native/workspace-checks.json) verify profile removal, measured
file progress, cancellation back to retry, and a real 67-record export containing
67 sections and the fixture transcript. Native export did not stress thousands
of rows; the separate 1,001-record worker regression checks multi-page export and
cancellation. The first progress screenshot exposed a stale Ready label, then
`3fef45c` corrected it. [Final workspace checks](native/workspace-final.json) and
[final progress](native/model-install-progress-final.png) establish the corrected
busy status and cancellation on the final package. The installer job remains
session-owned when changing pages; the export worker writes a temporary file and
replaces the destination only after success. Concurrent external history changes
are not a transactional snapshot guarantee.

[Host installation](host-install.json) verifies the installed process and SHA,
unchanged leaf-bound signing requirement, selected settings and history, SQLite
integrity and fsspec 2026.6.0. The installer retains the previous signed bundle
under `/Applications/.AudioWhisperBackups`; the private history backup stays
outside Git. Rollback tests use disposable paths; a new process refusing to stop
can still require manual rollback from the retained build. Public distribution
signing/notarization enforcement remains the separate E2 audit item.

The clean-runner coverage baseline is [CI run 37583653445](https://github.com/jtn0123/AudioWhisper/actions/runs/37583653445).
The final 40% ratchet runs in subsequent CI; report its live result independently
from the local and native evidence here. SonarCloud remains skipped, so these
checks do not establish a Sonar quality-gate pass.
