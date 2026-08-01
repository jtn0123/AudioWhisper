#!/usr/bin/env bash
# SwiftLint wrapper that guarantees a usable toolchain.
#
# SwiftLint loads sourcekitd, which lives in Xcode — not in Command Line Tools.
# With xcode-select pointing at CLT it dies with:
#
#   SourceKittenFramework/library_wrapper.swift:58: Fatal error: Loading
#   sourcekitdInProc.framework/Versions/A/sourcekitdInProc failed
#
# Same root cause as the actool failure in lib/xcode-env.sh, same fix.
# Used by .pre-commit-config.yaml so committing works on a CLT-only machine.
#
# Usage: scripts/lint.sh [--strict] [paths...]
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# shellcheck source=scripts/lib/xcode-env.sh
. "scripts/lib/xcode-env.sh"
ensure_xcode_toolchain || exit 1

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint not installed — skipping (brew install swiftlint)" >&2
  exit 0
fi

# Warn when the local version differs from the one CI pins.
#
# Results are genuinely version-dependent: the analyzer's unused_declaration
# heuristics changed between 0.63.2 and 0.65.0, and the same tree reports 144
# findings on one and 46 on the other. A silent mismatch means passing locally
# and failing in CI, or the reverse — with no hint why. Sourced from ci.yml so
# there is one place to change.
expected=$(sed -n 's/^  SWIFTLINT_VERSION: "\(.*\)"/\1/p' .github/workflows/ci.yml | head -n 1)
actual=$(swiftlint version 2>/dev/null)
if [ -n "$expected" ] && [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
  echo "warning: swiftlint $actual locally, CI pins $expected — results may differ." >&2
  echo "         brew upgrade swiftlint  (or install $expected) to match." >&2
fi

exec swiftlint lint "$@"
