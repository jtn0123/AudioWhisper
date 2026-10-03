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


def _require_str(value: Any, source: str) -> str:
    """Assert that an untyped mlx-lm call actually handed back a string.

    Both `apply_chat_template` and `generate` are untyped, so their results
    arrive as `Any` and mypy cannot tell a string from anything else. `cast()`
    would silence that without checking — the same kind of lie the old
    `_set_offline_env` (since deleted) told about its return type.

    The check earns its keep: mlx-lm's surface moves across minor versions (see
    the upgrade checklist in Sources/Resources/pyproject.toml). If `generate`
    ever returns a structured result instead of a bare string, the current code
    carries it into `generated.startswith(chat_prompt)` and dies with an
    AttributeError several frames away from the cause. This fails at the
    boundary instead, naming the call that broke.

    Raises RuntimeError, deliberately NOT TypeError: `_safe_generate` catches
    TypeError to fall back between mlx-lm sampler signatures, and a wrong return
    type is not a signature mismatch to retry.
    """
    if not isinstance(value, str):
        raise RuntimeError(f"{source} returned {type(value).__name__}, expected str")
    return value


def _safe_chat_template(
    tokenizer: Any,
    messages: List[Dict[str, str]],
    system_prompt: str,
    text: str,
) -> str:
    try:
        # Keep thinking enabled for better quality - we strip <think> tags from output
        return _require_str(
            tokenizer.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True,
            ),
            "tokenizer.apply_chat_template",
        )
    except Exception:
        # Includes the _require_str failure: a non-string template result
        # degrades to the plain-text prompt rather than propagating.
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
            return _require_str(
                generate(
                    model,
                    tokenizer,
                    prompt=chat_prompt,
                    max_tokens=max_tokens,
                    sampler=sampler,
                    verbose=False,
                ),
                "mlx_lm.generate",
            )
        except TypeError:
            pass

    # Legacy mlx-lm (< 0.20) took the sampling knobs directly.
    try:
        return _require_str(
            generate(
                model,
                tokenizer,
                prompt=chat_prompt,
                max_tokens=max_tokens,
                temp=CORRECTION_TEMP,
                top_p=CORRECTION_TOP_P,
                verbose=False,
            ),
            "mlx_lm.generate",
        )
    except TypeError:
        # Last resort: default (greedy) sampling. Correction still works, it
        # just loses the temperature tuning.
        return _require_str(
            generate(
                model,
                tokenizer,
                prompt=chat_prompt,
                max_tokens=max_tokens,
                verbose=False,
            ),
            "mlx_lm.generate",
        )


# --------------------------------------------------------------- sanitisation
# Chat-template control tokens. Models routinely emit these when generation runs
# past the answer. They are never part of a corrected transcript, so removing
# them is unconditionally safe.
#
# Found by the 2026-07-31 model benchmark: Phi-3.5-mini produced a CORRECT
# correction that arrived as
#     "Remember to call the dentist tomorrow morning.<|end|><|assistant|> …"
# The trailing tokens pushed safeMerge's edit-distance ratio to 0.6083 — just
# past the 0.6 threshold — so the app discarded a perfectly good correction and
# pasted the raw transcript instead.
_SPECIAL_TOKEN_RE = re.compile(r"<\|[^|>]{0,40}\|?>")

# Reasoning preambles. `<think>` is only ONE of the formats in the wild:
#   Qwen3            -> "<think> … </think>"
#   gemma-4          -> "<|channel>thought\nThinking Process: …"
#   Qwen3.5          -> "Thinking Process: …"      (no tags at all)
# The bare-text variants were invisible to the old `<think>`-only stripper, so
# raw chain-of-thought flowed into the transcript and safeMerge rejected the
# whole correction. Both models scored 0/6 in the benchmark purely because of
# this, not because of output quality.
#
# The risk here is asymmetric, so the match is deliberately narrow:
#   * missing a preamble  -> safeMerge rejects, user gets the raw transcript
#                            (annoying, but nothing is lost)
#   * matching too eagerly -> the user's actual dictated words are deleted
# So this requires ALL of:
#   1. position at the very start of the output (the phrase can legitimately
#      appear mid-transcript — "document our thinking process: first we scope"),
#   2. an optional bare "thought" marker, which is what gemma-4 leaves behind
#      once "<|channel>" has been removed,
#   3. the heading itself, and
#   4. structured-reasoning evidence immediately after — a numbered/bulleted
#      list or bold markdown. Models lay reasoning out that way; dictation does
#      not.
# A bare "Reasoning:" heading is intentionally NOT matched: someone dictating
# notes could plausibly open with it.
_REASONING_HEADING_RE = re.compile(
    r"\A\s*"
    r"(?:thought\s*|thinking\s*)?"          # gemma-4 residue after <|channel>
    r"(?:thinking|thought)\s+process\s*:"   # the heading
    r"\s*(?:\d+[.)]|[-*]\s|\*\*)"           # structured-reasoning evidence
    r".*",
    flags=re.DOTALL | re.IGNORECASE,
)


def sanitize_model_output(generated: str) -> str:
    """Strip reasoning preambles and control tokens from raw model output.

    Deliberately conservative. Returning an EMPTY string is a useful outcome —
    `correct()` treats that as "the model produced only reasoning" and retries
    with thinking disabled, which is exactly the right recovery. Guessing at an
    answer buried inside a truncated reasoning dump would be worse.

    NOT handled, on purpose: models that emit several alternative answers
    ("… | less\\n\\nAlternatively, for a more concise version:\\n…"). There is no
    safe way to pick one — "Alternatively," is also a perfectly ordinary thing to
    dictate, so truncating there would corrupt real transcripts. That behaviour
    is a model-quality problem and is why Phi-3.5-mini is not in the catalog.
    """
    if not generated:
        return ""

    # 1. Complete <think>…</think> blocks.
    cleaned = re.sub(r"<think>.*?</think>", "", generated, flags=re.DOTALL)
    # 2. Unterminated <think> (model hit max_tokens mid-thought).
    cleaned = re.sub(r"<think>.*", "", cleaned, flags=re.DOTALL)
    # 3. Control tokens, including gemma-4's "<|channel>" reasoning marker.
    cleaned = _SPECIAL_TOKEN_RE.sub("", cleaned)
    # 4. A leading bare-text reasoning heading and everything after it.
    cleaned = _REASONING_HEADING_RE.sub("", cleaned)

    return cleaned.strip().strip('"').strip("'").strip()


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

    cleaned = sanitize_model_output(generated)

    # If result is empty (all thinking, no answer), retry with thinking disabled
    if not cleaned:
        try:
            chat_prompt_no_think = _require_str(
                tokenizer.apply_chat_template(
                    messages, tokenize=False, add_generation_prompt=True, enable_thinking=False
                ),
                "tokenizer.apply_chat_template",
            )
            generated = _safe_generate(model, tokenizer, chat_prompt_no_think, max_tokens)
            if generated.startswith(chat_prompt_no_think):
                generated = generated[len(chat_prompt_no_think):]
            cleaned = sanitize_model_output(generated)
        except Exception:
            # Bug fix: Return original text if fallback fails instead of empty string
            cleaned = text

    # Bug fix: Also return original text if still empty after retries
    if not cleaned:
        cleaned = text

    return {"success": True, "text": cleaned}

