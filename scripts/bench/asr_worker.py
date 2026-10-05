"""One model per process; compare actual current providers with MLX challengers."""
from __future__ import annotations

import time

PROCESS_START = time.perf_counter()

import argparse
import importlib.metadata
import json
from pathlib import Path
import resource
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("model_id")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()
    entry = json.loads((args.base / "models.json").read_text())[args.model_id]
    corpus = json.loads((args.base / "corpus/manifest.json").read_text())
    output = args.base / "results" / (args.model_id + ".jsonl")
    output.parent.mkdir(exist_ok=True)
    import mlx.core as mx

    def emit(event):
        event["model_id"] = args.model_id
        event["rss_peak_bytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        event["mlx_peak_bytes"] = mx.get_peak_memory()
        with output.open("a") as handle:
            handle.write(json.dumps(event) + "\n")
        print(json.dumps({k: v for k, v in event.items() if k != "text"}), flush=True)

    start = time.perf_counter()
    if entry["runtime"] == "current":
        sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Sources"))
        from ml import loader, parakeet
        # Only asset resolution is injected. Production loader/generation/chunk
        # code is used unchanged, with the exact app-pinned model snapshot.
        loader.cached_snapshot_path = lambda repo: entry["path"]
        model = loader.load_parakeet_model(entry["repo"])
        mx.eval(model.parameters())

        def transcribe(row):
            return parakeet.transcribe(entry["repo"], str(Path(row["path"]).with_suffix(".f32")))["text"]

        settings = {"provider": "production Sources/ml/parakeet.py", "chunk_seconds": 120, "overlap_seconds": 15}
    elif entry["runtime"] == "cohere-speech":
        import soundfile as sf
        from mlx_speech.generation import CohereAsrModel
        model = CohereAsrModel.from_path(entry["path"])
        mx.eval(model.model.parameters())
        settings = {"provider": "conversion-documented mlx-speech 0.5.3", "language": "en",
                    "punctuation": True, "itn": False, "max_new_tokens": 1024}

        def transcribe(row):
            audio, rate = sf.read(row["path"], dtype="float32")
            return model.transcribe(audio, sample_rate=rate, **{key: value for key, value in settings.items() if key != "provider"}).text
    else:
        from mlx_audio.stt import load
        model = load(entry["path"])
        mx.eval(model.parameters())
        settings = {"provider": "mlx-audio 0.5.7 candidate adapter", "stream": False}
        if args.model_id.startswith("cohere"):
            settings.update(language="en", vad=False, max_tokens=1024)
        elif args.model_id.startswith("qwen"):
            settings.update(language="English", max_tokens=1024)

        def transcribe(row):
            options = {key: value for key, value in settings.items() if key not in ["provider"]}
            options["verbose"] = False
            return model.generate(row["path"], **options).text

    mx.synchronize()
    load_seconds = time.perf_counter() - start
    versions = {}
    for package in ["mlx", "mlx-audio", "mlx-speech", "parakeet-mlx", "numpy", "huggingface-hub"]:
        try: versions[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError: pass
    emit(dict(kind="loaded", load_seconds=load_seconds, process_to_loaded_seconds=time.perf_counter() - PROCESS_START,
              packages=versions, model=entry, settings=settings))
    first = corpus[0]
    start = time.perf_counter()
    text = transcribe(first)
    mx.synchronize()
    emit(dict(kind="first-use", case=first["id"], seconds=time.perf_counter() - start,
              process_to_first_result_seconds=time.perf_counter() - PROCESS_START, text=text))
    speed = next(row for row in corpus if row["group"] == "speed")
    # One explicit warmup followed by five timed same-audio measurements.
    transcribe(speed); mx.synchronize()
    for repetition in range(5):
        start = time.perf_counter()
        text = transcribe(speed)
        mx.synchronize()
        emit(dict(kind="speed", case=speed["id"], repetition=repetition,
                  seconds=time.perf_counter() - start, audio_seconds=speed["duration"], text=text))
    cases = [row for row in corpus if row["group"] != "speed"]
    if args.limit: cases = cases[:args.limit]
    failures = 0
    for index, row in enumerate(cases):
        start = time.perf_counter()
        try:
            text = transcribe(row)
            mx.synchronize()
            emit(dict(kind="quality", case=row["id"], group=row["group"], seconds=time.perf_counter() - start,
                      audio_seconds=row["duration"], text=text, index=index))
        except Exception as exc:
            failures += 1
            emit(dict(kind="error", case=row["id"], group=row["group"], error=repr(exc)))
    emit(dict(kind="complete", quality_cases=len(cases), failures=failures))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
