# Qwen app integration — 2026-10-06

The app now offers the two builds chosen from the prior
[quantized-model comparison](../2026-10-06-qwen-quants/README.md):

| Option | Pinned build | Role |
|---|---|---|
| Qwen3.5 9B 4-bit | `mlx-community/Qwen3.5-9B-4bit` | Recommended balanced editor for new installs |
| Qwen3.8 27B mixed 3-bit | `leonsarmiento/Qwen3.8-27B-3bit-mlx` | Optional larger editor |

The old lightweight models remain selectable. Existing explicit selections,
cached prior implicit defaults and the cleanup on/off preference survive an
upgrade. Parakeet selection and recording permissions are not changed by this
integration. Writing profiles shows readable names, a recommendation label,
download size and measured speed/memory guidance.

## Confirmed bugs repaired

- Regression tests failed before the fix: the first generation did not disable
  thinking, a legacy tokenizer lost its chat framing, and valid ending quotes
  were stripped from sentences and shell arguments. Six Python assertions
  failed before the patch and pass afterward. The catalog/default regressions
  also failed before implementation.
- Production now supplies `enable_thinking=False` on the first template call.
  Older tokenizers rejecting that argument retain their normal chat template.
  Empty results receive at most one recovery attempt, then retain the original.
- Sanitization removes reasoning/control tokens without stripping content quotes.
  The existing Swift output guard and profile prompts remain in place.

## Validation

- Full local suite: 3,060 Swift tests and 109 Python tests passed. Strict
  SwiftLint 0.65.1 and mypy passed (CI pins SwiftLint 0.65.0). The final startup
  migration call also passed 20 focused setup/default/startup tests and lint.
- **128 actual production edits:** 64 per model using the app's installed Python
  runtime (MLX 0.32.0, mlx-lm 0.31.3, Transformers 5.10.1). Both completed every
  edit in one generation, with no reasoning-only retries. The actual Swift guard
  retained the source for two 9B edits and three 27B edits. Raw generations,
  delivered outputs, model revisions and source hashes are retained here.
- A real packaged JSON-RPC daemon resolved the models from the shared cache
  offline, corrected grammar and preserved closing quote pairs, and switched
  3.5 → 3.8 → 3.5 successfully. Six requests succeeded. Deep strict signature
  verification passed afterward, with no bytecode cache files in the bundle.
  The model capitalized the quoted sentence; this checks quote integrity, not
  verbatim preservation of every character.
- The Tahoe 26.6.2 QA VM displayed all five model choices, the Qwen3.5
  recommendation and its guidance, and the Qwen3.8 selection/guidance. The 3.8
  selection persisted across a real app relaunch. Screenshots are in `vm-ui/`.
  The guest tested native settings UI; physical Mac tests above exercised MLX.
- The host window-control connector timed out. No host permission changes,
  TCC resets or manual consent requests were used to complete these checks.

This is an integration regression run, **not a new controlled speed ranking or
quality score**. Build and desktop activity overlapped inference; the VM began
booting near the end. Outputs differ from the benchmark's newer runtime, and
meaning omissions and unwanted email formatting still occur. Larger models do
not make the editor infallible; the existing edit-distance guard cannot detect
every semantic error. No new speech, microphone or Smart Paste acceptance run
was needed or claimed for this model-only change.

## Reproduce

After installing the pinned builds into the cache, run with the app's Python:

```sh
python3 scripts/bench/qwen_run.py <new-evidence-directory> \
  --python "$HOME/Library/Application Support/AudioWhisper Rebuild/python_project/.venv/bin/python" \
  --only qwen3.5-9b qwen3.8-27b-3bit --modes production
python3 scripts/bench/postprocess.py <new-evidence-directory>
```

The new evidence directory must contain a `models.json` manifest with the
pinned local snapshot paths; the runner refuses to overwrite an existing run.
Production mode uses the real correction template; generation tracing and the
manifest path resolver are the only instrumentation. Packaged daemon checks
use the real cache resolver and template with no replacements.
