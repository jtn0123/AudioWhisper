"""Model loading and caching utilities for Parakeet MLX and mlx-lm."""

from __future__ import annotations

import os
from typing import Any, Dict, Optional, Tuple

# Keep HF from grabbing a token implicitly; don't force offline globally here.
os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")

# Two caches rather than one `Dict[Tuple[str, str], Any]`. The single map
# stored two different shapes under a shared key space — a bare model for
# parakeet, a (model, tokenizer) pair for correction — so its value type had
# to be `Any` and neither loader could state what it returned.
_PARAKEET_CACHE: Dict[str, Any] = {}
_CORRECTION_CACHE: Dict[str, Tuple[Any, Any]] = {}
HF_ENV_KEYS = ("HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE")


def _set_offline_env() -> Dict[str, Optional[str]]:
    """Enable offline flags, returning previous values for restoration.

    Values are `Optional[str]` because a key may be UNSET, which is distinct
    from being set to "". `_restore_env` relies on that distinction to pop
    rather than assign, so the two must agree.
    """
    previous = {k: os.environ.get(k) for k in HF_ENV_KEYS}
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    return previous


def _restore_env(previous: Dict[str, Optional[str]]) -> None:
    """Restore HF offline flags to their prior state."""
    for key, value in previous.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value


def load_parakeet_model(repo: str) -> Any:
    cached = _PARAKEET_CACHE.get(repo)
    if cached is not None:
        return cached

    try:
        from parakeet_mlx import from_pretrained
    except Exception as exc:
        raise RuntimeError(f"parakeet-mlx import failed: {exc}") from exc

    previous = _set_offline_env()
    try:
        model = from_pretrained(repo)
    except Exception as exc:
        _restore_env(previous)
        raise RuntimeError(f"Model not available offline: {exc}") from exc
    _restore_env(previous)

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

    previous = _set_offline_env()
    try:
        model, tokenizer = load(repo)
    except Exception as exc:
        _restore_env(previous)
        raise RuntimeError(
            "MLX model not available offline. Please open Settings to download it."
        ) from exc
    _restore_env(previous)

    _CORRECTION_CACHE[repo] = (model, tokenizer)
    return _CORRECTION_CACHE[repo]

