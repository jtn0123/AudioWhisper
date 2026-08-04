# ADR 0006: Model Integrity — Pinned Hashes for Shipped Models, TOFU for User Models

**Status:** Accepted
**Date:** 2026-08-03

## Context

The app downloads multi-hundred-megabyte model weights from Hugging Face at runtime and executes them. Because it ships unsandboxed (see [ADR 0001](0001-no-sandbox.md)), a poisoned model file is a meaningful attack surface.

Two distinct cases exist, and they do not warrant the same treatment:

1. **App-shipped models** — the fixed set the app offers in its own picker (WhisperKit tiny/base/small/large-v3-turbo, the Parakeet and MLX correction models). These are known at build time, so their hashes can be baked into the binary.
2. **User-added models** — arbitrary Hugging Face repos a user points the app at. Their hashes cannot be known in advance by definition.

A pure trust-on-first-use scheme treats both identically and therefore trusts the *first* download of a shipped model unconditionally — the one case where we could have done better.

## Decision

`DiskMutationSerializer.verify(at:modelIdentifier:)` splits the two:

- **Shipped model** (identifier present in `knownHashes`): the file's SHA-256 is compared against the value baked into this build. A mismatch is a **hard fail** — `ModelIntegrityError.pinnedMismatch` — including on the very first download. There is no trust-on-first-use escape hatch.
- **User-added model**: trust-on-first-use against a sidecar hash written next to the model. Later mismatches throw `ModelIntegrityError.mismatch`.

The bundled `uv` binary is verified separately, against a SHA-256 stamped at build time (see [ADR 0002](0002-embedded-uv-python.md)).

## Consequences

- **A poisoned first download of a shipped model is caught.** This is the case that matters most, since it covers every model an ordinary user will ever fetch.
- **The trust boundary for user-added models is Hugging Face over TLS, at first fetch.** This is inherent — there is no prior knowledge to check against. It should be surfaced in the UI when a user adds a custom repo, which it currently is not.
- **Shipped-model hashes are build-time constants and must be updated when a model version is bumped.** A stale pin fails closed (hard error, no transcription) rather than open, which is the correct direction but will look like a download bug if the cause is not remembered. Update `knownHashes` in the same change that bumps a model.
- **Verification is per representative file, not per byte of the model directory.** Full-tree hashing was rejected as too slow for multi-GB caches on every load.
