# Hosted Whisper recognition investigation

Status: production candidate under validation (2026-10-19). The scheduled
acceptance runner remains macOS 15. Static analysis and raw-SDK diagnostic passes
are separate from production recognition acceptance.

## Reproduction

The public `speech_sample.wav` fixture says “The quick brown fox jumps over the
lazy dog.” Run the six real Whisper tests with:

```sh
RUN_E2E=1 swift test --no-parallel -Xswiftc -DTESTING \
  --filter LocalEngineFixtureTests/testWhisper
```

These tests require actual fixture words, including for full-file/incremental
loading and repeated app-service inference. Diagnostic tensors are captured from
the public fixture on a working Mac and are used only to isolate components.

## Observed results at `22dfeb1`

| Environment | Compiler | Result |
| --- | --- | --- |
| Hosted macOS 15.7.9, VirtualMac2,1 | Swift 6.2.4 | Five tests fail; reference-encoded decoder replay passes |
| Hosted macOS 26.6.2, VirtualMac2,1 | Swift 6.3.3 | All six tests pass, including complete app recognition and warm reuse |
| Local macOS 27.2 | Local Xcode toolchain | Earlier five tests and the additional CPU/GPU-allowed encoder test pass |

Hosted runs: [macOS 15](https://github.com/jtn0123/AudioWhisper/actions/runs/39156971054),
[macOS 26](https://github.com/jtn0123/AudioWhisper/actions/runs/39156972758).
Both runs downloaded fresh Whisper models. All 14 compared model files have
matching SHA-256 fingerprints across the hosted runs and the working reference.
The decoded input samples and tokenizer output also match.

On hosted macOS 15:

- Mel output nearly matches the reference: maximum error 0.00098, RMS 0.000024.
- Encoder output diverges: maximum error 11.96, RMS 0.86. Synchronous prediction
  using the exact reference mel tensor also diverges.
- Replaying reference mel through the hosted encoder produces `>>`. Replaying
  reference encoder output through the hosted decoder produces the full sentence.
- Removing mel row padding and permitting GPU execution for the encoder do not
  restore recognition. GPU permission does not prove which device executes it.

On hosted macOS 26, mel matches exactly and encoder RMS error is 0.042 rather than
0.86. All complete recognition paths produce the expected sentence. The encoder
is not numerically identical to the local reference (maximum error 4.95).

## Matched toolchain at `dc7e1dd`

Both fresh-model runs below use Xcode 26.3 build `17C529`, with Swift 6.2.4
(`swiftlang-6.2.4.1.4`, `clang-1700.6.4.2`):

- [macOS 15.7.9](https://github.com/jtn0123/AudioWhisper/actions/runs/39158979383):
  five Whisper tests fail; reference-encoded decoder replay passes.
- [macOS 26.6.2](https://github.com/jtn0123/AudioWhisper/actions/runs/39158981078):
  all six Whisper tests pass.

All 14 compared model-file fingerprints still match. The encoder comparison and
replay results reproduce the earlier environment difference. This rules out the
compiler-version difference in these runs and isolates the measured failure to
encoder inference in the macOS 15 hosted environment. It does not establish
whether physical Macs running macOS 15 are affected or identify a production fix.

The [complete macOS 26 real-engine test step](https://github.com/jtn0123/AudioWhisper/actions/runs/39161164830)
also passes all nine fixtures: six Whisper cases, actual MLX correction and two
Parakeet cases. These include Parakeet v2/v3 warm reuse, switching back to v2, and
Spanish recognition without English translation. Model caching is enabled in
that run, and the Whisper cache is saved successfully.

The [restored-cache run](https://github.com/jtn0123/AudioWhisper/actions/runs/39161787961)
confirms an exact Whisper model-cache hit and successful restore, then passes all
six Whisper tests. Complete app-service recognition and warm reuse produce the
expected sentence. Fresh and restored model-cache recognition are therefore
established on hosted macOS 26 with Xcode 26.3.

## Remaining acceptance

- Resolve the supported-OS behavior before treating this as a release fix. Do not
  remove the failing macOS 15 case or raise the app's minimum OS to hide it.
- Determine whether physical macOS 15 systems reproduce the hosted encoder
  failure; the two virtual OS environments do not establish that scope.
- Retain the meaningful complete-recognition assertions and the passing real
  Parakeet v2/v3 and MLX checks when evaluating a fix.

## Bounded compatibility candidate (October 19)

Repackaging the embedded encoder specification with its existing weights and
compiling it on the target OS restored complete fixture recognition with the
SDK's normal compute policy on both [macOS 15](https://github.com/jtn0123/AudioWhisper/actions/runs/39176625241)
and [macOS 26](https://github.com/jtn0123/AudioWhisper/actions/runs/39176627132).
The embedded specification and shipped compiled graph report different conversion
provenance. This supports a compatibility workaround; it does not establish
corruption, graph equivalence, or a defect in a specific Core ML operation.

`WhisperEngineFactory` now prepares only the exact known Base encoder on Apple
Silicon macOS 15. Other models, OS versions, and unknown upstream artifacts keep
the SDK encoder. Known affected artifacts with missing or changed preparation
sources fail clearly. Compilation uses the original SDK compute policy and never
edits upstream assets. Prepared encoders live separately under
`PreparedWhisperEncoders/base`, keyed by both source hashes, recipe, OS build,
architecture and compute policy. Same-key preparation coalesces, publication is
atomic, cached models are load/shape validated, and an unloadable derived cache is rebuilt once.
This validation is not a checksum of every prepared byte. A cancelled waiter drains
shared preparation before returning, preserving other callers and staging ownership.

`WhisperProductionAcceptanceTests` exercises the actual app service and factory:
cold/warm/cache reload, full/incremental loading, verification, and persistent
prepared-cache validation. Nightly runs select this production suite with the
existing Parakeet/MLX fixtures. The unchanged direct CPU/GPU, compact-input, boundary-replay and loading controls remain explicitly
available through `raw_diagnostics`; their known macOS 15 failures are not
reclassified as SDK passes. The embedded-specification experiment is another
separate opt-in input.

Local evidence: all fourteen preparation/cache/compiler-contract tests and all three
production recognition and persistence tests passed on macOS 27.2. Hosted
production and cache qualification is recorded below. Other Whisper variants,
physical macOS 15 and packaged-device acceptance remain open. No matched latency claim.

The nightly workflow caches prepared encoders separately. `cold_whisper` skips
upstream model-cache restoration; `cold_prepared_encoder` skips the derived-cache
restore. OS-build keys are validated inside the cache, so restoring an encoder
compiled for another build cannot select it. Cross-job restored prepared-cache
acceptance passed for the tested hosted build, as recorded below.

## Production qualification at 86402ea

Complete scheduled engine acceptance passed on
[macOS 15 with fresh Whisper and prepared assets](https://github.com/jtn0123/AudioWhisper/actions/runs/39235433063)
and [macOS 26](https://github.com/jtn0123/AudioWhisper/actions/runs/39235436682).
Both retained Parakeet v2/v3 recognition, the Spanish v3 fixture and actual MLX
correction. All three production Whisper tests recognized the sentence, preserved
full/incremental parity and validated persistent prepared-cache loading.

The added `e7f765c` test counts actual compilations for the current runtime cache
identity. `require_prepared_cache_hit` asserts zero first-load compilations, so an
outer Actions cache hit containing only another OS-build identity cannot falsely
pass restored-derived-cache acceptance. The [restored-cache run](https://github.com/jtn0123/AudioWhisper/actions/runs/39237985038)
passed all four production tests at `e7f765c`, reporting
`firstCompilations=0 secondCompilations=0` and the expected spoken sentence.
Physical macOS 15 and other Whisper model variants remain unqualified.

## Ordinary PR coverage

Normal CI now exercises real Core ML compilation and loading with two original,
sub-200-byte sum/broadcast models. The expected encoder dimensions compile and
persist; a different output shape and invalid specification fail without leaving
staging or a published cache. Additional tests cover a peer publishing first,
runtime environment selection, actionable repair errors and missing local assets.
The fixtures require no downloaded weights and do not qualify speech recognition.

After integration with merged #51, the local coverage export covers 94 of 109 new executable lines (86.2%),
up from its failing hosted measurement of 63.9%. The 80% gate is unchanged;
hosted Sonar confirms 86.2% with zero new issues on `ef49261`.

## Integration with merged workflows

PR #51 merged as `f92fd0b` after all 11 checks. The recognition branch retains
its language selection, clean meeting tokens, timestamp/source mapping and strict
installed-assets policy while routing the cache through `WhisperEngineFactory`.
The full 3,283-case local Swift suite passes, including configured opt-in skips.
Four actual-model recognition/persistence/meeting tests pass locally; the separate
macOS 15 prepared-cache policy test correctly skips on the newer local OS.
Integrated acceptance passed at `ef49261` with fresh Whisper assets on
[macOS 15](https://github.com/jtn0123/AudioWhisper/actions/runs/39246145332) and
[macOS 26](https://github.com/jtn0123/AudioWhisper/actions/runs/39246148239).
Both preserve Parakeet v2/v3 English/Spanish and actual MLX correction, and both
execute the installed-only meeting fixture after Base installation. The macOS
15-only exact-cache-identity case correctly skips on macOS 26.

The [integrated restored-cache run](https://github.com/jtn0123/AudioWhisper/actions/runs/39250250114)
passes all four production cases and the meeting fixture on macOS 15. It reports
`firstCompilations=0 secondCompilations=0`, expected speech and clean source-labeled
meeting segments at the requested offset. All 11 hosted checks pass at `ef49261`.
Physical-device and public-distribution acceptance remain separate and open.

The real MCP transport test locates the app beside its running test bundle,
covering the current build with either an in-checkout or shared scratch directory.
Its old fixed `.build/debug` assumption failed in the integration worktree before
this correction; the corrected test passes without skipping the executable check.
