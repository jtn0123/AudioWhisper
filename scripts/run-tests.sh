#!/usr/bin/env bash
set -uo pipefail
# Run the AudioWhisper test suite with macOS framework noise filtered out.
#
# Runs in PARALLEL by default.
#
# D4: this used to be forced sequential because tests wrote UserDefaults.standard
# directly while production read the same global domain, so parallel xctest
# processes raced the same keys (2-4 nondeterministic failures every run).
#
# Fixed by making AppDefaults.defaults redirectable: AUDIOWHISPER_DEFAULTS_SUITE
# below points it at a scratch suite, and AppDefaults appends the PROCESS ID, so
# each of the xctest processes --parallel spawns gets its own settings store.
# That required routing every settings access — production and test — through
# AppDefaults; production no longer touches .standard at all.
#
# Usage:
#   scripts/run-tests.sh                 # parallel (default)
#   scripts/run-tests.sh --no-parallel   # sequential
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n 's/^# //p' "$0" | head -n 20
  exit 0
fi

# Change to repo root (parent of scripts/)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Suppress macOS system framework noise (Contacts, CoreData XPC, FrontBoardServices)
# These errors occur because xctest runs outside the app sandbox
export OS_ACTIVITY_MODE=disable

# Per-invocation scratch settings domain; AppDefaults appends ".<pid>".
SUITE_PREFIX="com.audiowhisper.tests.$$"
export AUDIOWHISPER_DEFAULTS_SUITE="$SUITE_PREFIX"

# Sweep scratch preference domains.
#
# These are cfprefsd-backed, and cfprefsd flushes them to disk ASYNCHRONOUSLY —
# well after this script exits. Cleaning up only in an EXIT trap therefore does
# not work: an earlier version of this script leaked 4,335 plists (17 MB) that
# way, because `rm` raced the daemon and lost.
#
# So the primary sweep runs at STARTUP, clearing anything left by previous runs.
# By then cfprefsd has long since finished writing, and `defaults delete` (which
# drops the in-memory domain) followed by `rm` is durable. A best-effort EXIT
# sweep still runs, so a single interactive run usually leaves nothing behind;
# worst case the leak is bounded to one run and the next run reclaims it.
sweep_scratch_domains() {
  local prefs="$HOME/Library/Preferences"
  shopt -s nullglob
  local plist base
  for plist in "$prefs"/com.audiowhisper.tests.*.plist; do
    base=$(basename "$plist" .plist)
    defaults delete "$base" >/dev/null 2>&1 || true
    rm -f "$plist" 2>/dev/null || true
  done
  shopt -u nullglob
}

sweep_scratch_domains                       # reclaim anything from earlier runs
trap 'sleep 1; sweep_scratch_domains' EXIT  # best effort for this run

PARALLEL_FLAG="--parallel"
for arg in "$@"; do
  if [[ "$arg" == "--no-parallel" ]]; then
    PARALLEL_FLAG="--no-parallel"
  fi
done

# The pipeline below must not swallow swift test's exit status. Piping into grep
# makes $? grep's, so a failing suite reported success — the same class of bug as
# the print() CI gate (plan item 8). Capture PIPESTATUS explicitly.
set -o pipefail
# NOTE: --parallel and --no-parallel report DIFFERENTLY. Sequential prints
# "Test Case ... passed" / "Executed N tests"; parallel prints a "[N/M] Testing"
# progress counter and a swift-testing summary. The filter must pass both, or a
# parallel run looks like it executed nothing.
swift test $PARALLEL_FLAG -Xswiftc -DTESTING 2>&1 \
  | grep -v -E "(CNAccountCollection|ContactsPersistence|com\.apple\.contacts|NSXPCConnection|DetachedSignatures|FrontBoardServices|NSStatusItemScene|BSBlockSentinel)" \
  | grep -E "(Test Suite|Test Case|passed|failed|error:|Executed|skipped|^\[[0-9]+/[0-9]+\]|Test run)"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  echo "swift test failed (exit $status)"
fi
exit "$status"
