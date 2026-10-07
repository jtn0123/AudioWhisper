# Excluded Cohere adapter attempt

The initial model conversion was
`mlx-community/cohere-transcribe-03-2026-mlx-8bit`, revision
`a0acb7f93cd32d82c4fbf801b6d8fb39d20c509f`, nested `mlx-int8`.

The harness initially loaded it through `mlx-audio 0.5.7`. It loaded without a
runtime exception but produced long mixed-language nonsense on English clips.
This was a **benchmark integration failure**, not evidence of Cohere's intrinsic
accuracy. Those results were excluded from scoring and the charts.

The conversion's [own model card](https://huggingface.co/mlx-community/cohere-transcribe-03-2026-mlx-8bit)
specifies [AppAutomaton's mlx-speech](https://github.com/appautomaton/mlx-speech)
and `CohereAsrModel.from_path` rather than the mlx-audio adapter. That documented
loader applies strict checkpoint loading and inference mode. The runner now uses
`mlx-speech 0.5.3` in an isolated Python 3.13 environment for this conversion.

The corrected full run completed all 68 quality cases, produced meaningful
English, processed the speed composite in a median 1.78 seconds, and returned
empty output on all three non-speech fixtures. The same weights/revision and
audio were used; the documented runtime resolved the failure. No library/app
source, permissions, or weight files were patched to obtain the result.

The excluded raw attempt remains at
`~/Library/Caches/AudioWhisperBench/2026-10-05/cohere-incompatible-runtime.jsonl`.
It is outside the ranked `raw/` artifacts. Native Whisper's initially quiet log
was also checked with a process sample: it was loading/transcribing through
Core ML, and completed normally; it was not treated as an application crash.
