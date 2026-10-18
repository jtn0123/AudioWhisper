# Hosted Whisper recognition investigation

Status: open. Production Whisper inference settings and the scheduled macOS 15
acceptance runner are unchanged. Passing static analysis or a decoder replay does
not establish complete recognition.

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

This isolates the observed failure to encoder inference in the macOS 15 hosted
environment. It does not yet distinguish OS/runtime from compiler differences or
establish whether physical Macs running macOS 15 are affected.

## Remaining acceptance

- Compare both hosted OS images with the same Xcode 26.3 build. The manual nightly
  input pins Xcode and separates its Swift build cache from other toolchains.
- Verify successful complete recognition with both fresh and restored model
  caches, retaining the fixture assertions.
- Preserve the real Parakeet v2/v3 and MLX inference checks.
- Resolve the supported-OS behavior before treating this as a release fix. Do not
  remove the failing macOS 15 case or raise the app's minimum OS to hide it.
