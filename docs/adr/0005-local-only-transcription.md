# ADR 0005: Local-Only Transcription (Cloud Providers Removed)

**Status:** Accepted
**Date:** 2026-08-03

## Context

Upstream `mazdak/AudioWhisper` shipped four transcription providers: OpenAI Whisper (cloud), Google Gemini (cloud), local WhisperKit (CoreML), and Parakeet-MLX. This fork removed both cloud providers.

The motivation is that the two on-device engines cover the use case. WhisperKit runs on Intel and Apple Silicon; Parakeet-MLX handles 25 languages on Apple Silicon. Keeping the cloud paths meant maintaining API-key entry, Keychain storage, per-provider error taxonomies, endpoint overrides, and a large-file upload path — for a capability that contradicts the app's main privacy claim.

This was never written down as a decision. It was inferred from the code by two consecutive audits, and in the interim the README continued to document OpenAI and Gemini as shipping features, including a Privacy section that told users cloud options transmit their audio.

## Decision

`TranscriptionProvider` has exactly two cases, `.local` and `.parakeet` (`Sources/Models/TranscriptionTypes.swift`). No cloud transcription path exists. Semantic correction is likewise local-only, via MLX.

Historical data is *not* migrated. `TranscriptionRecord.provider` is persisted as a raw `String`, so history written by a pre-2.0 build still contains `"openai"` and `"gemini"`.

## Consequences

- **Audio never leaves the device.** Network access is limited to model downloads from Hugging Face, on explicit user action. This is now a property the code enforces, not a configuration the user must get right.
- **Presentation code retains `"openai"` / `"gemini"` cases** in `DashboardHomeView` and `MenuPopupViews`. These are *not* dead code: dropping them renders pre-2.0 history as "Openai" with a generic icon. They stay until a store migration rewrites or drops those records. Both sites carry a comment saying so — do not "clean them up".
- **Apple Silicon is effectively required** for the full feature set. Parakeet and MLX correction are Apple-Silicon-only; Intel users get WhisperKit alone, more slowly.
- **`KeychainService` is retained** and still referenced by `ProviderSettingsState`, `SpeechToTextService`, and `SemanticCorrectionService`, though no cloud key is required to transcribe. Revisit whether it still earns its place once the store migration lands.
- **This fork diverges from upstream in a user-visible way.** Upstream's prebuilt binaries and Homebrew cask (`mazdak/tap`) are a *different build* that still ships cloud providers. The README carries a fork notice saying so, because a user installing the cask expecting this behaviour would get something else.

## Open

A store migration that rewrites or drops pre-2.0 `provider` values would let the retained presentation cases go, and would let us reconsider `KeychainService`. Not scheduled.
