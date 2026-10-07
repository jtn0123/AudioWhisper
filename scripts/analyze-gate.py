#!/usr/bin/env python3
"""Run SwiftLint once, retaining diagnostics and rejecting incomplete analysis."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler_log", type=Path)
    parser.add_argument("--swiftlint", default="swiftlint")
    parser.add_argument("--output", type=Path, default=Path("analyze.json"))
    parser.add_argument("--baseline", type=int, default=30)
    args = parser.parse_args()
    if not args.compiler_log.is_file() or not args.compiler_log.stat().st_size:
        print("::error::Compiler log is missing or empty", file=sys.stderr)
        return 1
    result = subprocess.run(
        [args.swiftlint, "analyze", "--compiler-log-path", str(args.compiler_log),
         "--reporter", "json"], capture_output=True, text=True, check=False,
    )
    args.output.write_text(result.stdout)
    args.output.with_suffix(".stderr.txt").write_text(result.stderr)
    print(result.stderr, file=sys.stderr, end="")
    if result.returncode != 0:
        print(f"::error::Analyzer exited with {result.returncode}", file=sys.stderr)
        return 1
    # Indexing can fail for individual files even when the CLI returns zero.
    completed = re.search(r"Done analyzing!.* in ([1-9]\d*) files?\.", result.stderr)
    if not completed or re.search(r"Cannot index|(?:^|\n)Error:", result.stderr):
        print("::error::Analyzer did not complete valid indexing", file=sys.stderr)
        return 1
    try:
        findings = json.loads(result.stdout)
        if not isinstance(findings, list) or any(
            not isinstance(row, dict) or not isinstance(row.get("rule_id"), str)
            for row in findings
        ):
            raise ValueError("Expected an array of rule findings")
    except (ValueError, TypeError) as error:
        print(f"::error::Invalid analyzer report: {error}", file=sys.stderr)
        return 1
    imports = [row for row in findings if row["rule_id"] == "unused_import"]
    declarations = [row for row in findings if row["rule_id"] == "unused_declaration"]
    print(f"unused_import: {len(imports)}; unused_declaration: {len(declarations)} "
          f"(baseline {args.baseline})")
    if imports or len(declarations) > args.baseline:
        print(json.dumps(imports or declarations, indent=2))
        print("::error::Analyzer findings exceed the gate", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
