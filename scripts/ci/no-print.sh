#!/usr/bin/env bash
# CI gate: no print() in Sources/ outside an #if DEBUG block (use Logger).
# Run from the repo root (of the checkout being tested). Called by .github/workflows/ci.yml and scripts/ci-local.sh.
set -uo pipefail
violations=$(grep -rn --include='*.swift' -E '^\s*print\(' Sources/ | grep -v '//.*print' || true)
# Filter out lines that appear inside a #if DEBUG block by checking surrounding lines.
#
# NOTE: the loop reads from a process substitution rather than a pipe.
# `echo "$violations" | while ...` runs the loop body in a SUBSHELL, so
# an `exit 1` inside it only terminates that subshell — the step then
# falls through to the success echo and exits 0. This gate silently
# passed on every run until that was fixed.
failed=0
if [ -n "$violations" ]; then
  while IFS=: read -r file line _rest; do
    [ -n "$file" ] || continue
    # Search 50 lines back for #if DEBUG, then check if a #endif came between
    ctx=$(sed -n "1,${line}p" "$file" | tail -n 50)
    last_debug=$(echo "$ctx" | grep -n '#if DEBUG' | tail -n 1 | cut -d: -f1 || true)
    last_endif=$(echo "$ctx" | grep -n '#endif' | tail -n 1 | cut -d: -f1 || true)
    if [ -z "$last_debug" ] || { [ -n "$last_endif" ] && [ "$last_endif" -gt "$last_debug" ]; }; then
      echo "::error file=$file,line=$line::print() outside #if DEBUG"
      failed=1
    fi
  done < <(echo "$violations")
fi
if [ "$failed" -ne 0 ]; then
  echo "Production print() found — wrap in #if DEBUG or use Logger."
  exit 1
fi
echo "No production print() found"
