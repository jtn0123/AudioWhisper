"""mlx-lm semantic correction helpers."""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .loader import load_correction_model

DEFAULT_CORRECTION_PROMPT = (
    "Clean up this speech transcription: fix typos, grammar, punctuation, and remove "
    "filler words (um, uh, like, you know). Keep the original language. Output only "
    "the corrected text."
)


def _safe_chat_template(
    tokenizer: Any,
    messages: List[Dict[str, str]],
    system_prompt: str,
    text: str,
) -> str:
    try:
        # Keep thinking enabled for better quality - we strip <think> tags from output
        return tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
        )
    except Exception:
        return f"{system_prompt}\n\n{text}"


# Sampling parameters for the correction pass. Low temperature: we want the
# model to fix the transcript, not to paraphrase it.
CORRECTION_TEMP = 0.2
CORRECTION_TOP_P = 0.9


def _build_sampler() -> Optional[Any]:
    """Build an mlx-lm sampler for the correction temperature/top-p.

    mlx-lm >= 0.20 moved sampling out of ``generate``'s keyword arguments and
    into an explicit ``sampler`` callable: ``generate_step`` now accepts
    ``sampler=`` and rejects ``temp=``/``top_p=``. Passing the old keywords
    raises TypeError only once execution reaches ``generate_step``, i.e. after
    prompt processing has already been paid for.

    Returns ``None`` when ``make_sampler`` is unavailable, so the caller can
    fall back to the legacy keyword form.
    """
    try:
        from mlx_lm.sample_utils import make_sampler
    except Exception:
        return None
    try:
        return make_sampler(temp=CORRECTION_TEMP, top_p=CORRECTION_TOP_P)
    except Exception:
        return None


def _safe_generate(
    model: Any,
    tokenizer: Any,
    chat_prompt: str,
    max_tokens: int,
) -> str:
    try:
        from mlx_lm import generate
    except Exception as exc:
        raise RuntimeError(f"mlx-lm import failed: {exc}") from exc

    # Preferred path on current mlx-lm: an explicit sampler.
    sampler = _build_sampler()
    if sampler is not None:
        try:
            return generate(
                model,
                tokenizer,
                prompt=chat_prompt,
                max_tokens=max_tokens,
                sampler=sampler,
                verbose=False,
            )
        except TypeError:
            pass

    # Legacy mlx-lm (< 0.20) took the sampling knobs directly.
    try:
        return generate(
            model,
            tokenizer,
            prompt=chat_prompt,
            max_tokens=max_tokens,
            temp=CORRECTION_TEMP,
            top_p=CORRECTION_TOP_P,
            verbose=False,
        )
    except TypeError:
        # Last resort: default (greedy) sampling. Correction still works, it
        # just loses the temperature tuning.
        return generate(
            model,
            tokenizer,
            prompt=chat_prompt,
            max_tokens=max_tokens,
            verbose=False,
        )


def correct(repo: str, text: str, prompt: Optional[str]) -> Dict[str, Any]:
    model, tokenizer = load_correction_model(repo)

    system_prompt = (
        prompt.strip() if prompt and prompt.strip() else DEFAULT_CORRECTION_PROMPT
    )
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": text},
    ]

    chat_prompt = _safe_chat_template(tokenizer, messages, system_prompt, text)
    # Allow more tokens for thinking overhead
    max_tokens = max(128, min(4096, int(len(text.split()) * 4)))

    generated = _safe_generate(model, tokenizer, chat_prompt, max_tokens)

    if generated.startswith(chat_prompt):
        generated = generated[len(chat_prompt) :]

    # Strip complete <think>...</think> blocks
    cleaned = re.sub(r"<think>.*?</think>", "", generated, flags=re.DOTALL)
    # Strip incomplete <think> blocks (model truncated before closing tag)
    cleaned = re.sub(r"<think>.*", "", cleaned, flags=re.DOTALL)
    cleaned = cleaned.strip().strip('"').strip("'").strip()
    
    # If result is empty (all thinking, no answer), retry with thinking disabled
    if not cleaned:
        try:
            chat_prompt_no_think = tokenizer.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True, enable_thinking=False
            )
            generated = _safe_generate(model, tokenizer, chat_prompt_no_think, max_tokens)
            if generated.startswith(chat_prompt_no_think):
                generated = generated[len(chat_prompt_no_think):]
            cleaned = re.sub(r"<think>.*?</think>", "", generated, flags=re.DOTALL)
            cleaned = re.sub(r"<think>.*", "", cleaned, flags=re.DOTALL)
            cleaned = cleaned.strip().strip('"').strip("'").strip()
        except Exception:
            # Bug fix: Return original text if fallback fails instead of empty string
            cleaned = text

    # Bug fix: Also return original text if still empty after retries
    if not cleaned:
        cleaned = text

    return {"success": True, "text": cleaned}

