#!/usr/bin/env python3
"""Verify an MLX correction model loads, downloading it first if not cached.

Usage: verify_mlx.py <repo> [revision]

`revision` is the commit the app pins for the models it ships; a download
fetches exactly that commit. The cache check never touches the network — see
ml/hub.py for why that has to be a per-call guarantee rather than an
environment variable.
"""

import os
import sys
import json
import traceback


def emit(status: str, message: str) -> None:
    print(json.dumps({"status": status, "message": message}), flush=True)


def main() -> int:
    repo = sys.argv[1] if len(sys.argv) > 1 else ""
    if not repo:
        emit("error", "No repo specified")
        return 1
    revision = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
    os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
    try:
        emit("checking", "Importing mlx-lm…")
        from mlx_lm import load
        from ml.hub import cached_snapshot_path, download_snapshot

        try:
            emit("loading", "Trying offline cache…")
            path = cached_snapshot_path(repo)
            ready = "Model ready (offline)"
        except Exception as e:
            emit("downloading", "Offline unavailable: {}. Downloading…".format(str(e)))
            path = download_snapshot(repo, revision)
            ready = "Model downloaded and ready"
        _m, _t = load(path)
        emit("complete", ready)
    except ImportError as e:
        emit(
            "error",
            "mlx-lm not installed: {}. Use Install Dependencies.".format(str(e)),
        )
        return 1
    except Exception as e:
        emit("error", "Error: {}\n{}".format(str(e), traceback.format_exc()))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
