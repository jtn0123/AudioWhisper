#!/usr/bin/env python3
"""Benchmark one MLX correction model against AudioWhisper's actual task.

Measures what matters for THIS app, not generic LLM benchmarks:

  * load time            — storage-dependent, reported separately so it does not
                           contaminate the model-to-model comparison
  * generation latency   — the comparison metric (weights are already resident;
                           mlx_lm.load is non-lazy)
  * safeMerge acceptance — CRITICAL. SemanticCorrectionService.safeMerge rejects
                           any correction whose normalised edit distance from the
                           original exceeds 0.6, and silently returns the RAW
                           transcript instead. A model that rewrites too much is
                           therefore useless in this app no matter how good the
                           prose is. Reimplemented here exactly as Swift does it.
  * defect repair        — did the seeded errors actually get fixed
  * term preservation    — did required technical terms survive
  * think-tag leakage    — Qwen3 thinking models emit <think> blocks

Usage:  bench.py <hf-repo-id>
Appends a JSON record to results/results.jsonl
"""
from __future__ import annotations

import json
import pathlib
import sys
import time

RESULTS = pathlib.Path(__file__).parent / "results"
RESULTS.mkdir(exist_ok=True)

# ---------------------------------------------------------------- app prompts
# Copied verbatim from Sources/Models/CategoryDefinition.swift so the models are
# judged on the instructions they will actually receive in production.
TERMINAL_PROMPT = """Clean up this speech transcription for a terminal/command-line context.
- Fix typos, grammar, and punctuation while preserving command structure
- Remove filler words (um, uh, like, you know)
- Preserve technical terms: CLI, sudo, grep, awk, sed, bash, zsh, tmux, vim, git, ssh, curl, wget, ls, cd, rm, mkdir, echo, apt, brew
- Preserve app names: Ghostty, iTerm, Kitty, Wezterm, Hyper
- Preserve flags, paths, syntax, and multi-line elements (e.g., -v, --verbose, ~/Documents, |, >, &&, $VAR, \\ for line continuation)
- Infer and correct common homophones, misrecognitions, or fragments based on context (e.g., 'eye term' -> 'iTerm', 'suit oh' -> 'sudo', 'see dee' -> 'cd', incomplete 'pipe to' -> '|')
Output only the corrected text."""

EMAIL_PROMPT = """Clean up this speech transcription for email composition.
- Fix typos, grammar, and punctuation for professional tone
- Remove filler words (um, uh, like, you know)
- Preserve key elements: greetings (e.g., Hi [Name]), sign-offs (e.g., Best regards), attachments mentions
- Improve sentence structure for politeness and clarity if needed
- Infer and correct common homophones or misrecognitions based on context (e.g., 'sand' -> 'send', 'attach meant' -> 'attachment')
- Handle fragmented thoughts by forming coherent paragraphs
- Do not add or invent content; keep original intent
Output only the corrected text."""

GENERAL_PROMPT = """Clean up this speech transcription for general use.
- Fix typos, grammar, and punctuation appropriately
- Remove filler words (um, uh, like, you know)
- Preserve any technical or informal terms based on context
- Infer and correct common homophones or misrecognitions (e.g., 'weather' -> 'whether')
- Handle fragments by connecting logically without adding content
- Adapt tone to inferred context (casual or formal)
- Do not add or invent ideas; keep original intent
Output only the corrected text."""

