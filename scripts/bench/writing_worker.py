"""Measure unchanged production correction code and production profile prompts."""
from __future__ import annotations
import time
PROCESS_START = time.perf_counter()
import argparse
import importlib.metadata
import json
from pathlib import Path
import resource
import sys

from writing_cases import cases, production_prompts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("model_id")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    entry = json.loads((args.base / "models.json").read_text())[args.model_id]
    sys.path.insert(0, str(root / "Sources"))
    import mlx.core as mx
    from ml import loader, correction
    loader.cached_snapshot_path = lambda repo: entry["path"]
    prompts = production_prompts(root)
    rows = cases()
    output = args.base / "results" / (args.model_id + ".jsonl")
    output.parent.mkdir(exist_ok=True)

    def emit(event):
        event["model_id"] = args.model_id
        event["rss_peak_bytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        event["mlx_peak_bytes"] = mx.get_peak_memory()
        with output.open("a") as handle: handle.write(json.dumps(event) + "\n")
        print(json.dumps({k: v for k, v in event.items() if k not in ["text", "input"]}), flush=True)

    start = time.perf_counter()
    model, tokenizer = loader.load_correction_model(entry["repo"])
    mx.eval(model.parameters()); mx.synchronize()
    emit(dict(kind="loaded", load_seconds=time.perf_counter() - start,
              process_to_loaded_seconds=time.perf_counter() - PROCESS_START, model=entry,
              mlx_lm=importlib.metadata.version("mlx-lm"), mlx=importlib.metadata.version("mlx"),
              temperature=correction.CORRECTION_TEMP, top_p=correction.CORRECTION_TOP_P))
    for repetition in range(2):
        for row in rows:
            # Fix seed per case for repeatability without disabling production's
            # temperature or thinking/retry behavior.
            mx.random.seed(20261005 + int(row["id"].split("-")[-1]))
            start = time.perf_counter()
            result = correction.correct(entry["repo"], row["input"], prompts[row["category"]])
            mx.synchronize()
            emit(dict(kind="writing", case=row["id"], repetition=repetition, category=row["category"],
                      input=row["input"], text=result["text"], seconds=time.perf_counter() - start,
                      success=result.get("success"), process_to_result_seconds=time.perf_counter() - PROCESS_START if repetition == 0 and row == rows[0] else None))
    emit(dict(kind="complete", cases=len(rows), repetitions=2))


if __name__ == "__main__":
    main()
