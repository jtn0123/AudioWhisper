# AudioWhisper Test Suite

About 2,800 XCTest cases plus two Python test files. Everything runs offline
on a stock checkout except the opt-in end-to-end test (see below).

## Running

```bash
make test                                        # whole suite, parallel (preferred)
scripts/run-tests.sh --no-parallel               # sequential
swift test --filter "DataManagerTests"           # one class
swift test --filter "DataManagerTests/testSaveAndLoadHistory"   # one test

python3 Tests/test_correction_sanitize.py        # Python: correction output sanitising
python3 Tests/test_hub.py                        # Python: pinned downloads, offline loads
```

Prefer `make test` over bare `swift test`. It recovers when `xcode-select`
points at Command Line Tools (the asset catalog needs Xcode's `actool`; see
CLAUDE.md), filters macOS framework noise, and gives each run its own settings
domain.

## Settings isolation (why `--parallel` is safe)

Production and test code reach settings only through `AppDefaults`, never
`UserDefaults.standard`. `scripts/run-tests.sh` points `AppDefaults` at a
scratch suite (`AUDIOWHISPER_DEFAULTS_SUITE`), and `AppDefaults` appends the
process ID. So each xctest process that `--parallel` spawns has its own settings
store, and the scratch domains are swept afterwards.

`Tests/Utilities/IsolatedXCTestCase.swift` is the safety net. Tests that run
settings-touching business logic subclass it, and it reports any test that
still mutates `.standard`. Control it with `AUDIOWHISPER_TEST_ISOLATION`:

| Value | Effect |
|---|---|
| `warn` (default) | log `[IsolatedXCTestCase] WARNING:` and continue |
| `strict` | `XCTFail` and roll `.standard` back |
| `off` | silent |

A new test that needs settings should use a UUID-scoped suite rather than
`.standard`:

```swift
final class MyServiceTests: IsolatedXCTestCase {
    func testReadsInjectedDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("expected", forKey: "myKey")
        XCTAssertEqual(MyService(defaults: defaults).read(), "expected")
    }
}
```

## Layout

Most test files sit at the top level, named after the type they cover
(`DataManagerTests.swift`, `MLXModelManagerTests.swift`, …). Larger classes
split into extensions: `PressAndHoldKeyMonitorTests+ThreadSafety.swift`.
`*CoverageTests.swift` files fill branch coverage for a type whose main test
file covers behaviour.

| Directory | Contents |
|---|---|
| `AppDelegate/` | the app delegate's extensions: hotkeys, lifecycle, menu, notifications, recording window |
| `Integration/` | multi-component flows, plus the opt-in `ParakeetEndToEndTests` |
| `Mocks/` | test doubles for audio, model managers, data, speech-to-text, uv, windows |
| `Views/`, `Waveform/`, `Design/` | SwiftUI view logic and layout |
| `Stores/`, `Models/`, `ViewModels/`, `Utilities/` | as named |
| `Resources/` | `speech_sample.wav` (a spoken sentence, for the end-to-end test) and `test_audio.wav` (a 0.1 s tone, for audio decoding) |
| `__Snapshots__/` | UI snapshot baselines (local-only; see below) |

## The Swift ↔ Python contract

`MLRPCContractTests` runs the real `Sources/ml_daemon.py` and checks it against
the production Swift encoder and decoder. That is the only thing tying the two
sides of the JSON-RPC wire format together. It needs no venv and no models:
every ML import in `Sources/ml` is lazy, so the daemon boots on stock `python3`.
See CLAUDE.md, "The Swift ↔ Python RPC contract".

The Python files run in CI's "Python unit tests" step, and their coverage is
uploaded to SonarCloud. `Sources/ml` is also type-checked with `make typecheck`
(mypy `--strict`).

## Snapshot tests (local only)

```bash
SNAPSHOT_TESTS=1  swift test --no-parallel -Xswiftc -DTESTING --filter UISnapshotTests   # check
SNAPSHOT_RECORD=1 swift test --no-parallel -Xswiftc -DTESTING --filter UISnapshotTests   # re-record
```

They are skipped unless opted in, and never run in CI: a GitHub runner has no
usable WindowServer, so its renders are placeholders. CLAUDE.md lists the rules
for adding one (`ScrollableContent` instead of `ScrollView`, pinned dates).

## End-to-end (opt-in, nightly)

```bash
RUN_E2E=1 swift test --filter ParakeetEndToEndTests
```

This is the only test of the real transcription path: it builds the uv
environment, downloads the pinned Parakeet model (~2.5 GB on first run), starts
the daemon, transcribes `Resources/speech_sample.wav`, and checks the words. Without `RUN_E2E=1` it
skips, so per-PR CI stays fast. `.github/workflows/nightly.yml` runs it on a
schedule and on `workflow_dispatch`. Treat a failure there as a broken app.

## Tooling that runs over the tests in CI

- **SwiftLint** (`scripts/lint.sh`), plus `swiftlint analyze`, which gates on
  unused imports and ratchets unused declarations.
- **ThreadSanitizer** is not in CI. For concurrency work, run the relevant
  tests with `swift test --sanitize=thread --filter <Class>`; it found a data
  race in `PressAndHoldKeyMonitor` that the tests themselves passed over.
