#!/usr/bin/env bash
# mypy wrapper for the bundled Python (Sources/ml, ml_daemon, verify_*).
#
# Configuration lives in mypy.ini, which selects the files and turns on strict
# mode. Needs no Xcode and no venv: the ML libraries are exempted per-module in
# mypy.ini precisely so this runs against a bare checkout.
#
# Usage: scripts/typecheck.sh [extra mypy args...]
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if ! command -v mypy >/dev/null 2>&1; then
  echo "mypy not installed — skipping (pip install mypy==$(sed -n 's/^  MYPY_VERSION: "\(.*\)"/\1/p' .github/workflows/ci.yml | head -n 1))" >&2
  exit 0
fi

# Warn on drift from the version CI pins, same reasoning as scripts/lint.sh:
# mypy adds checks in minor releases, so a newer local copy can report errors CI
# never sees, and an older one can miss errors CI fails on.
expected=$(sed -n 's/^  MYPY_VERSION: "\(.*\)"/\1/p' .github/workflows/ci.yml | head -n 1)
actual=$(mypy --version 2>/dev/null | awk '{print $2}')
if [ -n "$expected" ] && [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
  echo "warning: mypy $actual locally, CI pins $expected — results may differ." >&2
  echo "         pip install 'mypy==$expected' to match." >&2
fi

exec mypy "$@"
