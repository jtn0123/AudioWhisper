"""Explicit, word-weighted ASR scoring and separate entity preservation checks."""
from __future__ import annotations

import re
from typing import Iterable

import jiwer
from transformers.models.whisper.english_normalizer import EnglishTextNormalizer

_NORMALIZER = EnglishTextNormalizer({})


def normalize(text: str) -> str:
    # Whisper-style English number/contraction normalization. British/American
    # spelling mappings are deliberately not added; record this in the report.
    text = text.translate(str.maketrans({"’": "'", "‘": "'"}))
    return " ".join(_NORMALIZER(text).split())


def error_counts(reference: str, hypothesis: str) -> dict:
    result = jiwer.process_words(normalize(reference), normalize(hypothesis))
    return {
        "reference_words": result.hits + result.substitutions + result.deletions,
        "hits": result.hits,
        "substitutions": result.substitutions,
        "deletions": result.deletions,
        "insertions": result.insertions,
        "errors": result.substitutions + result.deletions + result.insertions,
    }


def aggregate_counts(rows: Iterable[dict]) -> dict:
    rows = list(rows)
    keys = ["reference_words", "hits", "substitutions", "deletions", "insertions", "errors"]
    totals = {key: sum(row[key] for row in rows) for key in keys}
    totals["wer_percent"] = (
        100 * totals["errors"] / totals["reference_words"]
        if totals["reference_words"] else None
    )
    return totals


def meaning_normalize(text: str) -> str:
    # Standard WER strips bracketed annotations. Meaning checks must retain
    # their contents. Its number normalizer can also lose the word "negative"
    # in a spoken currency amount, so protect that word before normalization.
    value = re.sub(r"[()\[\]]", " ", text)
    value = re.sub(r"\bnegative\b", "awnegativepolarity", value, flags=re.I)
    return normalize(value).replace("awnegativepolarity", "negative")


def required_terms_retained(text: str, required: list[str], aliases: dict | None = None) -> dict:
    normalized = meaning_normalize(text)
    kept = [term for term in required if re.search(
        r"(?<!\w)" + re.escape(meaning_normalize(term)) + r"(?!\w)", normalized
    ) or any(re.search(r"(?<!\w)" + re.escape(meaning_normalize(alias)) + r"(?!\w)", normalized)
             for alias in (aliases or {}).get(term, []))]
    return {"kept": kept, "missing": [term for term in required if term not in kept]}
