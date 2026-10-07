"""Prepare an isolated, revision-pinned model cache and public English corpus."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import time
import urllib.parse
import urllib.request

import numpy as np
import soundfile as sf
from huggingface_hub import snapshot_download
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[2]
WHISPER_REVISION = "0f63a7800b00dd0226abd051b906c246e1907482"
PINS = {
    "parakeet-v2": ("mlx-community/parakeet-tdt-0.6b-v2", "8ae155301e23d820d82aa60d24817c900e69e487", "current"),
    "parakeet-v3": ("mlx-community/parakeet-tdt-0.6b-v3", "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15", "current"),
    "granite-5": ("ibm-granite/granite-speech-5.0-470m-turboctc", "947f59af40db9791170a0628cf0f3f4812d720f1", "candidate"),
    "cohere-8bit": ("mlx-community/cohere-transcribe-03-2026-mlx-8bit", "a0acb7f93cd32d82c4fbf801b6d8fb39d20c509f", "cohere-speech"),
    "qwen3-asr-4bit": ("mlx-community/Qwen3-ASR-1.7B-4bit", "78a389c776a5483b2d0d4ea5494e11012e0d6159", "candidate"),
    "writing-qwen4b": ("mlx-community/Qwen3-4B-Instruct-2507-4bit", "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b", "writing-current"),
    "writing-gemma1b": ("mlx-community/gemma-3-1b-it-qat-4bit", "15fed4eafb456c6fcb2a1165f19ac609670ed14b", "writing-current"),
    "writing-qwen1.7b": ("mlx-community/Qwen3-1.7B-4bit", "3b1b1768f8f8cf8351c712464f906e86c2b8269e", "writing-current"),
    "writing-qwen3.5-2b": ("mlx-community/Qwen3.5-2B-4bit", "674aaa7240b91e8012fcad5d791b7dfe5ba90207", "writing-candidate"),
    "writing-lfm1.2b": ("mlx-community/LFM2.5-1.2B-Instruct-4bit", "dee2f8a2786e6648bb644a7ca40652842490034b", "writing-candidate"),
    "writing-gemma4": ("mlx-community/gemma-4-e2b-it-4bit", "238767527555cb75a05732a84dff5d6ba0dd6809", "writing-candidate"),
}


def get_json(url):
    with urllib.request.urlopen(url, timeout=40) as response:
        return json.load(response)


def write_audio(path, samples, rate):
    samples = np.asarray(samples, dtype=np.float32)
    if samples.ndim > 1:
        samples = samples.mean(axis=1)
    if rate != 16_000:
        divisor = math.gcd(rate, 16_000)
        samples = resample_poly(samples, 16_000 // divisor, rate // divisor)
    sf.write(path, samples, 16_000, subtype="PCM_16")
    pcm = path.with_suffix(".f32")
    samples.astype("<f4").tofile(pcm)
    return len(samples) / 16_000


def corpus(base):
    directory = base / "corpus"
    directory.mkdir(parents=True, exist_ok=True)
    manifest = directory / "manifest.json"
    if manifest.exists():
        print("Corpus already prepared:", manifest, flush=True)
        return
    records = []
    sets = [
        ("librispeech-clean", "openslr/librispeech_asr", "clean", 2620),
        ("librispeech-other", "openslr/librispeech_asr", "other", 2939),
        ("ami-meetings", "edinburghcstr/ami", "ihm", 12643),
    ]
    for group, dataset, config, total in sets:
        for batch, offset in enumerate(np.linspace(0, total - 100, 8, dtype=int)):
            query = urllib.parse.urlencode(dict(dataset=dataset, config=config, split="test", offset=int(offset), length=30))
            rows = get_json("https://datasets-server.huggingface.co/rows?" + query)["rows"]
            kept = 0
            for row_entry in rows:
                row = row_entry["row"]
                text = row["text"].strip()
                if len(text.split()) < 8:
                    continue
                if "begin_time" in row and not 2 <= row["end_time"] - row["begin_time"] <= 35:
                    continue
                audio_url = row["audio"][0]["src"]
                ident = f"{group}-{row_entry['row_idx']}"
                raw = directory / f"{ident}.download"
                urllib.request.urlretrieve(audio_url, raw)
                samples, rate = sf.read(raw, dtype="float32")
                raw.unlink()
                duration = len(samples) / rate
                if not 2 <= duration <= 35:
                    continue
                path = directory / f"{ident}.wav"
                duration = write_audio(path, samples, rate)
                records.append(dict(id=ident, group=group, reference=text, path=str(path), duration=duration,
                                    dataset=dataset, config=config, split="test", row_index=row_entry["row_idx"],
                                    speaker=str(row.get("speaker_id", "")),
                                    source_audio=audio_url.split("?")[0], required=[]))
                kept += 1
                if kept == 2:
                    break
            if kept != 2:
                raise RuntimeError(f"Insufficient eligible samples in {group} at {offset}: {kept}")
        print("Prepared", group, sum(r["group"] == group for r in records), flush=True)
    rng = np.random.default_rng(20261005)
    for index, original in enumerate([r for r in records if r["group"] == "librispeech-clean"][::2]):
        samples, _ = sf.read(original["path"], dtype="float32")
        noise = rng.normal(size=samples.shape).astype(np.float32)
        noise *= np.sqrt(np.mean(samples ** 2)) / (10 ** (10 / 20) * np.sqrt(np.mean(noise ** 2)))
        path = directory / f"noise-{index}.wav"
        duration = write_audio(path, np.clip(samples + noise, -1, 1), 16_000)
        records.append(dict(original, id=f"noise-{index}", group="added-noise-10db", path=str(path), duration=duration,
                            derived_from=original["id"], noise_snr_db=10))
    spoken = [
        ("Please send the invoice for twenty one dollars and fifty cents to Morgan before Friday.", ["Morgan", "Friday", "$21.50"]),
        ("Do not delete the backup. The account balance is negative forty two dollars.", ["not", "backup", "negative $42"]),
        ("The appointment is on October fifth at nine thirty in the morning with Doctor Rivera.", ["October", "5th", "9:30", "Rivera"]),
        ("Open GitHub and check the pull request for Audio Whisper before deploying to production.", ["GitHub", "Audio Whisper", "production"]),
        ("Call Jordan at five five five, zero one two, nine eight seven six, and leave a message.", ["Jordan", "message"]),
        ("Version three point one point four needs Python and Swift, not JavaScript.", ["Python", "Swift", "not", "JavaScript"]),
        ("I can attend Tuesday, but I cannot attend Thursday. Please keep both dates in the notes.", ["Tuesday", "cannot", "Thursday"]),
        ("The meeting includes Priya, Mateo, and Siobhan. Please send each person the final report.", ["Priya", "Mateo", "Siobhan"]),
    ]
    for index, (text, required) in enumerate(spoken):
        raw = directory / f"dictation-{index}.aiff"
        subprocess.run(["say", "-v", "Samantha", "-r", "165", "-o", str(raw), text], check=True)
        decoded = directory / f"dictation-{index}-decode.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(raw), "-ar", "16000", "-ac", "1", str(decoded)], check=True)
        samples, rate = sf.read(decoded, dtype="float32")
        raw.unlink(); decoded.unlink()
        path = directory / f"dictation-{index}.wav"
        duration = write_audio(path, samples, rate)
        records.append(dict(id=f"dictation-{index}", group="synthetic-names-numbers", reference=text,
                            path=str(path), duration=duration, required=required, voice="macOS Samantha, 165 wpm"))
    for index, amplitude in enumerate([0, 0.001, 0.01]):
        path = directory / f"non-speech-{index}.wav"
        samples = rng.normal(size=80_000).astype(np.float32) * amplitude
        duration = write_audio(path, samples, 16_000)
        records.append(dict(id=f"non-speech-{index}", group="non-speech", reference="", path=str(path), duration=duration, required=[]))
    # Identical natural-speech composites for repeatable speed and long-form checks.
    for name, target, group in [("speed", 60, "speed"), ("long", 180, "long-form")]:
        waves, references = [], []
        elapsed = 0
        candidates = [r for r in records if r["group"].startswith("librispeech")]
        for row in candidates:
            wave, _ = sf.read(row["path"], dtype="float32")
            waves.extend([wave, np.zeros(4000, dtype=np.float32)])
            references.append(row["reference"])
            elapsed += len(wave) / 16_000 + 0.25
            if elapsed >= target: break
        path = directory / f"{name}.wav"
        duration = write_audio(path, np.concatenate(waves), 16_000)
        records.append(dict(id=name, group=group, reference=" ".join(references), path=str(path), duration=duration, required=[], synthetic_edit="Public natural speech clips joined with 250 ms gaps"))
    for row in records:
        row["sha256"] = hashlib.sha256(Path(row["path"]).read_bytes()).hexdigest()
    manifest.write_text(json.dumps(records, indent=2) + "\n")
    print("Corpus ready:", len(records), "cases", round(sum(r["duration"] for r in records)), "seconds", flush=True)


def models(base):
    registry = base / "models.json"
    saved = json.loads(registry.read_text()) if registry.exists() else {}
    for ident, (repo, revision, runtime) in PINS.items():
        if ident in saved: continue
        existing = Path.home() / ".cache/huggingface/hub" / ("models--" + repo.replace("/", "--")) / "snapshots" / revision
        start = time.perf_counter()
        if existing.is_dir():
            path = existing
            origin = "existing pinned app cache, read only"
        else:
            path = Path(snapshot_download(repo, revision=revision, cache_dir=str(base / "hf/hub")))
            origin = "isolated benchmark download"
        if ident == "cohere-8bit": path = path / "mlx-int8"
        saved[ident] = dict(repo=repo, revision=revision, runtime=runtime, path=str(path), origin=origin,
                            preparation_seconds=time.perf_counter() - start,
                            logical_bytes=sum(p.stat().st_size for p in path.rglob("*") if p.is_file()))
        registry.write_text(json.dumps(saved, indent=2) + "\n")
        print("MODEL READY", ident, saved[ident]["logical_bytes"], flush=True)
    repo = "argmaxinc/whisperkit-coreml"
    revision = WHISPER_REVISION
    for variant in ["tiny", "base", "small", "large-v3_turbo"]:
        ident = "whisper-" + variant
        if ident in saved: continue
        folder = "openai_whisper-" + variant
        start = time.perf_counter()
        snapshot = Path(snapshot_download(repo, revision=revision, cache_dir=str(base / "hf/hub"), allow_patterns=[folder + "/**"]))
        path = snapshot / folder
        if not path.is_dir(): raise RuntimeError("Missing Core ML variant " + folder)
        saved[ident] = dict(repo=repo, revision=revision, runtime="whisper", path=str(path), variant=folder,
                            origin="isolated pinned benchmark download", preparation_seconds=time.perf_counter() - start,
                            logical_bytes=sum(p.stat().st_size for p in path.rglob("*") if p.is_file()))
        registry.write_text(json.dumps(saved, indent=2) + "\n")
        print("MODEL READY", ident, saved[ident]["logical_bytes"], flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("mode", choices=["corpus", "models"])
    args = parser.parse_args()
    args.base.mkdir(parents=True, exist_ok=True)
    (corpus if args.mode == "corpus" else models)(args.base)
