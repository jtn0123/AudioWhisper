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

Current evidence: all five preparation/cache unit tests and all three
production recognition and persistence tests passed locally on macOS 27.2. Hosted production
acceptance, fresh-download/restored-cache runs, other Whisper variants, physical
macOS 15, and packaged-device acceptance remain open. No matched latency claim.

The nightly workflow caches prepared encoders separately. `cold_whisper` skips
upstream model-cache restoration; `cold_prepared_encoder` skips the derived-cache
restore. OS-build keys are validated inside the cache, so restoring an encoder
compiled for another build cannot select it. Cross-job restored prepared-cache
acceptance is still pending.

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
pass restored-derived-cache acceptance. This test-only qualification is pending;
physical macOS 15 and other Whisper model variants remain unqualified.
