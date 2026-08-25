# Security Policy

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report privately through GitHub's private vulnerability reporting:
[**Report a vulnerability**](https://github.com/jtn0123/AudioWhisper/security/advisories/new).

If that is unavailable to you, open a public issue containing only "security
report, requesting a private channel" — with no details — and a maintainer will
follow up.

Expect an acknowledgement within **7 days**. This is a personal fork maintained
in spare time, not a staffed project; please treat that as the realistic
response window rather than a service commitment.

## Scope

This is a fork of [mazdak/AudioWhisper](https://github.com/mazdak/AudioWhisper)
that has diverged: cloud transcription providers were removed and it is
local-only. Report issues in **this** repository's code here. Issues in
upstream's code — including the cloud providers this fork does not ship — belong
upstream.

Prebuilt binaries and the Homebrew cask are published by **upstream**, not by
this fork. This repository publishes no releases. A vulnerability in a
downloaded `.app` is almost certainly not this code.

## What raises the stakes here

These are documented design decisions, not oversights. Understanding them helps
target a report:

- **The app is not sandboxed** ([ADR 0001](docs/adr/0001-no-sandbox.md)).
  Push-to-talk needs `CGEventTap`, Smart Paste posts synthetic `⌘V` via
  `CGEvent.postToPid`, and prompt overrides read the filesystem directly — none
  of which the App Sandbox permits. It ships Developer ID–signed, notarized,
  with hardened runtime and three entitlements (audio input, network client,
  Apple events).
- **It requests Accessibility permission**, which grants synthetic event
  injection. That is the highest-value capability the app holds.
- **It executes downloaded model weights** and runs an **embedded Python
  runtime** bootstrapped with a bundled `uv`
  ([ADR 0002](docs/adr/0002-embedded-uv-python.md)). The `uv` binary is verified
  at runtime against a SHA-256 stamped at build time.
- **Model integrity is only partly enforced**
  ([ADR 0006](docs/adr/0006-model-integrity.md)). This is a **known gap**, not a
  finding: `ModelIntegrity.knownHashes` is empty, so app-shipped models fall
  through to trust-on-first-use rather than the documented hard-fail. The ADR's
  *Implementation status* section states this. A report that pinned hashes are
  unenforced is already tracked; a report of a way to *bypass* verification that
  is supposed to work is not.

## Particularly interesting areas

- Subprocess invocation and argument handling (`MLXModelManager+Downloads`,
  `UvBootstrap`, `MLDaemonManager`) — everything uses `executableURL` plus an
  arguments array with no shell, and untrusted values such as model repo names
  are passed as `argv[n]` rather than interpolated. A way around that is worth
  reporting.
- The subprocess environment allowlist (`MLDaemonManager.daemonEnvironment()`),
  which exists so tokens and proxy credentials are not inherited.
- Path handling for model caches and prompt overrides under
  `~/Library/Application Support/AudioWhisper/`.
- Anything that causes transcript text or audio to leave the machine.
  Transcription is local-only by design and there is no HTTP client in the Swift
  sources; a network call carrying user content would be a serious bug.

## Out of scope

- Vulnerabilities in upstream's builds or the Homebrew cask.
- Consequences of the app being unsandboxed that follow directly from ADR 0001.
- Findings that require an attacker who already has code execution as the user,
  where the app is incidental. Trust-on-first-use model verification explicitly
  does not defend against that; the code says so.
- Reports from automated scanners with no demonstrated exploit path.
