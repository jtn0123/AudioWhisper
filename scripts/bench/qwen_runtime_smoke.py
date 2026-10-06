"""Read-only basic compatibility check using a supplied installed Python runtime."""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("--sources", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    sources = args.sources or root / "Sources"
    sys.path.insert(0, str(sources))
    import mlx.core as mx
    from ml import correction, loader
    from writing_cases import production_prompts

    manifest = json.loads((args.base / "models.json").read_text())
    by_repo = {entry["repo"]: entry for entry in manifest.values()}
    loader.cached_snapshot_path = lambda repo: by_repo[repo]["path"]
    correction._safe_chat_template = lambda tokenizer, messages, system_prompt, text: (
        tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True, enable_thinking=False
        )
    )
    prompt = production_prompts(root)["general"]
    report = dict(
        python=sys.executable,
        versions={package: importlib.metadata.version(package)
                  for package in ["mlx", "mlx-lm", "transformers", "huggingface-hub"]},
        sources={str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in [sources / "ml/correction.py", sources / "ml/loader.py"]},
        scope="One short direct-answer correction per model; not an app, quality, or paste test.",
        models={},
    )
    for ident, entry in manifest.items():
        mx.random.seed(20261006)
        start = time.perf_counter()
        result = correction.correct(entry["repo"], "she dont have the files yet", prompt)
        mx.synchronize()
        report["models"][ident] = dict(
            seconds_including_load=time.perf_counter() - start,
            success=result["success"], text=result["text"],
        )
        (args.base / "installed-runtime-smoke.json").write_text(json.dumps(report, indent=2) + "\n")
        print(ident, report["models"][ident], flush=True)
        assert result["success"] and result["text"]


if __name__ == "__main__":
    main()
