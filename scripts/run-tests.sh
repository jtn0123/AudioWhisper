#!/usr/bin/env bash
set -euo pipefail
# Run the AudioWhisper test suite with macOS framework noise filtered out.
# Runs sequentially by default to match CI: some tests still read/write
# UserDefaults.standard directly and fail nondeterministically under
# --parallel. Tests that touch UserDefaults.standard should subclass
# IsolatedXCTestCase (Tests/Utilities/IsolatedXCTestCase.swift); once that
# migration enforces strict isolation, parallel can become the default.
# Pass --parallel to opt in anyway.
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n 's/^# //p' "$0" | head -n 20
  exit 0
fi

# Change to repo root (parent of scripts/)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Suppress macOS system framework noise (Contacts, CoreData XPC, FrontBoardServices)
# These errors occur because xctest runs outside the app sandbox
export OS_ACTIVITY_MODE=disable

# Run sequentially by default (matches CI). Pass --parallel as a script arg
# to opt into parallel execution (currently nondeterministic — see above).
PARALLEL_FLAG="--no-parallel"
for arg in "$@"; do
  if [[ "$arg" == "--parallel" ]]; then
    PARALLEL_FLAG="--parallel"
  fi
done

swift test $PARALLEL_FLAG -Xswiftc -DTESTING 2>&1 | grep -v -E "(CNAccountCollection|ContactsPersistence|com\.apple\.contacts|NSXPCConnection|DetachedSignatures|FrontBoardServices|NSStatusItemScene|BSBlockSentinel)" | grep -E "(Test Suite|Test Case|passed|failed|error:|Executed|skipped)"