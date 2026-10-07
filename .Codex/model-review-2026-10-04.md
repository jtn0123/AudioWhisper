# AudioWhisper model review — English first

**Reviewed:** 2026-10-04
**App code:** `187eacdb55737ba8eb6b57c9bb59f5e0cc23c506`
**Purpose:** Local, private Mac dictation and optional text cleanup. Multilingual
models compete on their English results; multilingual capability is a benefit,
not a reason to exclude them.

## Decision

The current lineup is sensible, but **“best available for English” is not
established**. Keep **Parakeet v2 as the provisional English recommendation
among current Apple Silicon choices**, keep v3 for multilingual use, and retain
Whisper as the existing Intel/Core ML alternative. Do not silently migrate users
or label a newer model the winner without app-specific comparison.

**Next speech-model evaluation order:** **Granite Speech 5.0 470M TurboCTC
(Apache variant) → Cohere Transcribe → Qwen3-ASR 1.7B**. This ranks evaluation
priority for this app, not proven Mac accuracy or latency. Granite is the most
interesting compact English challenger; Cohere is a strong English-accuracy
challenger with multilingual support; Qwen is particularly attractive when
English dictation and broader language coverage share one engine.

For writing, **keep Qwen3-4B-Instruct-2507-4bit provisionally**. The existing
app-specific benchmark supports it more directly than generic language-model
leaderboards, but that benchmark is small and historical. Fix text preservation
and rerun the current pipeline before adding a newer default.

## What the rebuild actually offers

| Role | Current option | Status and assessment |
|---|---|---|
| Speech | Parakeet TDT 0.6B v2 | Selectable; English-only; strongest starting choice for English among current Parakeet options |
| Speech | Parakeet TDT 0.6B v3 | Selectable; new Apple Silicon install default; 25 languages; keep for multilingual needs |
| Speech | Whisper large-v3-turbo | Selectable; practical larger-model Core ML alternative on supported Macs; measure actual resource cost |
| Speech | Whisper small | Selectable; lower-resource quality compromise; not an accuracy-first recommendation without local comparison |
| Speech | Whisper base | Selectable; default Whisper selection/Intel initial fallback; native VM inference demonstrated, not a quality winner |
| Speech | Whisper tiny | Selectable; resource-focused option; should not be sold as best English quality |
| Speech | Parakeet TDT/CTC 110M | Present in enum, pins and services, **absent from the rebuilt model picker**; not a user-selectable rebuilt option today |
| Writing | Qwen3-4B-Instruct-2507-4bit | Current default model when optional cleanup is enabled; provisional best general cleanup choice in this catalogue |
| Writing | Gemma 3 1B IT QAT 4bit | Selectable; fast/light cleanup alternative with weaker historical mistake correction |
| Writing | Qwen3 1.7B 4bit | Selectable; smaller than the 4B default, but historical generation was slower and correction weaker |

Cleanup itself defaults **off**. Default-model selection is separate from
whether cleanup runs. Existing users may retain a previous installed cleanup
model through migration rather than being forced to redownload.

Inventory evidence: `Sources/Rebuild/RebuildModelsView.swift:36`,
`Sources/Models/TranscriptionTypes.swift:28`,
`Sources/Models/WhisperModel+WhisperKit.swift:1`,
`Sources/Rebuild/RebuildApp.swift:74`,
`Sources/Stores/AppDefaults+Settings.swift:22` and `:63`,
`Sources/Services/MLXModelManager.swift:58`,
`Sources/Models/ModelPins.swift:28`.

Whisper currently uses the multilingual tiny/base/small/turbo checkpoints,
`task = .transcribe` and automatic language detection. It does **not** offer
`.en` tiny/base/small variants or a user-selected English language preset
(`Sources/Services/LocalWhisperService.swift:182`). The visible MB/GB labels are
static estimates inherited from single-file model metadata; production uses
Argmax Core ML bundles. Those labels are not measured installed bytes or Mac
peak memory.

## Ranked new speech candidates

