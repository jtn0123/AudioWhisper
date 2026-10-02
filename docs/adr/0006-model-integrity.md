# ADR 0006: Model Integrity — Pinned Revisions for Shipped Models, TOFU for the Rest

**Status:** Accepted — implemented for MLX and Parakeet; WhisperKit is trust-on-first-use (see *Revision 2*)
**Date:** 2026-08-03
**Amended:** 2026-08-25 (audit item H3); 2026-10-02 (pinned revisions replace pinned hashes)

## Context

The app downloads multi-hundred-megabyte model weights from Hugging Face at runtime and executes them. Because it ships unsandboxed (see [ADR 0001](0001-no-sandbox.md)), a poisoned model file is a meaningful attack surface.

Two distinct cases exist, and they do not warrant the same treatment:

1. **App-shipped models** — the fixed set the app offers in its own picker (WhisperKit tiny/base/small/large-v3-turbo, the Parakeet and MLX correction models). These are known at build time.
2. **User-added models** — arbitrary Hugging Face repos a user points the app at. Nothing about them can be known in advance.

A pure trust-on-first-use scheme treats both identically and therefore trusts the *first* download of a shipped model unconditionally — the one case where we could have done better.

## Decision (original, 2026-08-03) — pinned hashes

Bake a SHA-256 of each shipped model's representative file into the binary (`ModelIntegrity.knownHashes`) and hard-fail on mismatch, including on first download. User-added models fall back to trust-on-first-use.

**This was never implemented, and could not safely have been.** The table stayed empty, so every model took the trust-on-first-use path (the 2026-08-25 amendment recorded that honestly). The deeper problem was that every download followed the repo's `main` branch. A hash pinned against `main` stays correct only until the repo's next commit; after that the app would reject every fresh install of that model, fail-closed, with no transcription at all. Repos do move: `mlx-community/Qwen3-4B-Instruct-2507-4bit` was revised in January 2026, months after the app first offered it.

## Decision (Revision 2, 2026-10-02) — pinned revisions

Pin **what is downloaded**, not a hash of what happened to arrive.

- **`ModelPins`** maps each shipped MLX and Parakeet repo to a full commit hash. `download_model.py` (and the verify scripts, on a cache miss) fetch exactly that commit. A commit names the repo's whole tree, LFS pointers included, and each LFS pointer carries the file's SHA-256 — so fetching by commit over TLS gets the bytes this build was tested with, and an upstream change, hostile or merely breaking, cannot reach users until a pin is deliberately bumped.
- **`refs/main` is pointed at the pin.** A download by commit hash does not write it, and `refs/main` is what every offline lookup resolves; without this step a pinned download is invisible.
- **Loads never touch the network.** The daemon and verify scripts resolve the cached snapshot with `local_files_only=True` and load from that local path. (This also fixed a real bug: loads had set `HF_HUB_OFFLINE` *after* `huggingface_hub` was imported, which it ignores, so every "offline" load contacted huggingface.co and could pull a newer upstream revision mid-load.)
- **The trust-on-first-use record still runs** (`ModelIntegrity`), taken right after the download. For a pinned model it therefore vouches for the pinned commit, and catches the cache later being repointed, truncated, or corrupted.
- **`knownHashes` and its hard-fail branch are deleted.** Unreachable code that described a control which did not run was worse than no code.

### Coverage

| Case | What anchors the first download | Later loads |
|---|---|---|
| Parakeet, MLX correction (shipped) | pinned commit (`ModelPins`) | offline, TOFU record of the pinned ref |
| WhisperKit (shipped) | TLS only — see below | TOFU record of `config.json` |
| User-added repo | TLS only, by definition | TOFU record |
| Bundled `uv` binary | build-time SHA-256 (ADR 0002) | verified each launch |

**WhisperKit cannot be pinned from this codebase.** `WhisperKit.download(variant:…)` takes no revision; it always fetches `main`. Pinning it would need an upstream API change (or bypassing WhisperKit's downloader), and pinning a *hash* without a pinned revision reintroduces exactly the fail-closed trap described above.

## Consequences

- **A poisoned or changed upstream repo cannot reach a fresh install of a shipped MLX or Parakeet model.** That covers every MLX/Parakeet model an ordinary user will ever fetch.
- **Updating a shipped model is an explicit act**: bump its entry in `ModelPins`, from `https://huggingface.co/api/models/<repo>` (`sha`), in the same change as anything that depends on it. `ModelPinsTests` fails if an offered model has no pin or a pin is not a full commit hash.
- **Caches downloaded before pinning keep working** at whatever revision they hold. They are not forced to redownload; the next download of that model moves `refs/main` to the pin and reuses any unchanged blobs.
- **The trust boundary for WhisperKit and user-added models is Hugging Face over TLS, at first fetch.** For user-added repos this is inherent. It should be surfaced in the UI when a user adds a custom repo, which it currently is not.
- **The trust-on-first-use record does not live beside the model** (audit item E3, 2026-08-25). It lives under `~/Library/Application Support/AudioWhisper/model-integrity/`, keyed by a hash of the model path, so rewriting a model does not also rewrite the record vouching for it. This removes the trivial bypass; it does not make TOFU tamper-proof against a local process running as the user.
- **Verification is per representative file, not per byte of the model directory.** Full-tree hashing was rejected as too slow for multi-GB caches on every load.