# ------------------------------------------------------------------ test set
# Realistic raw dictation: no punctuation, filler words, and the exact homophone
# classes the prompts call out. `must_fix` / `must_keep` are checked
# case-insensitively against the output. `must_drop` are filler words that a
# correct pass removes.
CASES = [
    {
        "id": "terminal_homophones",
        "prompt": TERMINAL_PROMPT,
        "text": "um so run suit oh apt update and then uh see dee into tilde slash "
                "documents and like grep dash v for the error you know then pipe to less",
        "must_fix": ["sudo", "cd"],
        "must_keep": ["apt", "grep", "less"],
        "must_drop": ["um ", " uh ", "you know"],
    },
    {
        "id": "terminal_flags_paths",
        "prompt": TERMINAL_PROMPT,
        "text": "open eye term and uh run git status then git commit dash m quick fix "
                "and um push to origin master",
        "must_fix": ["iterm"],
        "must_keep": ["git", "commit", "origin"],
        "must_drop": [" uh ", " um "],
    },
    {
        "id": "email_homophones",
        "prompt": EMAIL_PROMPT,
        "text": "hi sarah um i wanted to sand you the quarterly report the attach meant "
                "should be there uh let me know if you like need anything else best regards justin",
        "must_fix": ["send", "attachment"],
        "must_keep": ["sarah", "quarterly", "best regards", "justin"],
        "must_drop": ["um ", " uh "],
    },
    {
        "id": "general_run_on",
        "prompt": GENERAL_PROMPT,
        "text": "so i was thinking we should um check the weather or not the deploy went "
                "through because you know last time it like failed silently and nobody noticed "
                "until the next morning",
        "must_fix": ["whether"],
        "must_keep": ["deploy", "failed"],
        "must_drop": ["um ", "you know"],
    },
    {
        "id": "general_short",
        "prompt": GENERAL_PROMPT,
        "text": "uh remind me to call the dentist tomorrow morning",
        "must_fix": [],
        "must_keep": ["dentist", "tomorrow"],
        "must_drop": ["uh "],
    },
    {
        "id": "general_long",
        "prompt": GENERAL_PROMPT,
        "text": ("okay so um the plan for next week is basically we finish the migration on "
                 "monday and then uh tuesday we run the full regression suite and if that's "
                 "green we like ship on wednesday but i want to you know hold a buffer day "
                 "on thursday just in case something breaks in production and then friday "
                 "we do the retro and write up what we learned um and also we should "
                 "probably update the runbook because the last one is way out of date"),
        "must_fix": [],
        "must_keep": ["migration", "regression", "retro", "runbook"],
        "must_drop": ["um ", " uh ", "you know"],
    },
]


