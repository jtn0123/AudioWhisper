#!/usr/bin/env bash
# Audit reproducer: illustrates the audited CI recipe's failure suppression.
# Run from the repository root. No production source/configuration is changed.
set +e
set -o pipefail
audit_dir=$(mktemp -d /tmp/audiowhisper-analyzer-audit.XXXXXX) || exit 1
trap 'rm -rf "$audit_dir"' EXIT
missing_log="$audit_dir/missing-compiler.log"

swiftlint analyze --compiler-log-path "$missing_log" \
  --reporter github-actions-logging >"$audit_dir/direct.txt" 2>"$audit_dir/error.txt"
checker_status=$?

# Exact failure-suppression shape from the audited Analyze step.
swiftlint analyze --compiler-log-path "$missing_log" \
  --reporter github-actions-logging 2>/dev/null | tee "$audit_dir/report.txt" || true
recipe_status=$?
imports=$(grep -c '(unused_import)' "$audit_dir/report.txt" || true)
declarations=$(grep -c '(unused_declaration)' "$audit_dir/report.txt" || true)
printf 'checker_exit=%s recipe_exit=%s imports=%s declarations=%s report_bytes=%s\n' \
  "$checker_status" "$recipe_status" "${imports:-0}" "${declarations:-0}" \
  "$(wc -c <"$audit_dir/report.txt")"
head -3 "$audit_dir/error.txt"

# Zero means the audit reproduced the flaw, not that the production gate is safe.
test "$checker_status" -ne 0 && test "$recipe_status" -eq 0 \
  && test ! -s "$audit_dir/report.txt" \
  && test "${imports:-0}" -eq 0 && test "${declarations:-0}" -eq 0
