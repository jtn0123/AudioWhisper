# ADR 0001: Ship Unsandboxed (Developer ID Signed + Notarized)

**Status:** Accepted
**Date:** 2026-05-14
**Amended:** 2026-08-25 (audit item H4 — corrected two facts that drifted; the decision itself stands)

## Context

AudioWhisper's core features require capabilities that the macOS App Sandbox does not grant or grants only with severe limitations:

- **Press-and-hold push-to-talk** requires monitoring modifier-key state via `CGEventTap` — sandbox blocks this without an entitlement that the App Store does not approve for general apps.
- **Smart Paste** posts synthetic `⌘V` events via `CGEvent.postToPid` — same restriction.
- **Prompt overrides** at `~/Library/Application Support/AudioWhisper/prompts/` use direct filesystem access — sandbox would force this through `NSOpenPanel`, breaking the silent-override UX.
- **Global hotkeys** use Carbon APIs that sandbox treats with restrictions. (Originally via the `HotKey` library; the app moved to `KeyboardShortcuts` 3.x, which relies on the same underlying APIs, so the reasoning is unchanged.)

## Decision

Ship as a Developer ID–signed, notarized app, *not* sandboxed.

> **Amended 2026-08-25 (H4):** this originally read "Distribute via direct
> download and Homebrew cask." That describes **upstream**, not this fork. This
> fork publishes no releases and no tap — `make update-brew-cask` and
> `make publish-brew-cask` are deliberately disabled because, as inherited, they
> pushed into the upstream author's repository. See the README's *Installation*
> section and `HOMEBREW.md`. Building from source is the only distribution path
> here.

## Consequences

- **Cannot ship via the Mac App Store.** Distribution is build-from-source for this fork; direct download + brew for upstream.
- **Notarization is mandatory** for any release that is distributed. `scripts/build.sh --notarize` handles it. This fork ships no releases today, so in practice it matters only if that changes.
- **Code signature changes invalidate Accessibility permission** — users must re-grant after each install. Documented in README.
- **Higher security responsibility:** without the sandbox safety net, we must be careful about subprocess execution, file paths, and bundled binaries (see ADR 0002).
