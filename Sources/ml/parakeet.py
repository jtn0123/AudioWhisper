"""Parakeet transcription helpers."""

from __future__ import annotations

import os
from typing import Any, Callable, Dict

from .loader import load_parakeet_model

DEFAULT_PARAKEET_REPO = "mlx-community/parakeet-tdt-0.6b-v2"
CHUNK_SECONDS = 120
OVERLAP_SECONDS = 15


def extract_parakeet_text(result: Any) -> str:
    if isinstance(result, list) and result:
        first_item = result[0]
        if hasattr(first_item, "text"):
            return first_item.text or ""
        return str(first_item)

    if hasattr(result, "text"):
        return result.text or ""
    if hasattr(result, "texts") and getattr(result, "texts"):
        return result.texts[0] or ""

    if isinstance(result, dict):
        if "text" in result:
            return result.get("text", "") or ""
        if "texts" in result and result.get("texts"):
            return result["texts"][0] or ""

    raise AttributeError(f"Cannot extract text from result: {result}")


def transcribe(repo: str, pcm_path: str) -> Dict[str, Any]:
    if not os.path.exists(pcm_path):
        raise FileNotFoundError(f"PCM file not found: {pcm_path}")
    if not os.access(pcm_path, os.R_OK):
        raise PermissionError(f"Cannot read PCM file: {pcm_path}")

    try:
        import numpy as np
    except ImportError as exc:
        raise RuntimeError(f"numpy import failed: {exc}") from exc

    try:
        import mlx.core as mx
    except ImportError as exc:
        raise RuntimeError(f"mlx.core import failed: {exc}") from exc

    try:
        from parakeet_mlx.audio import get_logmel
    except ImportError as exc:
        raise RuntimeError(f"parakeet_mlx.audio import failed: {exc}") from exc

    model = load_parakeet_model(repo)
    frames = os.path.getsize(pcm_path) // 4
    sample_rate = model.preprocessor_config.sample_rate
    if frames <= CHUNK_SECONDS * sample_rate:
        audio_data = np.fromfile(pcm_path, dtype=np.float32, count=CHUNK_SECONDS * sample_rate)
        mel = get_logmel(mx.array(audio_data), model.preprocessor_config)
        text = extract_parakeet_text(model.generate(mel))
    else:
        text = transcribe_chunks(model, pcm_path, frames, np, mx, get_logmel)
    return {"success": True, "text": text}


def transcribe_chunks(
    model: Any, pcm_path: str, frames: int, np: Any, mx: Any,
    get_logmel: Callable[[Any, Any], Any],
) -> str:
    # Use the vendor's overlapping-token merge, while reading raw PCM in bounded
    # windows instead of its full-file loader. Short recordings retain the same
    # generation path; long attention tensors never span the complete input.
    from parakeet_mlx import DecodingConfig
    from parakeet_mlx.alignment import (
        merge_longest_contiguous, merge_longest_common_subsequence,
        sentences_to_result, tokens_to_sentences,
    )

    rate = model.preprocessor_config.sample_rate
    chunk_frames = CHUNK_SECONDS * rate
    stride = (CHUNK_SECONDS - OVERLAP_SECONDS) * rate
    tokens: list[Any] = []
    for start in range(0, frames, stride):
        data = np.fromfile(pcm_path, dtype=np.float32, count=chunk_frames, offset=start * 4)
        if len(data) < model.preprocessor_config.hop_length:
            break
        result = model.generate(get_logmel(mx.array(data), model.preprocessor_config))[0]
        for token in result.tokens:
            token.start += start / rate
            token.end = token.start + token.duration
        if tokens:
            try:
                tokens = merge_longest_contiguous(tokens, result.tokens, overlap_duration=OVERLAP_SECONDS)
            except RuntimeError:
                tokens = merge_longest_common_subsequence(tokens, result.tokens, overlap_duration=OVERLAP_SECONDS)
        else:
            tokens = result.tokens
    merged = sentences_to_result(tokens_to_sentences(tokens, DecodingConfig().sentence))
    return extract_parakeet_text(merged)
