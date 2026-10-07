"""Offline fixture inference through the packaged daemon, with no loader overrides."""
import argparse
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/bench"))
from writing_cases import production_prompts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    resources = args.app / "Contents/Resources"
    executable = args.app / "Contents/MacOS/AudioWhisper"
    report = {"binary_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
              "runtime_versions": {name: importlib.metadata.version(name) for name in
                                   ["fsspec", "mlx", "mlx-lm", "huggingface-hub", "parakeet-mlx"]},
              "offline": True, "requests": []}
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        samples, rate = sf.read(ROOT / "Tests/Resources/speech_sample.wav", dtype="float32")
        if samples.ndim > 1:
            samples = samples.mean(axis=1)
        divisor = math.gcd(rate, 16000)
        samples = resample_poly(samples, 16000 // divisor, rate // divisor)
        pcm = directory / "speech.f32"
        samples.astype("<f4").tofile(pcm)
        environment = {key: value for key, value in os.environ.items()
                       if key in ["HOME", "PATH", "TMPDIR", "LANG", "USER"]}
        environment.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1",
                           HF_HUB_DISABLE_IMPLICIT_TOKEN="1", PYTHONDONTWRITEBYTECODE="1",
                           PYTHONUNBUFFERED="1", PYTHONNOUSERSITE="1")
        with (directory / "daemon.stderr").open("w") as errors:
            process = subprocess.Popen([sys.executable, str(resources / "ml_daemon.py")],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=errors, text=True, env=environment)
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)

            def request(method, params):
                identity = len(report["requests"]) + 1
                started = time.monotonic()
                process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": identity,
                                                "method": method, "params": params}) + "\n")
                process.stdin.flush()
                if not selector.select(timeout=180):
                    raise TimeoutError(f"No packaged response to {method}")
                response = json.loads(process.stdout.readline())
                if response.get("id") != identity or "error" in response:
                    raise RuntimeError(response)
                result = response["result"]
                if method != "ping" and not result.get("success"):
                    raise RuntimeError(result)
                report["requests"].append({"method": method, "repo": params.get("repo"),
                                           "seconds": time.monotonic() - started, "result": result})
                print(method, params.get("repo", ""), "passed", flush=True)
                return result

            try:
                assert request("ping", {})["pong"]
                speech = request("transcribe", {"repo": "mlx-community/parakeet-tdt-0.6b-v2",
                                                 "pcm_path": str(pcm)})
                assert "quick brown fox" in speech["text"].lower(), speech
                prompt = production_prompts(ROOT)["general"]
                for repo in ["mlx-community/Qwen3.5-9B-4bit",
                             "leonsarmiento/Qwen3.8-27B-3bit-mlx",
                             "mlx-community/Qwen3.5-9B-4bit"]:
                    result = request("correct", {"repo": repo, "text": "she dont want to cancel the order",
                                                  "prompt": prompt})
                    normalized = result["text"].lower().replace("’", "'")
                    assert "cancel" in normalized and "want" in normalized, result
                    assert "doesn't" in normalized or "does not" in normalized, result
                report["status"] = "passed"
            finally:
                process.stdin.close()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                selector.close()
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
    assert not list(resources.rglob("__pycache__")), "Inference wrote into signed resources"
    report["signature_valid_after_inference"] = True
    args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
