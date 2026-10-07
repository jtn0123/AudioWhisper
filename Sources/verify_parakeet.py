#!/usr/bin/env python3
"""Verify a Parakeet model loads, downloading it first if it is not cached.

Usage: verify_parakeet.py [repo] [revision]

`revision` is the commit the app pins for the models it ships; a download
fetches exactly that commit. The cache check never touches the network — see
ml/hub.py for why that has to be a per-call guarantee rather than an
environment variable.
"""

import os
import json
import traceback
import sys


def emit(status: str, message: str) -> None:
    print(json.dumps({"status": status, "message": message}), flush=True)


def main() -> int:
    os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
    # Default to v2 English; v3 remains available through an explicit repo.
    repo = sys.argv[1] if len(sys.argv) > 1 else "mlx-community/parakeet-tdt-0.6b-v2"
    revision = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
    try:
        emit("checking", "Importing parakeet-mlx…")
        from parakeet_mlx import from_pretrained
        from ml.hub import cached_snapshot_path, download_snapshot

        try:
            emit("loading", "Trying offline cache…")
            path = cached_snapshot_path(repo)
            ready = "Model ready (offline)"
        except Exception as e:
            emit("downloading", "Offline unavailable: {}. Downloading…".format(str(e)))
            path = download_snapshot(repo, revision)
            ready = "Model downloaded and ready"
        _ = from_pretrained(path)
        emit("complete", ready)
    except ImportError as e:
        emit(
            "error",
            "parakeet-mlx not installed: {}. Use Install Dependencies.".format(str(e)),
        )
        return 1
    except Exception as e:
        emit("error", "Error: {}\n{}".format(str(e), traceback.format_exc()))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
