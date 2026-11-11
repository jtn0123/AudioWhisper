#!/usr/bin/env bash
# CI gate: the packaged AudioWhisper.app (from `make build`) is complete, signed,
# and its read-only recording diagnostics run and report this commit.
# Usage: scripts/ci/smoke-bundle.sh <full commit sha the app was built from>
# Run from the repo root. Called by .github/workflows/ci.yml and scripts/ci-local.sh.
set -euo pipefail
export EXPECTED_BUILD="${1:?Usage: scripts/ci/smoke-bundle.sh <commit sha>}"

APP="AudioWhisper.app"
test -d "$APP" || { echo "::error::Missing $APP"; exit 1; }
test -x "$APP/Contents/MacOS/AudioWhisper" || { echo "::error::Missing executable"; exit 1; }
test -f "$APP/Contents/Info.plist" || { echo "::error::Missing Info.plist"; exit 1; }
plutil -lint "$APP/Contents/Info.plist"
# A linker-only signature leaves the bundle unidentified to TCC.
# Local previews also need a complete, verified bundle signature.
codesign --verify --strict --verbose "$APP"
# Captured, not piped into `grep -q`: grep exits at its first match, codesign
# then dies writing to the closed pipe, and pipefail reports a failure.
requirement=$(codesign -d -r- "$APP" 2>&1)
grep -q 'designated =>' <<< "$requirement"
details=$(codesign -dv "$APP" 2>&1)
grep -q '^Identifier=com.audiowhisper.rebuild$' <<< "$details"
# Confirm Python bootstrap binary made it into the bundle
test -f "$APP/Contents/Resources/bin/uv" -o -f "$APP/Contents/Resources/uv" \
  || echo "::warning::uv binary not found in bundled Resources (may be missing for dev builds)"
# The Python entry points the app launches, and the package they all
# import. A missing one is not a build error — it surfaces at runtime
# as a model that can never be downloaded, verified, or loaded.
for py in ml_daemon.py download_model.py verify_parakeet.py verify_mlx.py ml/hub.py ml/rpc.py; do
  test -f "$APP/Contents/Resources/$py" || { echo "::error::Missing bundled Resources/$py"; exit 1; }
done
# Opening Preferences creates the shortcut recorder, which resolves
# its localized text through Bundle.module. Missing resources trap at
# runtime even when the executable and headless tests pass.
for bundle in AudioWhisper_AudioWhisper KeyboardShortcuts_KeyboardShortcuts; do
  test -d "$APP/Contents/Resources/$bundle.bundle" \
    || { echo "::error::Missing SwiftPM resource bundle $bundle"; exit 1; }
done
# SwiftPM versions package macOS resources in either a flat bundle
# or Contents/Resources. Validate runtime resolution through Foundation.
xcrun swift -e 'import Foundation; let path = "AudioWhisper.app/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle"; guard let bundle = Bundle(path: path), let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"), FileManager.default.fileExists(atPath: url.path) else { fatalError("Missing shortcut editor localization") }'
# Confirm version was stamped (not left as a placeholder)
if grep -q "VERSION_PLACEHOLDER\|BUILD_PLACEHOLDER" "$APP/Contents/MacOS/AudioWhisper" 2>/dev/null; then
  echo "::warning::Version placeholders found unsubstituted in binary"
fi
echo "App bundle smoke test passed."

python3 - <<'PY'
import json, os, subprocess
result = subprocess.run(
    ["AudioWhisper.app/Contents/MacOS/AudioWhisper", "--diagnose-recording"],
    capture_output=True, text=True, timeout=30, check=True,
)
report = json.loads(result.stdout)
assert report["bundleIdentifier"] == "com.audiowhisper.rebuild", report
assert report["build"] == os.environ["EXPECTED_BUILD"], report
assert report["launchContext"] == "commandLine", report
assert report["nextStep"], report
if report["microphonePermission"] != "granted":
    assert not report["readyToRecord"], report
print("Packaged recording diagnostics exited cleanly and reported valid setup state")
PY
