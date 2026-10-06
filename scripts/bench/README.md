# Local English model benchmark

This runs inference on public audio and fabricated text. It does not launch the
app, record a microphone, change TCC permissions, or change model defaults.
Current Parakeet and writing options use the unchanged production Python code
and app environment. Whisper uses the production WhisperKit version and default
compute/decode settings. Challengers use isolated, explicitly versioned runtimes.

## What is measured

- One fresh process: load time and time until the first short transcript, with
  downloaded model files present. OS file/compiled-model caches are not purged.
- Warm speed: one warmup and five repeats of the same 61.285-second composite.
- English quality: word-weighted word error rate over 48 natural clips, sampled
  across LibriSpeech test-clean, test-other, and AMI headset meetings.
- Separate diagnostics: eight clips with added 10 dB white noise; eight synthetic
  name/number/negation dictations; three silence/noise-only clips; a 180.41-second
  natural-speech composite.
- Writing: 28 independent tasks across six actual app profile prompts, twice,
  using production temperature/retry behavior and fixed per-case random seeds.
  Scoring applies the actual Swift safety guard extracted from source. It checks
  repairs, retained terms, fillers, and command punctuation. Passing those checks
  is not proof of complete semantic correctness or a full grammar evaluation.
  The retained report also has a qualitative review of all delivered outputs,
  with specific failure reasons. `report.py` checks the output hashes before
  reusing those labels; changed outputs require a new review.
- Memory: process peak RSS and, for MLX, peak allocation measured separately.
  They are not additive, and RSS does not include all Core ML service memory.

`scoring.py` uses Transformers' Whisper English normalizer plus JiWER. WER ignores
case, punctuation, fillers, and bracketed annotations; number formatting can
still create misleading errors. Separate meaning checks preserve bracket text
and spoken negative amounts, with narrow clock/date aliases. Synthetic WER is
retained for inspection but is not used to select a model. Public-test training
exposure and the small sampled set limit generalization. This is a deployment
comparison on one Mac, not a new global leaderboard.

## Reproduce on this Mac

Use the recorded requirements files in the report directory. All downloads,
generated audio, venvs and Swift build products belong outside the repository.
The persistent cache permits a second run on identical WAV files; their hashes
and source URLs are retained in `corpus-manifest.json`.

```sh
BENCH_BASE="$HOME/Library/Caches/AudioWhisperBench/2026-10-05"
uv venv --python 3.11 "$BENCH_BASE/.venv"
uv pip install --python "$BENCH_BASE/.venv/bin/python" -r .Codex/bench/2026-10-05-m5-pro/requirements-bench.txt
uv venv --python 3.13 "$BENCH_BASE/.cohere-venv"
uv pip install --python "$BENCH_BASE/.cohere-venv/bin/python" -r .Codex/bench/2026-10-05-m5-pro/requirements-cohere.txt
"$BENCH_BASE/.venv/bin/python" scripts/bench/prepare.py "$BENCH_BASE" corpus
"$BENCH_BASE/.venv/bin/python" scripts/bench/prepare.py "$BENCH_BASE" models
source scripts/lib/xcode-env.sh
ensure_xcode_toolchain
swift build -c release --package-path scripts/bench/native-whisper --scratch-path "$BENCH_BASE/swift-build"
"$BENCH_BASE/.venv/bin/python" scripts/bench/run.py "$BENCH_BASE"
"$BENCH_BASE/.venv/bin/python" scripts/bench/postprocess.py "$BENCH_BASE"
"$BENCH_BASE/.venv/bin/python" scripts/bench/report.py "$BENCH_BASE" .Codex/bench/2026-10-05-m5-pro
"$BENCH_BASE/.venv/bin/python" -m pytest -q --cov=scoring scripts/bench/test_scoring.py
```

Completed successful results are skipped. For a fresh timing run, archive the
`results` directory, keeping the corpus and pinned model cache. `--only MODEL_ID`
limits a run. Runs are sequential to avoid GPU contention. Each model has a
15-minute process timeout; errors and timeouts are retained instead of converted
to accuracy scores. The first incompatible Cohere adapter attempt is retained
separately as harness diagnostics and excluded from the ranked chart.

## Public corpus attribution

- [LibriSpeech](https://huggingface.co/datasets/openslr/librispeech_asr), Panayotov
  et al., via OpenSLR; CC BY 4.0. Both clean/other test splits, 16 clips each.
- [AMI](https://huggingface.co/datasets/edinburghcstr/ami), University of Edinburgh
  Centre for Speech Technology Research; CC BY 4.0. IHM test split, 16 clips.
- Added-noise/composite derivatives are identified in the manifest. Synthetic
  dictation uses macOS Samantha, 165 wpm; it is separate from natural-speech scores.

Model repositories, revisions, runtime versions, raw transcripts, delivered
transcripts, and per-case checks are retained with the report. No weights or
audio files are committed.

## Qwen 3.5 / 3.8 cleanup follow-up

[The 2026-10-06 report](../../.Codex/bench/2026-10-06-qwen/README.md) compares the
current Qwen3 4B Instruct 2507 with Qwen3.5 4B/9B and Qwen3.8 27B. It retains
raw generation traces, the production Swift guard's delivered text, and a manual
review of 64 English stress cases for each complete configuration. Thinking
disabled, exact production behavior, and a stricter experimental prefix are
separate conditions. This does not edit production prompts or model defaults.

```sh
QWEN_BASE="$HOME/Library/Caches/AudioWhisperBench/qwen-fresh-run"
QWEN_PY="$HOME/Library/Caches/AudioWhisperBench/2026-10-05/.venv/bin/python"
"$QWEN_PY" scripts/bench/qwen_prepare.py "$QWEN_BASE"
python3 scripts/bench/qwen_run.py "$QWEN_BASE" --python "$QWEN_PY" --only qwen3-4b qwen3.5-4b qwen3.5-9b
python3 scripts/bench/qwen_run.py "$QWEN_BASE" --python "$QWEN_PY" --only qwen3.8-27b --production-limit 19
python3 scripts/bench/qwen_run.py "$QWEN_BASE" --python "$QWEN_PY" --only qwen3-4b qwen3.5-4b qwen3.5-9b qwen3.8-27b --modes strict
```

Use the follow-up's frozen requirements if creating a fresh runtime. Preparation
reuses only the exact pinned revision, otherwise downloading into this isolated
cache. Runs are sequential, each with a 20-minute timeout. Qwen3.8's production
mode is intentionally limited because its default template is incompatible with
current reasoning sanitization; a fresh bounded run can complete successfully
even though its delivered text is rejected by the app guard.

`qwen_report.py` compiles the actual production Swift helper and writes delivered
outputs before checking the reviewer labels' hashes. Copy the retained
`manual-review.json` only when outputs are identical; fresh or changed outputs
need a new qualitative review using the recorded criteria. After review:

```sh
"$QWEN_PY" scripts/bench/qwen_report.py "$QWEN_BASE"
```

The optional `qwen_runtime_smoke.py` runs one short direct correction per model
using the Python executable supplied by the caller. `--sources` can point at a
read-only installed resource directory. Set `PYTHONDONTWRITEBYTECODE=1`,
`HF_HUB_OFFLINE=1`, and `HF_HUB_DISABLE_IMPLICIT_TOKEN=1` when inspecting an
installed runtime. This is a basic compatibility check, not an app acceptance
test. All weights, binaries, virtual environments, and caches stay outside Git.
