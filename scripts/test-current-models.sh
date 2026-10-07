#!/usr/bin/env bash
# Actual offered-model inference; no microphone, UI automation or TCC changes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/xcode-env.sh
ensure_xcode_toolchain
test "$(uname -m)" = arm64 || { echo "Apple Silicon required" >&2; exit 1; }
test "$(sysctl -n hw.memsize)" -ge 34359738368 || { echo "32 GB unified memory required" >&2; exit 1; }
echo "Exact source: $(git rev-parse HEAD)"
git diff --quiet && git diff --cached --quiet || { echo "Commit source before recording exact-head evidence" >&2; exit 1; }
sw_vers
RUN_E2E=1 RUN_CURRENT_MODELS=1 OS_ACTIVITY_MODE=disable \
    swift test --no-parallel -Xswiftc -DTESTING \
    --filter 'ParakeetEndToEndTests|CurrentWritingModelFixtureTests|LocalEngineFixtureTests'
