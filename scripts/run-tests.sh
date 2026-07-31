#!/usr/bin/env bash
set -uo pipefail
# Run the AudioWhisper test suite with macOS framework noise filtered out.
#
# Runs sequentially by default to match CI. Some tests write UserDefaults.standard
# directly in setUp and then assert on production code that reads the same global
# domain, so under --parallel two xctest processes race the same keys. Reproduced
# consistently: --parallel yields 2-4 nondeterministic failures per run, always in
# AppDefaultsTests, PasteManagerTests, AppDelegateHotkeysTests,
# HotkeyIntegrationTests, RecordingViewModelPasteCoverageTests, and
# AppSetupHelperCoverageTests — exactly the classes that set
# `enforcesStandardUserDefaultsIsolation = false`.
#
# Fixing this properly means migrating every test that touches
# UserDefaults.standard (48 files) onto a scoped suite; redirecting only the six
# offenders makes it worse, because the other 42 write .standard and expect
# production to read it back. See .claude/fix-plan.md item 17.
#
# Usage:
#   scripts/run-tests.sh              # sequential (default, reliable)
#   scripts/run-tests.sh --parallel   # faster, currently flaky — see above
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n 's/^# //p' "$0" | head -n 20
  exit 0
fi

# Change to repo root (parent of scripts/)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Suppress macOS system framework noise (Contacts, CoreData XPC, FrontBoardServices)
# These errors occur because xctest runs outside the app sandbox
export OS_ACTIVITY_MODE=disable

PARALLEL_FLAG="--no-parallel"
for arg in "$@"; do
  if [[ "$arg" == "--parallel" ]]; then
    PARALLEL_FLAG="--parallel"
  fi
done

# The pipeline below must not swallow swift test's exit status. Piping into grep
# makes $? grep's, so a failing suite reported success — the same class of bug as
# the print() CI gate (plan item 8). Capture PIPESTATUS explicitly.
set -o pipefail
swift test $PARALLEL_FLAG -Xswiftc -DTESTING 2>&1 \
  | grep -v -E "(CNAccountCollection|ContactsPersistence|com\.apple\.contacts|NSXPCConnection|DetachedSignatures|FrontBoardServices|NSStatusItemScene|BSBlockSentinel)" \
  | grep -E "(Test Suite|Test Case|passed|failed|error:|Executed|skipped)"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  echo "swift test failed (exit $status)"
fi
exit "$status"
