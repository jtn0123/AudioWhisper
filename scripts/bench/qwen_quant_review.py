"""Reuse exact prior text judgments and expose every novel output for manual review."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from postprocess import build_helper


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("reference", type=Path)
    args = parser.parse_args()
    base = args.base
    helper = build_helper(Path(__file__).resolve().parents[2], base)
    reference = json.loads((args.reference / "manual-review.json").read_text())
    review_path = base / "manual-review.json"
    review = (json.loads(review_path.read_text()) if review_path.exists() else
              {k: value for k, value in reference.items() if k != "reviews"})
    review.setdefault("reviews", {})
    review["method"] = (
        "Identical case/input/category/delivered text reuses the prior qualitative judgment. "
        "App-failure attribution is reused only with an identical raw generation. "
        "Every novel output is manually adjudicated. One reviewer; not independently blinded."
    )
    known = {}

    def index_rows(paths, labels):
        for path in paths:
            for row in map(json.loads, path.read_text().splitlines()):
                key = row["model_id"] + "/" + row["mode"]
                if key not in labels:
                    continue
                failure = labels[key]["failures"].get(row["case"])
                signature = (row["case"], row["category"], row["input"], row["delivered"])
                raw = row["generations"][-1]["text"]
                if signature in known:
                    prior = known[signature]["failure"]
                    assert (prior is None) == (failure is None), signature
                    if failure is not None:
                        assert prior["critical"] == failure["critical"], signature
                known[signature] = {"failure": failure, "raw": raw, "reference": key}

    index_rows(sorted((args.reference / "raw").glob("*.delivered.jsonl")), reference["reviews"])
    index_rows(sorted((base / "results").glob("*.delivered.jsonl")), review["reviews"])
    drafts = {}
    for path in sorted((base / "results").glob("*-direct-strict.jsonl")):
        raw_rows = [json.loads(line) for line in path.read_text().splitlines()]
        writing = [row for row in raw_rows if row["kind"] == "writing"]
        result = subprocess.run(
            [str(helper)], input="".join(json.dumps(row) + "\n" for row in writing),
            text=True, capture_output=True, check=True,
        )
        path.with_suffix(".delivered.jsonl").write_text(result.stdout)
        delivered = [json.loads(line) for line in result.stdout.splitlines()]
        for mode in ["direct", "strict"]:
            rows = [row for row in delivered if row["mode"] == mode]
            if len(rows) != 64:
                continue
            ident = rows[0]["model_id"]
            key = ident + "/" + mode
            digest = hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()
            if key in review["reviews"]:
                assert review["reviews"][key]["outputs_sha256"] == digest
                continue
            inherited_failures = {}
            pending = []
            for row in rows:
                signature = (row["case"], row["category"], row["input"], row["delivered"])
                previous = known.get(signature)
                raw = row["generations"][-1]["text"]
                if (previous is not None and
                        not (previous["failure"] is not None and
                             previous["failure"]["component"] == "app" and raw != previous["raw"])):
                    if previous["failure"] is not None:
                        inherited_failures[row["case"]] = previous["failure"]
                else:
                    pending.append({k: row[k] for k in ["case", "category", "input", "delivered", "generations", "guard_rejected"]})
            drafts[key] = dict(total=64, inherited_failures=inherited_failures,
                               pending=pending, outputs_sha256=digest)
            if not pending:
                review["reviews"][key] = dict(
                    total=64, passes=64-len(inherited_failures),
                    critical_failures=sum(f["critical"] for f in inherited_failures.values()),
                    failures=inherited_failures, outputs_sha256=digest,
                    inherited_cases=64, manually_adjudicated_novel_cases=0,
                )
    review_path.write_text(json.dumps(review, indent=2) + "\n")
    (base / "review-drafts.json").write_text(json.dumps(drafts, indent=2) + "\n")
    print(json.dumps({key: {"inherited": 64-len(value["pending"]), "pending": len(value["pending"])}
                      for key, value in drafts.items()}))


if __name__ == "__main__":
    main()
