"""Opt-in real MLX model replacement measurement; downloads pinned public weights."""
import gc
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import weakref

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Sources"))
from ml.hub import download_snapshot
from ml.loader import _CORRECTION_CACHE, load_correction_model
import mlx.core as mx
from mlx.utils import tree_flatten

MODELS = {
    "mlx-community/gemma-3-1b-it-qat-4bit": "15fed4eafb456c6fcb2a1165f19ac609670ed14b",
    "mlx-community/Qwen3-4B-Instruct-2507-4bit": "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b",
}
for repo, revision in MODELS.items():
    download_snapshot(repo, revision)

def measure(stage, elapsed=None):
    rss = int(subprocess.check_output(["/bin/ps", "-o", "rss=", "-p", str(os.getpid())])) * 1024
    print(json.dumps({"stage": stage, "seconds": elapsed, "rss_bytes": rss,
                      "mlx_active_bytes": mx.get_active_memory(),
                      "mlx_cache_bytes": mx.get_cache_memory(),
                      "cache_entries": len(_CORRECTION_CACHE)}), flush=True)

measure("baseline")
previous = None
repos = list(MODELS)
for repo in [repos[1], repos[0], repos[1], repos[0]]:
    start = time.monotonic()
    model, tokenizer = load_correction_model(repo)
    mx.eval(*[parameter for _, parameter in tree_flatten(model.parameters())])
    assert len(_CORRECTION_CACHE) == 1
    assert previous is None or previous() is None, "replaced model remained retained"
    measure(repo, time.monotonic() - start)
    previous = weakref.ref(model)
    del model, tokenizer
_CORRECTION_CACHE.clear()
gc.collect()
mx.clear_cache()
assert previous() is None
measure("released")
