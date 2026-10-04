# Correction-model benchmark — 2026-07-31

Plan item 6 / audit item F4. Benchmarks candidates for the **semantic correction**
catalog (`MLXModelManager.recommendedModels`) — the optional text→text pass that
runs *after* transcription. **Not** speech-to-text; Parakeet and WhisperKit are a
separate role and were not part of this run.

Raw per-case data: `correction-model-results.jsonl` (one JSON record per model,
every input/output retained). Harness: `bench.py` + `run-one.sh`.

## Method

Each model was downloaded to external storage, benchmarked, then deleted before
the next download — peak disk 3.58 GB, and the user's own HF cache (Parakeet)
was never touched.

The harness calls the app's **real** `Sources/ml/correction.py`, not a
reimplementation. This matters: the first version of the harness rolled its own
generate-and-strip and reported the shipping default (Qwen3-1.7B) as 0/6 —
"completely broken". That was wrong. Production also strips *incomplete*
`<think>` blocks and retries with `enable_thinking=False` when stripping leaves
nothing. Re-run against production code: 6/6. The invalid first run is kept as
`results-INVALID-harness-v1.jsonl` on the bench volume.

Six dictation cases across the app's real Terminal / Email / General prompts
(copied verbatim from `CategoryDefinition.swift`), each seeded with the exact
homophone classes those prompts call out (`suit oh`→`sudo`, `sand`→`send`,
`attach meant`→`attachment`, `weather`→`whether`, `eye term`→`iTerm`).

**The decisive metric is safeMerge acceptance.**
`SemanticCorrectionService.safeMerge` discards any correction whose normalised
edit distance from the original exceeds `maxChangeRatio = 0.6` and silently
pastes the RAW transcript. A model can produce excellent text and still be
useless here. The Swift DP is ported exactly in `bench.py`.

## Results

| Model | Size | Load | Mean gen | Max gen | safeMerge | Homophones | Terms | Filler left |
|---|---|---|---|---|---|---|---|---|
| **Qwen3-4B-Instruct-2507-4bit** | 2.28 GB | 7.0s | **1.64s** | 2.94s | 5/6 | **5/6** | 18/18 | **0/6** |
| Qwen3-1.7B-4bit *(current default)* | 0.98 GB | 1.6s | 2.90s | 5.67s | **6/6** | 3/6 | 18/18 | 1/6 |
| gemma-3-1b-it-qat-4bit | 0.77 GB | 1.9s | **0.71s** | 1.17s | **6/6** | 2/6 | 18/18 | 4/6 |
| Llama-3.2-1B-Instruct-4bit *(legacy default)* | 0.71 GB | 1.8s | 1.14s | 2.16s | 3/6 | **0/6** | 16/18 | 2/6 |
| Phi-3.5-mini-instruct-4bit *(catalog "Premium")* | 2.4 GB | 5.5s | 3.19s | 4.51s | **1/6** | 5/6 | 18/18 | 0/6 |
| Qwen3.5-4B-MLX-4bit | 3.06 GB | 7.2s | 5.38s | 10.46s | **0/6** | 2/6 | 18/18 | 6/6 |
| gemma-4-e2b-it-4bit | 3.58 GB | 6.7s | 3.03s | 5.85s | **0/6** | 0/6 | 18/18 | 6/6 |

Newer is emphatically **not** better here. The two newest models scored 0/6.

## Three app bugs this exposed

These are defects in AudioWhisper, not model-quality results.

### 1. The think-stripper only knows one tag format

`correction.py` strips `<think>…</think>` and truncated `<think>…`. But:

* **gemma-4-e2b** emits `<|channel>thought\nThinking Process:…`
* **Qwen3.5-4B** emits bare `Thinking Process:…` with **no tags at all**

Neither is stripped, so raw chain-of-thought lands in the transcript, blows the
edit-distance guard, and the correction is discarded. Both models score 0/6
purely because of this. The retry path never fires either, because stripping
leaves a non-empty string — it just leaves the *wrong* string.

### 2. Chat-template special tokens are not stripped

Phi-3.5-mini's actual correction is **right**:

```
in : uh remind me to call the dentist tomorrow morning
out: Remember to call the dentist tomorrow morning.<|end|><|assistant|> Remember to call the dentist tomorrow morning.<|end|>
```

The correction is correct and then repeated, with `<|end|>` / `<|assistant|>`
tokens attached. That pushes the ratio to **0.6083** — just past the 0.6
threshold — so it is thrown away. Phi ships in the catalog labelled "Premium
quality correction"; anyone selecting it gets corrections silently discarded on
5 of 6 cases.

### 3. safeMerge's 0.6 threshold punishes the Terminal category

The single rejection for the winning model:

```
in : um so run suit oh apt update and then uh see dee into tilde slash documents
     and like grep dash v for the error you know then pipe to less
out: sudo apt update && cd ~/Documents && grep -v error | less
```

That output is **exactly** what the Terminal prompt asks for — homophones
resolved, filler removed, real shell syntax. It is discarded (ratio 0.664)
because good terminal correction legitimately *compresses* rambling dictation
into a terse command. The 0.6 threshold is calibrated for prose and actively
fights the Terminal/Coding categories.

Suggested follow-up: make `maxChangeRatio` per-category (prose ~0.6, terminal
~0.85), or compare against a normalised form rather than raw edit distance.

## Recommendation

**Switch the default and RECOMMENDED model to `mlx-community/Qwen3-4B-Instruct-2507-4bit`.**

* Best correction quality measured: 5/6 homophones, 18/18 terms, filler removed
  in all 6 cases (the only model to manage that)
* 1.8× faster than the current Qwen3-1.7B default (1.64s vs 2.90s mean) despite
  being 2.3× larger — because it is a **non-thinking Instruct** variant and does
  not pay for the think-then-retry round trip
* No reasoning leakage by construction, which is what sank both newer models
* Cost: 2.28 GB vs 0.98 GB, and ~7s first load

Keep **gemma-3-1b-it-qat-4bit** as the low-end option — 0.71s mean is by far the
fastest and it never trips safeMerge, but it only fixes 2/6 homophones and leaves
filler in 4/6. Good "fast and safe", not "good".

**Retire** Phi-3.5-mini (1/6 accepted; its "Premium" label is actively
misleading) and Llama-3.2-1B (0/6 homophones, and the only model that dropped
required terms). Do not add Qwen3.5-4B or gemma-4-e2b until bug #1 is fixed.

Caveat: six synthetic cases, one run, one machine. Directionally solid — the
gaps are large and the failure modes are structural, not marginal — but it is
not a WER-grade study.
