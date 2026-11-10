#!/usr/bin/env bash
# Runs CI's macOS jobs on this Mac, for when GitHub's hosted macOS runners are
# short (jobs cancelled with "not acquired by Runner"). Same gates, same order:
#
#   lint     SwiftLint --strict (pinned version), no print(), uv.lock in sync,
#            mypy --strict, the Python unit tests
#   test     the Rust core, swift build, swift test --parallel with coverage,
#            the coverage ratchet
#   bundle   make build, then scripts/ci/smoke-bundle.sh
#   analyze  xcodebuild build-for-testing, then the SwiftLint analyzer ratchet
#
# It tests a COMMIT, not your working tree: the commit is checked out in its own
# worktree under ~/Library/Caches/AudioWhisper-ci (kept between runs, so builds
# are incremental), and your checkout is never touched.
#
# Gentle on the machine: one job at a time, at low CPU priority (nice), with
# compilers and test workers capped at CI_LOCAL_CORES (default 4). Each job
# first waits until at least CI_LOCAL_MIN_FREE percent of memory is free
# (default 25). Peak use is about 4-6 GB, mostly the Swift compiler.
#
# --post reports each job to GitHub as a commit status, "local-ci/<job>", so a
# pull request shows the local result beside (not instead of) the hosted one.
#
# Usage: scripts/ci-local.sh [--post] [--jobs lint,test,bundle,analyze] [commit-ish]
#   scripts/ci-local.sh                      # all jobs on HEAD
#   scripts/ci-local.sh --post origin/my-pr  # a pushed branch, reported to GitHub
# Logs: ~/Library/Logs/AudioWhisper-ci/<sha>/<job>.log
set -uo pipefail

# Low CPU priority for everything below, compilers and tests included.
if [ -z "${CI_LOCAL_NICED:-}" ]; then CI_LOCAL_NICED=1 exec nice -n 10 "$0" "$@"; fi

REPO_SLUG="jtn0123/AudioWhisper"
CORES="${CI_LOCAL_CORES:-4}"
MIN_FREE="${CI_LOCAL_MIN_FREE:-25}"
JOBS="lint,test,bundle,analyze"
POST=false
REF="HEAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --post) POST=true ;;
    --jobs) JOBS="${2:?--jobs needs a list}"; shift ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
    *) REF="$1" ;;
  esac
  shift
done

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHA=$(git -C "$SOURCE" rev-parse --verify "$REF^{commit}") || { echo "Unknown commit: $REF" >&2; exit 2; }
CACHE="$HOME/Library/Caches/AudioWhisper-ci"
WORK="$CACHE/worktree"
LOGS="$HOME/Library/Logs/AudioWhisper-ci/$SHA"
mkdir -p "$CACHE" "$LOGS"

# The gates in scripts/ci, from the commit under test when it has them, else
# from this checkout (a branch cut before they were extracted).
gate() {
  local name="$1"; shift
  if [ -x "scripts/ci/$name" ]; then "scripts/ci/$name" "$@"; else "$SOURCE/scripts/ci/$name" "$@"; fi
}

ci_value() { sed -n "s/^  $1: \"\(.*\)\"/\1/p" "$WORK/.github/workflows/ci.yml" | head -n 1; }

# --- the worktree ------------------------------------------------------------
if [ ! -e "$WORK/.git" ]; then
  git -C "$SOURCE" worktree add --detach "$WORK" "$SHA" >/dev/null || exit 1
fi
git -C "$WORK" checkout --quiet --detach --force "$SHA" || exit 1
# Remove everything untracked except the build caches, so a stale file from an
# earlier commit cannot make this one pass.
git -C "$WORK" clean -ffdxq -e .build -e .mypy-venv -e .analyzer-cache
git -C "$WORK" submodule update --init --recursive --quiet || exit 1
cd "$WORK" || exit 1

# The pinned SwiftLint, cached by version (a different local version reports a
# different analyzer count, which the ratchet compares against).
SWIFTLINT_VERSION=$(ci_value SWIFTLINT_VERSION)
SWIFTLINT_DIR="$CACHE/swiftlint-$SWIFTLINT_VERSION"
if [ ! -x "$SWIFTLINT_DIR/swiftlint" ]; then
  if ! curl -sSfL --retry 3 -o "$CACHE/swiftlint.zip" \
      "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip" \
      || ! unzip -q -o "$CACHE/swiftlint.zip" -d "$SWIFTLINT_DIR"; then
    echo "Could not download SwiftLint $SWIFTLINT_VERSION" >&2; exit 1
  fi
  rm -f "$CACHE/swiftlint.zip"
fi
export PATH="$SWIFTLINT_DIR:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
export OS_ACTIVITY_MODE=disable
# shellcheck source=scripts/lib/xcode-env.sh
. scripts/lib/xcode-env.sh
ensure_xcode_toolchain || exit 1

