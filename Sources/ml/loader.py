"""Model loading and caching utilities for Parakeet MLX and mlx-lm."""

from __future__ import annotations

import os
import gc
from typing import Any, Dict, Tuple

from .hub import cached_snapshot_path

# Keep HF from grabbing a token implicitly. (Offline is guaranteed per call by
# `cached_snapshot_path`, and the daemon also sets it before any import.)
os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")

# Two caches rather than one `Dict[Tuple[str, str], Any]`. The single map
# stored two different shapes under a shared key space — a bare model for
# parakeet, a (model, tokenizer) pair for correction — so its value type had
# to be `Any` and neither loader could state what it returned.
_PARAKEET_CACHE: Dict[str, Any] = {}
_CORRECTION_CACHE: Dict[str, Tuple[Any, Any]] = {}

# Both loaders resolve the cached snapshot to a local directory first and load
# from that path. This file used to set HF_HUB_OFFLINE around each load and
# restore it afterwards, which never worked — huggingface_hub reads the flag
# once at import, and the model libraries had imported it already — so every
# load went online. See ml/hub.py.


def _release_previous_models(cache: Dict[str, Any]) -> None:
    # RPC dispatch is sequential, so the previous inference has finished here.
    # Release its weights before allocating a replacement, keeping each engine
    # bounded to one loaded repository.
    if not cache:
        return
    cache.clear()
    gc.collect()
    try:
        import mlx.core as mx
    except ImportError:
        return
    mx.clear_cache()


def load_parakeet_model(repo: str) -> Any:
    cached = _PARAKEET_CACHE.get(repo)
    if cached is not None:
        return cached

    try:
        from parakeet_mlx import from_pretrained
    except Exception as exc:
        raise RuntimeError(f"parakeet-mlx import failed: {exc}") from exc

    _release_previous_models(_PARAKEET_CACHE)
    try:
        model = from_pretrained(cached_snapshot_path(repo))
    except Exception as exc:
        raise RuntimeError(f"Model not available offline: {exc}") from exc

    _PARAKEET_CACHE[repo] = model
    return model


def load_correction_model(repo: str) -> Tuple[Any, Any]:
    cached = _CORRECTION_CACHE.get(repo)
    if cached is not None:
        return cached

    try:
        from mlx_lm import load
    except Exception as exc:
        raise RuntimeError(f"mlx-lm import failed: {exc}") from exc

    _release_previous_models(_CORRECTION_CACHE)
    try:
        model, tokenizer = load(cached_snapshot_path(repo))
    except Exception as exc:
        raise RuntimeError(
            "MLX model not available offline. Please open Settings to download it."
        ) from exc

    _CORRECTION_CACHE[repo] = (model, tokenizer)
    return _CORRECTION_CACHE[repo]
