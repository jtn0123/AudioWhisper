#!/usr/bin/env python3
"""Resolve exactly one macOS test executable in the tested configuration."""
from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: coverage-test-binary.py <swift-build-bin-path>", file=sys.stderr)
        return 2
    directory = Path(sys.argv[1])
    bundles = list(directory.glob("*.xctest"))
    if len(bundles) == 1:
        binary = bundles[0] / "Contents" / "MacOS" / bundles[0].stem
        if binary.is_file():
            print(binary)
            return 0
    print(f"Expected one complete test bundle in {directory}; found {len(bundles)}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
