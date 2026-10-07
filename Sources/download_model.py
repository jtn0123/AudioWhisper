#!/usr/bin/env python3
"""Download a model snapshot into the Hugging Face cache.

Usage: download_model.py <repo> [revision]

`revision` is the commit the app pins for models it ships (see `ModelPins` in
Swift); it is omitted for user-added repos, which download at their latest
revision. Arguments arrive via argv, never interpolated into source, so a
hostile repo name cannot run code.

Reports progress as one JSON object per stdout line — the contract
`MLXDownloadEvent` parses: `{"status": "downloading" | "complete" | "error",
"message": str}`. Failure is also signalled by a non-zero exit code.
"""

import json
import os
import sys
from typing import Any, List

# Read by huggingface_hub at import time, so these must precede the import in
# main(). Never pick up a token from the user's environment or HF login.
os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "0")


def emit(status: str, message: str) -> None:
    print(json.dumps({"status": status, "message": message}), flush=True)


def main(argv: List[str]) -> int:
    if len(argv) < 2 or not argv[1]:
        emit("error", "Missing repo argument")
        return 2
    repo = argv[1]
    revision = argv[2] if len(argv) > 2 and argv[2] else None

    from ml.hub import download_snapshot

    emit("downloading", "Downloading model files...")
    try:
        # ml.hub imports huggingface_hub lazily, so a missing install surfaces
        # here, at the call, rather than at the import above.
        from tqdm.auto import tqdm

        # tqdm is the runtime's untyped third-party progress base.
        class DownloadProgress(tqdm):  # type: ignore[misc]
            def display(self, msg: Any = None, pos: Any = None) -> None:
                total = self.total
                completed = self.n
                if not total or total <= 0:
                    return
                unit = "bytes" if self.unit == "B" else "files"
                if unit == "bytes":
                    message = f"Downloaded {completed / 1_000_000:.1f} / {total / 1_000_000:.1f} MB"
                else:
                    message = f"Fetched {int(completed)} / {int(total)} files"
                print(json.dumps({"status": "downloading", "message": message,
                                  "completed": completed, "total": total, "unit": unit}), flush=True)

        download_snapshot(repo, revision, tqdm_class=DownloadProgress)
    except ImportError as exc:
        emit("error", f"huggingface_hub not installed: {exc}")
        return 1
    except Exception as exc:
        emit("error", str(exc))
        return 1
    emit("complete", "Download complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
