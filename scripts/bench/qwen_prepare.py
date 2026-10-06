"""Download fixed Qwen revisions into an isolated cache; retain existing assets."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import time

PINS = {
    "qwen3-4b": ("mlx-community/Qwen3-4B-Instruct-2507-4bit", "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"),
    "qwen3.5-4b": ("mlx-community/Qwen3.5-4B-4bit", "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c"),
    "qwen3.5-9b": ("mlx-community/Qwen3.5-9B-4bit", "8b2b98c00a6b4d291155e4890773ca8f769aee53"),
    "qwen3.8-27b": ("mlx-community/Qwen3.8-27B-4bit", "10c35caafbb80f7dc6a7a432cdd11af10a6d4818"),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    args = parser.parse_args()
    os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
    from huggingface_hub import snapshot_download
    args.base.mkdir(parents=True, exist_ok=True)
    manifest = args.base / "models.json"
    saved = json.loads(manifest.read_text()) if manifest.exists() else {}
    for ident, (repo, revision) in PINS.items():
        if ident in saved:
            if saved[ident]["revision"] != revision:
                raise RuntimeError(f"Revision mismatch in existing cache: {ident}")
            continue
        start = time.perf_counter()
        existing = Path.home() / ".cache/huggingface/hub" / ("models--" + repo.replace("/", "--")) / "snapshots" / revision
        if existing.is_dir():
            path, origin = existing, "existing pinned cache; read only"
        else:
            path = Path(snapshot_download(repo, revision=revision, cache_dir=str(args.base / "hf/hub")))
            origin = "isolated pinned benchmark download"
        saved[ident] = dict(repo=repo, revision=revision, path=str(path), origin=origin,
                            logical_bytes=sum(p.stat().st_size for p in path.rglob("*") if p.is_file()),
                            preparation_seconds=time.perf_counter() - start)
        temporary = manifest.with_suffix(".tmp")
        temporary.write_text(json.dumps(saved, indent=2) + "\n")
        temporary.replace(manifest)
        print("READY", ident, saved[ident]["logical_bytes"], flush=True)


if __name__ == "__main__":
    main()
