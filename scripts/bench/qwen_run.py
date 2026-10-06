"""Run Qwen comparisons sequentially after isolated model preparation."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--only", nargs="+", required=True)
    parser.add_argument("--modes", nargs="+", choices=["direct", "production", "strict"],
                        default=["direct", "production"])
    parser.add_argument("--production-limit", type=int, default=64)
    args = parser.parse_args()
    if not 1 <= args.production_limit <= 64:
        parser.error("--production-limit must be between 1 and 64")
    worker = Path(__file__).with_name("qwen_worker.py")
    status = {}
    for ident in args.only:
        deadline = time.monotonic() + 1200
        while ident not in json.loads((args.base / "models.json").read_text()):
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Model preparation did not finish: {ident}")
            time.sleep(1)
        start = time.perf_counter()
        print("START", ident, flush=True)
        suffix = "" if args.modes == ["direct", "production"] else "-" + "-".join(args.modes)
        environment = dict(os.environ, HF_HUB_OFFLINE="1", HF_HUB_DISABLE_IMPLICIT_TOKEN="1",
                           PYTHONDONTWRITEBYTECODE="1", TOKENIZERS_PARALLELISM="false")
        with (args.base / f"{ident}{suffix}.log").open("w") as log:
            result = subprocess.run([str(args.python), str(worker), str(args.base), ident,
                                     "--production-limit", str(args.production_limit), "--modes", *args.modes],
                                    env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
        status[ident] = dict(exit=result.returncode, elapsed=time.perf_counter() - start)
        (args.base / f"run-status{suffix}.json").write_text(json.dumps(status, indent=2) + "\n")
        print("FINISH", ident, status[ident], flush=True)
        if result.returncode:
            raise RuntimeError((args.base / f"{ident}{suffix}.log").read_text()[-2000:])
        rows = [json.loads(s) for s in (args.base / "results" / f"{ident}{suffix}.jsonl").read_text().splitlines()]
        assert rows[-1]["kind"] == "complete"
        expected = sum(min(64, args.production_limit) if m == "production" else 64 for m in args.modes)
        assert sum(r["kind"] == "writing" for r in rows) == expected


if __name__ == "__main__":
    main()
