#!/usr/bin/env python3
"""Convert an lcov coverage report to SonarQube's generic test coverage XML.

Usage: lcov-to-sonar.py <input.lcov> <output.xml> <repo-root>

Only files under Sources/ are emitted, with paths made relative to the repo
root, so SonarCloud can match them against `sonar.sources`.
"""
import os
import sys
from xml.sax.saxutils import quoteattr


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: lcov-to-sonar.py <input.lcov> <output.xml> <repo-root>", file=sys.stderr)
        return 2

    lcov_path, out_path, repo_root = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])

    files: dict[str, dict[int, bool]] = {}
    current: str | None = None
    if os.path.exists(lcov_path):
        with open(lcov_path, encoding="utf-8") as handle:
            for raw in handle:
                line = raw.strip()
                if line.startswith("SF:"):
                    current = line[3:]
                elif line == "end_of_record":
                    current = None
                elif line.startswith("DA:") and current is not None:
                    parts = line[3:].split(",")
                    line_no, hits = int(parts[0]), int(parts[1])
                    covered = hits > 0
                    bucket = files.setdefault(current, {})
                    bucket[line_no] = bucket.get(line_no, False) or covered

    with open(out_path, "w", encoding="utf-8") as out:
        out.write('<coverage version="1">\n')
        for path in sorted(files):
            if "/.build/" in path or "/checkouts/" in path:
                continue
            rel = os.path.relpath(os.path.abspath(path), repo_root)
            if rel.startswith("..") or not rel.startswith("Sources/"):
                continue
            out.write(f"  <file path={quoteattr(rel)}>\n")
            for line_no in sorted(files[path]):
                covered = "true" if files[path][line_no] else "false"
                out.write(f'    <lineToCover lineNumber="{line_no}" covered="{covered}"/>\n')
            out.write("  </file>\n")
        out.write("</coverage>\n")

    print(f"Wrote {out_path} ({len(files)} files from {lcov_path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
