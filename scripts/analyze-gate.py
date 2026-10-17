#!/usr/bin/env python3
"""Run SwiftLint once, retaining diagnostics and rejecting incomplete analysis."""
import argparse
import contextlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import time

from analyze_cache import read_bundle, write_bundle


def validate_report(stdout, stderr, status, baseline):
    # SwiftLint exits 2 after successfully reporting error-severity findings.
    # unused_declaration defaults to error, including our ratcheted baseline.
    # Accept that code only after validating the complete report below; crashes,
    # indexing errors, and an unexplained exit 2 still fail closed.
    if status not in (0, 2):
        print(f"::error::Analyzer exited with {status}", file=sys.stderr)
        return 1
    # Indexing can fail for individual files even when the CLI returns zero.
    completed = re.search(
        r"Done analyzing! Found (\d+) violations?, (\d+) serious in ([1-9]\d*) files?\.",
        stderr,
    )
    if not completed or re.search(r"Cannot index|(?:^|\n)Error:", stderr):
        print("::error::Analyzer did not complete valid indexing", file=sys.stderr)
        return 1
    try:
        findings = json.loads(stdout)
        if not isinstance(findings, list) or any(
            not isinstance(row, dict) or not isinstance(row.get("rule_id"), str)
            or row.get("severity") not in ("Warning", "Error")
            for row in findings
        ):
            raise ValueError("Expected an array of rule findings")
    except (ValueError, TypeError) as error:
        print(f"::error::Invalid analyzer report: {error}", file=sys.stderr)
        return 1
    serious = sum(row["severity"] == "Error" for row in findings)
    if (len(findings) != int(completed.group(1))
            or serious != int(completed.group(2))
            or (status == 2) != (serious > 0)):
        print("::error::Analyzer exit status and completed report disagree", file=sys.stderr)
        return 1
    imports = [row for row in findings if row["rule_id"] == "unused_import"]
    declarations = [row for row in findings if row["rule_id"] == "unused_declaration"]
    print(f"unused_import: {len(imports)}; unused_declaration: {len(declarations)} "
          f"(baseline {baseline})")
    other_errors = [row for row in findings if row["severity"] == "Error"
                    and row["rule_id"] not in ("unused_import", "unused_declaration")]
    if imports or len(declarations) > baseline or other_errors:
        print(json.dumps(imports or other_errors or declarations, indent=2))
        print("::error::Analyzer findings exceed the gate", file=sys.stderr)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler_log", type=Path)
    parser.add_argument("--swiftlint", default="swiftlint")
    parser.add_argument("--output", type=Path, default=Path("analyze.json"))
    parser.add_argument("--baseline", type=int, default=30)
    parser.add_argument("--cache-directory", type=Path)
    parser.add_argument("--cache-key", help="Complete input fingerprint from analyze_cache.py")
    parser.add_argument("--check-cache", action="store_true", help="Validate a restored report without running analysis")
    parser.add_argument("--benchmark", action="store_true")
    args = parser.parse_args()
    if bool(args.cache_directory) != bool(args.cache_key) or (args.cache_key and not re.fullmatch(r"[0-9a-f]{64}", args.cache_key)):
        parser.error("Cache directory and a SHA-256 input key must be supplied together")
    if args.check_cache and not args.cache_directory:
        parser.error("--check-cache requires a cache directory and input key")
    diagnostics = args.output.with_suffix('.stderr.txt')
    if args.cache_directory:
        cached = read_bundle(args.cache_directory, args.cache_key)
        messages = io.StringIO()
        with contextlib.redirect_stdout(messages), contextlib.redirect_stderr(messages):
            valid = cached is not None and validate_report(*cached, args.baseline) == 0
        if valid:
            args.output.write_text(cached[0])
            diagnostics.write_text(cached[1])
            print(messages.getvalue(), end='')
            print('Reused complete analyzer report for identical inputs; gates revalidated.', flush=True)
            return 0
        print('No valid exact-input analyzer cache.', flush=True)
        if args.check_cache:
            return 1
    if not args.compiler_log.is_file() or not args.compiler_log.stat().st_size:
        print("::error::Compiler log is missing or empty", file=sys.stderr)
        return 1
    command = [args.swiftlint, 'analyze', '--compiler-log-path', str(args.compiler_log), '--reporter', 'json']
    if args.benchmark:
        command.append('--benchmark')
    started = time.monotonic()
    # stdout goes straight to disk so large reports cannot block the stderr pipe.
    with args.output.open('w') as report, diagnostics.open('w') as errors:
        with subprocess.Popen(command, stdout=report, stderr=subprocess.PIPE, text=True, bufsize=1) as process:
            for message in process.stderr:
                errors.write(message)
                errors.flush()
                print(message, file=sys.stderr, end='', flush=True)
            status = process.wait()
    print(f'Full analyzer elapsed: {time.monotonic() - started:.2f}s', file=sys.stderr, flush=True)
    report = args.output.read_text()
    errors = diagnostics.read_text()
    result = validate_report(report, errors, status, args.baseline)
    if result == 0 and args.cache_directory:
        write_bundle(args.cache_directory, args.cache_key, report, errors, status)
    return result


if __name__ == "__main__":
    sys.exit(main())