# ----------------------------------------------------- app-identical safeMerge
def normalized_edit_distance(a: str, b: str) -> float:
    """Port of SemanticCorrectionService.normalizedEditDistance (two-row DP)."""
    if a == b:
        return 0.0
    if not a or not b:
        return 1.0
    shorter, longer = (a, b) if len(a) <= len(b) else (b, a)
    prev = list(range(len(shorter) + 1))
    cur = [0] * (len(shorter) + 1)
    for i in range(1, len(longer) + 1):
        cur[0] = i
        for j in range(1, len(shorter) + 1):
            cost = 0 if longer[i - 1] == shorter[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        prev, cur = cur, prev
    return prev[len(shorter)] / max(len(a), len(b))


SAFE_MERGE_LENGTH_CAP = 4000
MAX_CHANGE_RATIO = 0.6


def safe_merge_accepts(original: str, corrected: str) -> tuple[bool, float]:
    """Port of SemanticCorrectionService.safeMerge. Returns (accepted, ratio).

    Returns False when the app would DISCARD the correction and paste the raw
    transcript instead — the failure mode that matters most here.
    """
    if not corrected:
        return False, 1.0
    if max(len(original), len(corrected)) > SAFE_MERGE_LENGTH_CAP:
        denom = max(len(original), len(corrected))
        delta = abs(len(original) - len(corrected)) / denom
        return delta <= MAX_CHANGE_RATIO, delta
    ratio = normalized_edit_distance(original, corrected)
    return ratio <= MAX_CHANGE_RATIO, ratio


def strip_think(text: str) -> tuple[str, bool]:
    """The app strips <think> blocks; mirror that and report whether any leaked."""
    leaked = "<think>" in text.lower()
    if leaked:
        lowered = text.lower()
        end = lowered.rfind("</think>")
        if end != -1:
            text = text[end + len("</think>"):]
    return text.strip(), leaked


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: bench.py <hf-repo-id>", file=sys.stderr)
        return 2
    repo = sys.argv[1]

    # Use the APP'S OWN correction module, not a reimplementation. The first
    # version of this harness rolled its own generate+strip and unfairly failed
    # every thinking model: production also strips INCOMPLETE <think> blocks and,
    # when that leaves nothing, retries with enable_thinking=False. Benchmarking
    # an approximation of the app would have produced a confidently wrong
    # recommendation.
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    from ml.loader import load_correction_model
    from ml import correction as app_correction

    print(f"[{repo}] loading…", flush=True)
    t0 = time.perf_counter()
    load_correction_model(repo)          # warms the module-level cache
    load_seconds = time.perf_counter() - t0
    print(f"[{repo}] loaded in {load_seconds:.1f}s", flush=True)

    results = []
    for case in CASES:
        t0 = time.perf_counter()
        outcome = app_correction.correct(repo, case["text"], case["prompt"])
        gen_seconds = time.perf_counter() - t0

        out = (outcome.get("text") or "").strip()
        # Production returns the ORIGINAL text when every attempt yields nothing.
        # That is a silent no-op, so score it as such rather than as a perfect
        # zero-edit correction.
        no_op = (out == case["text"].strip())

        accepted, ratio = safe_merge_accepts(case["text"], out)
        low = out.lower()

        fixed = [t for t in case["must_fix"] if t.lower() in low]
        kept = [t for t in case["must_keep"] if t.lower() in low]
        remaining_filler = [f for f in case["must_drop"] if f.lower() in low]

        results.append({
            "case": case["id"],
            "input": case["text"],
            "output": out,
            "raw_output": None,
            "gen_seconds": round(gen_seconds, 3),
            "output_tokens": None,
            "tokens_per_sec": None,
            "returned_input_unchanged": no_op,
            "safemerge_accepted": accepted,
            "safemerge_ratio": round(ratio, 4),
            "defects_fixed": f"{len(fixed)}/{len(case['must_fix'])}",
            "defects_missed": [t for t in case["must_fix"] if t not in fixed],
            "terms_kept": f"{len(kept)}/{len(case['must_keep'])}",
            "terms_lost": [t for t in case["must_keep"] if t not in kept],
            "filler_remaining": remaining_filler,
            "think_leaked": "<think>" in low,
            "length_ratio": round(len(out) / max(1, len(case["text"])), 3),
        })
        flag = "NO-OP" if no_op else ("OK " if accepted else "REJECTED-BY-SAFEMERGE")
        print(f"  {case['id']:24} {gen_seconds:6.2f}s  ratio={ratio:.3f} {flag}", flush=True)

    total_fix_possible = sum(len(c["must_fix"]) for c in CASES)
    total_fixed = sum(int(r["defects_fixed"].split("/")[0]) for r in results)
    total_keep_possible = sum(len(c["must_keep"]) for c in CASES)
    total_kept = sum(int(r["terms_kept"].split("/")[0]) for r in results)

    record = {
        "repo": repo,
        "load_seconds": round(load_seconds, 2),
        "summary": {
            "cases": len(results),
            "safemerge_accepted": sum(1 for r in results if r["safemerge_accepted"]),
            "mean_gen_seconds": round(sum(r["gen_seconds"] for r in results) / len(results), 2),
            "max_gen_seconds": round(max(r["gen_seconds"] for r in results), 2),
            "returned_input_unchanged": sum(1 for r in results if r["returned_input_unchanged"]),
            "defects_fixed": f"{total_fixed}/{total_fix_possible}",
            "terms_kept": f"{total_kept}/{total_keep_possible}",
            "cases_with_filler_left": sum(1 for r in results if r["filler_remaining"]),
            "think_leaks": sum(1 for r in results if r["think_leaked"]),
        },
        "cases": results,
    }

    with (RESULTS / "results.jsonl").open("a") as handle:
        handle.write(json.dumps(record) + "\n")

    s = record["summary"]
    print(f"\n[{repo}] SUMMARY")
    print(f"  load {load_seconds:.1f}s | mean gen {s['mean_gen_seconds']}s "
          f"| max {s['max_gen_seconds']}s | no-ops {s['returned_input_unchanged']}/{s['cases']}")
    print(f"  safeMerge accepted {s['safemerge_accepted']}/{s['cases']} "
          f"| defects fixed {s['defects_fixed']} | terms kept {s['terms_kept']}")
    print(f"  filler left in {s['cases_with_filler_left']} cases | think leaks {s['think_leaks']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
