# Contributing to AudioWhisper Rebuild

This is the local-only fork at `jtn0123/AudioWhisper`. Target this repository explicitly when using `gh`; its default branch is `master` and the rebuild work is on `rebuild/native-v2`. Upstream releases and its Homebrew tap are different products.

## Tooling

Use a full Xcode 26+ installation with Swift 6.2+ tooling, Git and Python 3.11+ for development utilities. KeyboardShortcuts 3.x requires that toolchain even though this package retains Swift 5 language mode. Native app testing targets macOS 26/27; older-OS acceptance is outside the current scope.

The shell build/test scripts source `scripts/lib/xcode-env.sh` to recover from Command Line Tools being selected. For direct Swift or SwiftLint commands:

```sh
. scripts/lib/xcode-env.sh
ensure_xcode_toolchain
```

## Build and launch

```sh
git clone https://github.com/jtn0123/AudioWhisper.git
cd AudioWhisper
make run
```

`make run` builds the resource-complete debug bundle, reuses the persistent local signing certificate, validates a staged copy, stops the exact installed rebuild, replaces it and relaunches. It retains the previous signed build for rollback and rejects signing-identity changes. Do not overwrite the running app with `ditto` or run the unbundled Swift executable for native permission testing.

```sh
make build-dev              # signed host debug package only
make build                  # universal release package
swift build                 # compilation check after toolchain setup
make test
make typecheck
```

The local certificate remains in the user Keychain. It is development signing, not Developer ID or notarization. Microphone/Accessibility consent should persist across builds using the same complete signature; repeated permission prompts are a bug to investigate, not a normal development loop. Never reset TCC as part of a routine build.

## App setup

**Models & setup** handles microphone consent, local runtime preparation and voice-model install/verify/remove. Parakeet v2 is the English choice; v3 remains available. Whisper uses CoreML.

**Writing cleanup** handles optional local editing. Qwen3.5 9B 4-bit is the new-install recommendation and Qwen3.8 27B mixed 3-bit is optional. Existing explicit model choices survive upgrades. Cleanup has one grammar policy for every app; app mappings, editable profiles and profile prompt overrides have been removed. Compare/Use original lets users recover their words.

Initial preparation downloads Python, locked packages and model weights. Prepared transcription and correction run offline. The app does not upload audio or transcripts and has no cloud provider/API-key setup.

## Tests and checks

```sh
swift test --parallel
swift test --filter RebuildDeliveryIntegrationTests
swift test --parallel --enable-code-coverage
make typecheck
swiftlint lint --strict
```

Use `IsolatedXCTestCase` and scratch defaults for preference-dependent tests. Create explicit in-memory or disposable on-disk SwiftData containers; never initialize the live history store in tests. Tie regressions to the changed recording/setup/delivery behavior. Optional real-engine tests need installed models and `RUN_E2E=1`; discovered case counts do not mean every hardware test executed.

Python tests use a lightweight test environment with `tqdm==4.67.1`; model libraries are faked unless a test explicitly says otherwise:

```sh
python3 -m venv .mypy-venv
.mypy-venv/bin/pip install mypy==1.20.0 tqdm==4.67.1
.mypy-venv/bin/python -m unittest discover -s Tests -p 'test_*.py'
```

Match the `MYPY_VERSION` and `SWIFTLINT_VERSION` pins in `.github/workflows/ci.yml` for exact CI comparisons. CI validates the frozen Python lock, runs Swift/Python tests, measures project-source coverage, packages the app and runs one analyzer pass. Failed indexing or malformed/missing reports must fail analysis. Keep stderr/report artifacts when investigating failures.

For native recording, focus, paste, window and consent testing, use the disposable macOS 26 guest in [the VM guide](scripts/vm/README.md). Guest virtual input/audio is separate from physical host acceptance. Reuse the signer and existing permissions; do not require repeated user interaction for the automated loop.

## Architecture

- `Sources/Rebuild/`: active workspace, session ownership, setup and writing-install state.
- `Sources/Services/`: transcription pipeline, speech routing, output guards and model services.
- `Sources/Managers/`: local ML daemon, model/setup/permission orchestration.
- `Sources/Stores/`: SwiftData history, background export, preferences and usage.
- `Sources/ml/`: local Python inference, pinned cache access and JSON-RPC.
- `Sources/Resources/`: frozen `pyproject.toml`/`uv.lock` and packaged tools.

The executable launches `RebuildApp`. Legacy views/controllers still compile for historical regression coverage; do not add new product flows there. Shared engines remain reusable. See [ADRs](docs/adr/) for offline/cache/security boundaries.

## Dependency changes

For Python updates, modify `Sources/Resources/pyproject.toml`, regenerate the frozen lock with `uv lock`, and review the exact package diff. Preserve unrelated ML pins. Verify offline Parakeet and both shipped Qwen models before installing a new runtime. Model revisions are pinned in `ModelPins`; representative-file integrity records detect corruption but are not full weight authentication.

The bundled uv version/checksums are defined in `scripts/prepare-uv.sh`; update them together from the official release and rebuild. Never retain signing keys, credentials or transcript data in the repository.

## Distribution

This fork publishes no releases or Homebrew tap. A local development bundle is not a distributable release. Public distribution requires Developer ID signing, accepted notarization, stapling and Gatekeeper assessment. Do not publish upstream’s tap or an ad-hoc development package.

## Contributions

Use focused commits, meaningful regression evidence and a short PR description explaining the resulting behavior. Run the checks appropriate to the change. Preserve unverified native scenarios explicitly; a green unit-test job is not physical microphone acceptance.

```sh
gh pr create --repo jtn0123/AudioWhisper --base master
```

An optional staged-file hook is available through `git config core.hooksPath .githooks`. Use clear Swift/Python names, conservative error handling and scoped changes. New dependencies and broader architecture changes need concrete justification.
