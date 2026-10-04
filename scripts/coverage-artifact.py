#!/usr/bin/env python3
"""Bind a validated coverage report to the commit and CI run that produced it."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def report_hash(report: Path, kind: str) -> str:
    data = report.read_bytes()
    root = ET.fromstring(data)
    if root.tag != "coverage":
        raise ValueError("expected a coverage XML document")
    if kind == "swift":
        covered_sources = [
            entry for entry in root.findall("file")
            if entry.get("path", "").startswith("Sources/")
            and entry.get("path", "").endswith(".swift")
            and entry.findall("lineToCover")
        ]
    else:
        covered_sources = [
            entry for entry in root.findall(".//class")
            if entry.get("filename", "").startswith("Sources/")
            and entry.get("filename", "").endswith(".py")
            and entry.findall("lines/line")
        ]
    if not covered_sources:
        raise ValueError(f"no {kind} application source lines in {report}")
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("create", "verify"))
    parser.add_argument("kind", choices=("swift", "python"))
    parser.add_argument("report", type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--attempt", required=True)
    args = parser.parse_args()
    manifest = args.report.with_suffix(args.report.suffix + ".manifest.json")
    try:
        expected = {
            "schema": 1,
            "kind": args.kind,
            "report": args.report.name,
            "commit": args.commit,
            "run_id": args.run_id,
            "attempt": args.attempt,
            "sha256": report_hash(args.report, args.kind),
        }
        if args.action == "create":
            manifest.write_text(json.dumps(expected, indent=2) + "\n", encoding="utf-8")
        elif json.loads(manifest.read_text(encoding="utf-8")) != expected:
            raise ValueError("coverage provenance or content does not match this CI run")
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"Coverage artifact rejected: {error}", file=sys.stderr)
        return 1
    print(f"{args.action}: validated {args.kind} coverage for {args.commit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
