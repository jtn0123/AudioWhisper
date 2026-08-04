#!/usr/bin/env python3
"""Line-coverage ratchet over this project's own sources.

Usage: coverage-gate.py <codecov.json> <repo-root> <threshold>

Reads SwiftPM's codecov JSON (`swift test --show-codecov-path`) and reports
line coverage for files under <repo-root>/Sources ONLY.

Why not `data[0].totals`: that figure covers every instrumented file, which
includes the dependency sources SwiftPM builds under .build/checkouts. On this
project the two numbers differ by ~25 points (53.7% all-files vs 28.4% for our
own code), because WhisperKit, KeyboardShortcuts and swift-transformers are
large and well covered by their own exercised code paths.

Gating on the all-files number has two failure modes:
  * it flatters us — most of the "covered" lines are not ours;
  * it is movable by things that are not tests. A dependency bump that adds
    well-covered code raises it with no new tests, and one that adds uncovered
    code can redden CI with no change to this repo at all.

Anchoring on <repo-root>/Sources matters: dependency paths like
.build/checkouts/KeyboardShortcuts/Sources/... also contain "/Sources/", so a
substring match would silently readmit exactly what we are excluding.
"""

import json
import os
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    cov_path, repo_root, threshold_arg = sys.argv[1:4]
    threshold = float(threshold_arg)
    prefix = os.path.join(os.path.realpath(repo_root), "Sources") + os.sep

    try:
        with open(cov_path) as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as exc:
        print(f"::error::Could not read coverage JSON at '{cov_path}': {exc}")
        return 1

    try:
        files = payload["data"][0]["files"]
    except (KeyError, IndexError) as exc:
        print(f"::error::Unexpected codecov JSON shape in '{cov_path}': {exc}")
        return 1

    covered = 0
    count = 0
    matched = 0
    for entry in files:
        if not os.path.realpath(entry["filename"]).startswith(prefix):
            continue
        matched += 1
        lines = entry["summary"]["lines"]
        covered += lines["covered"]
        count += lines["count"]

    if matched == 0:
        # A gate that cannot find its input is broken and should say so, not
        # pass. Same reasoning as the "no coverage JSON" branch in ci.yml.
        print(f"::error::No covered files found under {prefix}")
        print("::error::The gate matched 0 of "
              f"{len(files)} instrumented files — check the repo root argument.")
        return 1

    pct = (covered / count * 100) if count else 0.0
    print(f"Line coverage (Sources only): {pct:.2f}% "
          f"({covered}/{count} lines across {matched} files)")

    if pct < threshold:
        print(f"::error::Line coverage {pct:.2f}% is below the "
              f"{threshold:g}% ratchet.")
        return 1

    print(f"Coverage {pct:.2f}% >= ratchet {threshold:g}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
