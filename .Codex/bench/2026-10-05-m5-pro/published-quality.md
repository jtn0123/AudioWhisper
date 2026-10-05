# Published English quality references

These are publisher-reported word error rates (WER), checked 2026-10-05. Lower
is better. Each comparison group has its own test composition and date; this
table is not a fresh combined leaderboard. Our local chart measures the actual
Mac deployments, including community quantization and runtime differences.

| Comparison group | Model | Published mean WER | Source |
|---|---|---:|---|
| NVIDIA eight English sets | Parakeet v2 | 6.05% | [NVIDIA v2 card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) |
| Same named NVIDIA sets | Parakeet v3 | 6.34% | [NVIDIA v3 card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) |
| Cohere March 26, 2026 table | Cohere Transcribe | 5.42% | [Cohere publisher card](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026) |
| Same Cohere table | Qwen3-ASR 1.7B | 5.76% | [Cohere table](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026), [Qwen publisher card](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) |
| IBM newer public short-form sets, including changed chunked Earnings22 | Granite 5 Apache | 5.00% | [IBM benchmark article](https://huggingface.co/blog/ibm-granite/granite-speech-5-0-470m-turboctc) |

Cohere's table supports its accuracy potential; its full-precision publisher
results are not proof of a particular 8-bit Mac conversion. IBM's changed
evaluation should not be directly subtracted from older eight-set averages.
Our sample did not establish a general quality win for any challenger.

[Whisper Turbo's publisher card](https://huggingface.co/openai/whisper-large-v3-turbo)
describes pruning the large-v3 decoder from 32 to four layers for faster
inference, with a small quality tradeoff. That design claim does not imply it
beats Parakeet latency on this Mac with the app's Core ML provider.

Writing model cards publish general instruction/knowledge/coding evaluations:
[Qwen3 4B](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507),
[Qwen3.5 2B](https://huggingface.co/Qwen/Qwen3.5-2B),
[LFM2.5](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct),
[Gemma 4](https://huggingface.co/google/gemma-4-E2B-it).
They do not establish faithful dictation cleanup with our six prompts and current
guard. Our task checks plus explicit qualitative review are more applicable to
that question, while remaining small-sample evidence.
