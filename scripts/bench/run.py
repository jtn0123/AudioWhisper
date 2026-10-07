"""Sequential runs prevent the models from competing for the same GPU."""
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
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    candidates = args.base / ".venv/bin/python"
    current = Path.home() / "Library/Application Support/AudioWhisper Rebuild/python_project/.venv/bin/python"
    registry = json.loads((args.base / "models.json").read_text())
    order = ["parakeet-v2", "granite-5", "cohere-8bit", "qwen3-asr-4bit", "parakeet-v3",
             "whisper-large-v3_turbo", "whisper-base", "whisper-small", "whisper-tiny",
             "writing-qwen4b", "writing-gemma1b", "writing-qwen1.7b",
             "writing-lfm1.2b", "writing-qwen3.5-2b", "writing-gemma4"]
    results = args.base / "results"
    results.mkdir(exist_ok=True)
    status_path = results / "run-status.json"
    status = json.loads(status_path.read_text()) if status_path.exists() else {}
    for ident in args.only or order:
        entry = registry[ident]
        path = results / (ident + ".jsonl")
        previous = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        complete = any(row.get("kind") == "complete" and not row.get("failures", 0) for row in previous)
        expected_kind, expected_count = ("writing", 56) if ident.startswith("writing") else ("quality", 68)
        if complete and sum(row["kind"] == expected_kind for row in previous) == expected_count:
            print("ALREADY COMPLETE", ident, flush=True)
            continue
        if path.exists():
            path.rename(path.with_suffix(f".partial-{int(time.time())}.jsonl"))
        if entry["runtime"] == "whisper":
            command = [str(args.base / "swift-build/release/WhisperBenchmark"), str(args.base), ident]
        else:
            python = (args.base / ".cohere-venv/bin/python" if entry["runtime"] == "cohere-speech"
                      else current if entry["runtime"] in ["current", "writing-current"] else candidates)
            worker = "writing_worker.py" if entry["runtime"].startswith("writing") else "asr_worker.py"
            command = [str(python), str(root / "scripts/bench" / worker), str(args.base), ident]
        environment = dict(os.environ, HF_HUB_OFFLINE="1", HF_HUB_DISABLE_IMPLICIT_TOKEN="1",
                           TOKENIZERS_PARALLELISM="false", HF_HUB_CACHE=str(args.base / "hf/hub"))
        # The app-owned Python environment is read-only; user package state and
        # bytecode caches are never modified by the benchmark.
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        start = time.perf_counter()
        print("START", ident, flush=True)
        with (results / (ident + ".log")).open("w") as log:
            try:
                result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=900)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = "timeout"
        status[ident] = dict(exit=code, elapsed=time.perf_counter() - start)
        status_path.write_text(json.dumps(status, indent=2) + "\n")
        print("FINISH", ident, status[ident], flush=True)
        if code != 0:
            print("\n".join((results / (ident + ".log")).read_text().splitlines()[-10:]), flush=True)


if __name__ == "__main__": main()