# --- helpers -----------------------------------------------------------------
post_status() { # state job description
  [ "$POST" = true ] || return 0
  gh api --silent "repos/$REPO_SLUG/statuses/$SHA" -f state="$1" -f context="local-ci/$2" \
    -f description="$3" >/dev/null 2>&1 || echo "  (could not post the $2 status to GitHub)" >&2
}

free_percent() { memory_pressure -Q 2>/dev/null | sed -n 's/.*free percentage: \([0-9]*\)%.*/\1/p'; }

wait_for_memory() {
  local free
  while free=$(free_percent) && [ -n "$free" ] && [ "$free" -lt "$MIN_FREE" ]; do
    echo "  waiting: $free% of memory free, want $MIN_FREE%"
    sleep 30
  done
}

generate_version_info() {
  local version hash
  version=$(tr -d '[:space:]' < VERSION 2>/dev/null || echo "0.0.0")
  hash=$(git rev-parse --short HEAD)
  sed -e "s/BUNDLED_UV_VERSION_PLACEHOLDER//g" -e "s/BUNDLED_UV_SHA256_PLACEHOLDER//g" \
      -e "s/VERSION_PLACEHOLDER/$version/g" -e "s/GIT_HASH_PLACEHOLDER/$hash/g" \
      Sources/VersionInfo.swift.template > Sources/Utilities/VersionInfo.swift
}

# --- the jobs (each mirrors the ci.yml job of the same name) ------------------
job_lint() {
  swiftlint --strict --quiet &&
  gate no-print.sh &&
  (cd Sources/Resources && uv lock --check) &&
  { [ -x .mypy-venv/bin/python ] || python3 -m venv .mypy-venv; } &&
  .mypy-venv/bin/pip install --quiet --disable-pip-version-check \
    "mypy==$(ci_value MYPY_VERSION)" "coverage==$(ci_value COVERAGE_VERSION)" "tqdm==4.67.1" &&
  .mypy-venv/bin/mypy &&
  .mypy-venv/bin/python -m unittest discover -s Tests -p 'test_*.py' &&
  python3 -m unittest scripts/test_unattended_acceptance.py
}

job_test() {
  generate_version_info &&
  scripts/build-core.sh &&
  swift build -j "$CORES" &&
  swift test -j "$CORES" --parallel --num-workers "$CORES" --enable-code-coverage &&
  python3 scripts/coverage-gate.py "$(swift test --show-codecov-path)" "$PWD" \
    "$(sed -n 's/.*coverage-gate.py "\$COV_JSON" "\$PWD" \([0-9.]*\).*/\1/p' .github/workflows/ci.yml)"
}

job_bundle() {
  rm -rf AudioWhisper.app &&
  AUDIOWHISPER_BUILD_JOBS="$CORES" make build &&
  gate smoke-bundle.sh "$SHA"
}

job_analyze() {
  generate_version_info &&
  scripts/build-core.sh &&
  xcodebuild -scheme AudioWhisper -destination 'platform=macOS' -jobs "$CORES" \
    build-for-testing > xcodebuild.log 2>&1 &&
  python3 scripts/analyze-gate.py xcodebuild.log --baseline \
    "$(sed -n 's/.*analyze-gate.py xcodebuild.log --baseline \([0-9]*\) --benchmark.*/\1/p' .github/workflows/ci.yml)"
}

# --- run ---------------------------------------------------------------------
echo "Local CI for ${SHA:0:12} ($(git log -1 --format=%s "$SHA"))"
echo "Logs: $LOGS"
IFS=',' read -r -a SELECTED <<< "$JOBS"
for job in "${SELECTED[@]}"; do post_status pending "$job" "Queued on a local Mac"; done

failed=0
for job in "${SELECTED[@]}"; do
  if ! declare -F "job_$job" >/dev/null; then echo "Unknown job: $job" >&2; failed=1; continue; fi
  wait_for_memory
  post_status pending "$job" "Running on a local Mac"
  started=$(date +%s)
  printf '%s  %-8s ' "$(date +%H:%M)" "$job"
  if ( "job_$job" ) > "$LOGS/$job.log" 2>&1 < /dev/null; then
    took=$(( $(date +%s) - started ))
    echo "passed in $((took / 60))m$((took % 60))s"
    post_status success "$job" "Passed on a local Mac in $((took / 60)) min"
  else
    took=$(( $(date +%s) - started ))
    echo "FAILED after $((took / 60))m$((took % 60))s — last lines of $LOGS/$job.log:"
    tail -n 25 "$LOGS/$job.log" | sed 's/^/    /'
    post_status failure "$job" "Failed on a local Mac; see its log there"
    failed=1
  fi
done
exit $failed