| Priority | Candidate | Why evaluate it | Main integration/quality question |
|---|---|---|---|
| 1 | [IBM Granite Speech 5.0 470M TurboCTC](https://huggingface.co/ibm-granite/granite-speech-5.0-470m-turboctc) | Compact English encoder-only model; Apache 2.0 variant; current Apple Silicon MLX support | Compare short dictation, noise, names/numbers, long-form boundaries, actual latency/RAM and punctuation against Parakeet |
| 2 | [Cohere Transcribe 03-2026](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026) | 2B dedicated recognizer; strong published English results; 14 languages | Specify language; test silence/VAD carefully. No native diarization or word timestamps; original repository currently requires HF access acceptance |
| 3 | [Qwen3-ASR 1.7B](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) | Strong English evidence plus 30-language support and English-accent coverage; offline/streaming modes | Test the actual MLX conversion, quantization, long-form handling, startup and memory; compare its 0.6B sibling if resources dominate |
| 4 | [NVIDIA Canary-Qwen 2.5B](https://huggingface.co/nvidia/canary-qwen-2.5b) | Strong English benchmark reference | Dedicated NeMo/SALM path is a larger departure from the app's current runtime; exact Mac deployment support needs a separate spike |
| 5 | [Moonshine Streaming Medium](https://huggingface.co/moonshine-ai/moonshine-streaming-medium) | 245M English model targeting constrained devices and live output | Benchmark shipping quantized/runtime variants; useful lightweight challenger, not a published accuracy upgrade over every larger model |

Granite, Cohere and Qwen each have Apple Silicon implementations in
[mlx-audio](https://github.com/Blaizzy/mlx-audio), including dedicated
[Granite](https://github.com/Blaizzy/mlx-audio/blob/main/mlx_audio/stt/models/granite_speech5_ctc/README.md)
and [Cohere](https://github.com/Blaizzy/mlx-audio/blob/main/mlx_audio/stt/models/cohere_asr/README.md)
documentation. They are **not drop-in replacements** for the app's
`parakeet-mlx` calls. AudioWhisper needs a provider adapter, pinned assets/runtime,
verification, offline setup, cancellation, bounded long-audio handling and
delivery tests. The current frozen project does not contain that integration
(`Sources/Resources/pyproject.toml`).

The Granite `-nc` sibling has a different noncommercial license. The Apache
variant is the appropriate first candidate for this app's general distribution
path; do not quietly replace it with the differently licensed checkpoint.
[IBM's model/runtime documentation](https://raw.githubusercontent.com/Blaizzy/mlx-audio/main/mlx_audio/stt/models/granite_speech5_ctc/README.md)
distinguishes the two.

## What the published English numbers actually show

WER means **word error rate**: substitutions, missing words and inserted words
relative to reference speech. Lower is better. It is not a simple guaranteed
“percent accurate” value for your microphone, and insertions can make WER exceed
100%. Published GPU throughput is not Mac dictation latency.

| Benchmark group | Model | Published mean WER | Interpretation |
|---|---|---|---|
| NVIDIA's matched eight English sets | [Parakeet v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) | 6.05% | Slightly better aggregate English result than v3 in these model-card tables |
| Same NVIDIA set descriptions | [Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) | 6.34% | Multilingual capability has a small aggregate English tradeoff here |
| Cohere's March 26 comparison table | [Cohere Transcribe](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026) | 5.42% | Strong offline English candidate in that dated comparison |
| Same Cohere comparison table | [Canary-Qwen 2.5B](https://huggingface.co/nvidia/canary-qwen-2.5b) | 5.63% | Strong reference; integration fit still matters |
| Same Cohere comparison table | [Qwen3-ASR 1.7B](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) | 5.76% | Strong multilingual candidate with competitive English results |
| IBM's newer public English short-form benchmark | [Granite 5.0 Apache variant](https://huggingface.co/blog/ibm-granite/granite-speech-5-0-470m-turboctc) | 5.00% | Promising, but the benchmark includes changed chunked Earnings22 evaluation; do not subtract this directly from older averages |
| Moonshine publisher's eight-set table | [Moonshine Streaming Medium](https://huggingface.co/moonshine-ai/moonshine-streaming-medium) | 6.65% | Compact English streaming tradeoff; evaluate actual quantized deployment |

These are publisher-reported results and dated snapshots, not a single fresh
head-to-head run. Even similarly named test sets can change segmentation,
normalization or private/public composition. The rankings above therefore use
English evidence **and app fit**, without claiming a measured Mac winner.

Parakeet v2's advantage is not universal: NVIDIA's 0 dB noisy-set aggregate is
slightly better for v3 (11.66% versus 11.88% for v2). The practical recommendation
is to offer English guidance and test both on the same representative noisy
audio, rather than remove v3. [NVIDIA's v3 card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
contains that comparison.

## Whisper: retain the alternative, improve the English choices

[OpenAI's Whisper documentation](https://github.com/openai/whisper) says English
`.en` models tend to help, particularly at tiny/base sizes. AudioWhisper should
evaluate `base.en`/`small.en` and an English decoding preset while retaining Auto
language mode and multilingual checkpoints. This could improve the existing
Intel-compatible route without introducing an entirely new engine. It still
needs confirmation that the selected Argmax Core ML asset/runtime combination
is available and works on supported hardware.

[Distil-Whisper large-v3.5](https://huggingface.co/distil-whisper/distil-large-v3.5)
is another English candidate, but it is not an unconditional upgrade: its
publisher's own comparison reports 7.08% versus turbo's 7.30% on short out-of-
distribution speech, while long-form WER is 11.39% versus turbo's 10.25%.
The reported relative speed also belongs to that benchmark, not this Mac app.
WhisperKit/Core ML availability for that exact checkpoint was not established
here, so it is behind the first three candidates in integration priority.

## Live streaming and native-runtime alternatives

For the current stop-then-transcribe workflow, streaming latency alone should
not decide the default. If live text/captions become a feature, evaluate
[Nemotron Speech Streaming English 0.6B](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b),
Moonshine, and [Voxtral Mini 4B Realtime](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602).
Voxtral's open realtime model supports 13 languages; it is different from the
cloud-only Voxtral transcription product.

[Nemotron 3.5 multilingual](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)
advertises 40 locales, but 32 transcribe out of the box and eight need adaptation.
Its own card recommends the English-specific model for English-only use. Do not
present “40 languages” as forty immediately working transcription choices.

Two implementation options deserve separate consideration from model accuracy:

- [FluidAudio](https://github.com/FluidInference/FluidAudio) offers a Swift/Core ML Parakeet path. Using the same model through a native runtime could reduce Python setup complexity; that is an integration proposal, not evidence of better recognition.
- [Apple SpeechAnalyzer/SpeechTranscriber](https://developer.apple.com/videos/play/wwdc2025/277/) provides on-device transcription with system-managed model assets on newer Apple platforms. Evaluate hardware/locale/API availability and English quality before adoption, and retain the macOS 14 fallback. It would not automatically remove OS microphone consent.

## Writing models: quality before a catalogue refresh

The optional writer is **text → text**, separate from the speech model. It can
repair spelling/homophones and format app-specific writing, but cannot recover
words missing from its input with certainty. Recognition and cleanup should be
scored separately so plausible rewriting does not hide ASR mistakes.

Historical app benchmark, **2026-07-31**, six seeded text cases across actual
Terminal/Email/General prompts:

| Rank/use | Current model | Mean generation | Homophone cases fixed | Required terms kept | Filler remained | Historical guard acceptance |
|---|---|---|---|---|---|---|
| 1 / general quality | Qwen3 4B Instruct 2507 4bit | 1.64 s | 5/6 | 18/18 | 0/6 | 5/6 |
| 2 / low delay | Gemma 3 1B IT QAT 4bit | 0.71 s | 2/6 | 18/18 | 4/6 | 6/6 |
| 3 / smaller Qwen | Qwen3 1.7B 4bit | 2.90 s | 3/6 | 18/18 | 1/6 | 6/6 |

Evidence: `.claude/bench/README.md`, `bench.py`, `correction-model-results.jsonl`.
These are one-machine historical generation timings, not today's end-to-end
dictation delay. They exclude recognition, and cold model loading adds time.
The Qwen 4B rejection was a legitimate Terminal compression rejected by the old
flat threshold; the current code uses category-specific thresholds. Output
parsing has also changed. Consequently, the old rejected counts for Qwen3.5 4B
and Gemma 4 E2B do **not** prove they fail the current pipeline.

[Qwen3 4B Instruct 2507](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507)
is a non-thinking variant, a useful fit for short corrections. Keep it as the
provisional default while retesting current parsing/guards on many more cases.
Include [Qwen3.5 2B/4B](https://huggingface.co/Qwen/Qwen3.5-2B),
[Gemma 4 E2B](https://huggingface.co/google/gemma-4-E2B-it), and
[LFM2.5 1.2B Instruct](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct)
as challengers where the runtime supports the exact conversion. Generic
reasoning or coding scores are insufficient to replace an app-specific writer.

## Required comparison before changing the default

1. Fix codebase **B1/B2**: preserve real bracketed words and compare long correction content. Carry original/final text separately (**B3**).
2. Start with a reproducible licensed English corpus: conversational dictation, multiple accents, background noise, technical names, dates/money/numbers, silence, short clips and long recordings. Keep a small multilingual subset for retained multilingual choices.
3. Run the same audio through current Parakeet v2/v3 and Whisper turbo/base, then Granite, Cohere and Qwen adapters. Record exact revision, quantization, decoder/language/VAD settings and runtime.
4. Measure raw WER, silence insertions, entity/number mistakes, long-form loss/duplication, cold start, time after Stop, peak memory and installed/download bytes. Use both an 8 GB-class Apple Silicon baseline and a stronger Mac; VM behavior complements physical hardware evidence.
5. Run cleanup separately on identical raw transcripts. Score preserved meaning/terms/numbers, desired formatting, reasoning leakage, guard fallback, warm/cold delay and restore-original behavior. Do not award accuracy for invented but plausible text.
6. Change an English recommendation/default only after the measured benefit justifies memory, setup and maintenance cost. Preserve explicit user selections and multilingual/Intel alternatives.

**Plain meaning:** The speech engine decides what it heard. The writing engine
edits those words. We need to prove both are good at their own job, on the same
examples, before calling a newer model an upgrade.

No new candidate was downloaded, installed or benchmarked in AudioWhisper during
this research pass, and no model selection/default was changed.
