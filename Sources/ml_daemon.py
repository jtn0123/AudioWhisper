#!/usr/bin/env python3
"""Thin entrypoint for the ML JSON-RPC daemon.

The core logic lives in the `ml` package; this file stays bundled as the
resource entrypoint the Swift app launches.
"""

import os

# The daemon only ever loads models that are already cached; downloads run in
# their own process (download_model.py). huggingface_hub reads these once, at
# import, so they must be set before anything below imports it — setting them
# later is silently ignored. Loads are offline per call regardless (see
# ml/hub.py); this is the belt to that pair of braces.
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

from ml.rpc import main  # must follow the environment setup above


if __name__ == "__main__":
    raise SystemExit(main())
