# Offscreen Models behavioral-test feasibility probe

This is a preserved experiment, **not a passing test in the regression suite**.
Production code and the existing tests remain unchanged. Its source was
compiled temporarily in `Tests/`, then archived here with the failed result.

- Source under test: `b64f707` (app sources identical to `224473e` / `a9a0fed`).
- Host: macOS 27.2; local XCTest with `GITHUB_ACTIONS=true`. This flag does not
  turn a local desktop into a hosted runner.
- Pattern: unordered borderless NSWindow / NSHostingView, matching the existing
  `Tests/Views/ViewBodyRenderingTests.swift` layout helper. No shortcut name or
  interactive root workspace was mounted.
- Services: injected fake setup/capture/install/consent operations. AppDefaults
  used a process-isolated `AUDIOWHISPER_DEFAULTS_SUITE`. Session construction
  still permits the existing read-only shared model-cache scan; no real model
  installation, inference, permission request, clipboard write or recording ran.
- Required assertion: find and press the real Models **Finish setup** button,
  then verify that it routes to setup without requesting consent or recording.
- **Result: failed feasibility.** The host exposed only `AXGroup` with an empty
  accessibility-children array. The required named button was unavailable.
  The probe explicitly failed instead of treating a missing tree as success.
  Initial and diagnostic reruns all failed that assertion; no passing behavior
  result or hosted-runner compatibility is claimed.

[Full probe](RebuildModelsHeadlessProbeTests.swift) · [Selected output](result.log).
Reproduce by copying the probe into `Tests/` and running:

```sh
. scripts/lib/xcode-env.sh
ensure_xcode_toolchain
AUDIOWHISPER_DEFAULTS_SUITE=com.audiowhisper.tests.headless-probe \
  OS_ACTIVITY_MODE=disable GITHUB_ACTIONS=true \
  swift test -Xswiftc -DTESTING --filter RebuildModelsHeadlessProbeTests
```

Existing hosted body/layout tests do pass, but that does not establish native
AX control materialization for this page. The interactive workspace fixture
remains guarded after its prior hosted signal-6 abort. A reliable semantic
harness still needs isolation and validation before it can close D3. No gate,
coverage exclusions, existing test skips or assertion requirements were relaxed.
