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

exec swiftlint lint "$@"
