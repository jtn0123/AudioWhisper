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
    "qwen3.5-9b-8bit": ("mlx-community/Qwen3.5-9B-MLX-8bit", "84f7c2deea248d8df56240f88102def51c7ed5d6"),
    "qwen3.8-27b-6bit": ("lmstudio-community/Qwen3.8-27B-MLX-6bit", "05f38c1f39e2f39619653616fe8e96a5d676358e"),
    "qwen3.8-27b-3bit": ("leonsarmiento/Qwen3.8-27B-3bit-mlx", "5fc234d9e6080b8388a11286380e801b7c9f535c"),
}
ORIGINAL_MODELS = ["qwen3-4b", "qwen3.5-4b", "qwen3.5-9b", "qwen3.8-27b"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("--only", nargs="+", choices=list(PINS), default=ORIGINAL_MODELS)
    parser.add_argument("--reuse-base", type=Path,
                        help="Reuse exact pinned snapshots from a previous isolated benchmark.")
    args = parser.parse_args()
    os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
    from huggingface_hub import snapshot_download
    args.base.mkdir(parents=True, exist_ok=True)
    manifest = args.base / "models.json"
    saved = json.loads(manifest.read_text()) if manifest.exists() else {}
    reusable = json.loads((args.reuse_base / "models.json").read_text()) if args.reuse_base else {}
    for ident in args.only:
        repo, revision = PINS[ident]
        if ident in saved:
            if saved[ident]["revision"] != revision:
                raise RuntimeError(f"Revision mismatch in existing cache: {ident}")
            continue
        start = time.perf_counter()
        existing = Path.home() / ".cache/huggingface/hub" / ("models--" + repo.replace("/", "--")) / "snapshots" / revision
        previous = reusable.get(ident, {})
        if (previous.get("repo") == repo and previous.get("revision") == revision
                and Path(previous.get("path", "/nonexistent")).is_dir()):
            path, origin = Path(previous["path"]), "previous pinned benchmark cache; read only"
        elif existing.is_dir():
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
