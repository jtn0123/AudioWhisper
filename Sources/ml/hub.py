"""Hugging Face cache access for the bundled ML scripts.

Two rules, and why each exists:

* **Loading a model never touches the network.** This used to be attempted by
  setting `HF_HUB_OFFLINE=1` just before each load. That does nothing:
  `huggingface_hub` reads the variable once, into a module constant, when it is
  first imported — and by then `parakeet_mlx` / `mlx_lm` had already imported
  it. So every "offline" load quietly asked huggingface.co for the latest
  revision, and if the repo had moved upstream, downloaded new weights in the
  middle of a load. `local_files_only=True` is a per-call guarantee that does
  not depend on import order, so loads resolve the cached snapshot here and
  hand the model library a local directory.

* **Downloads of app-provided models fetch a pinned commit.** The Swift side
  passes the revision (see `ModelPins`). A download by commit hash does not
  write `refs/main`, which is the pointer every offline lookup — ours and the
  model libraries' — resolves, so `download_snapshot` writes it. Without that
  a pinned download is invisible to `cached_snapshot_path`.
"""

from __future__ import annotations

import os
from typing import Any, Optional


def cached_snapshot_path(repo: str) -> str:
    """Local directory of the snapshot `refs/main` points at.

    Never touches the network. Raises (`LocalEntryNotFoundError`) if the repo
    is not cached.
    """
    from huggingface_hub import snapshot_download

    return str(snapshot_download(repo, local_files_only=True))


def download_snapshot(repo: str, revision: Optional[str] = None, tqdm_class: Any = None) -> str:
    """Download `repo` at `revision` (latest if None) and return its directory.

    When a revision is given, `refs/main` is pointed at it so that offline
    resolution finds exactly this snapshot.
    """
    from huggingface_hub import snapshot_download

    if tqdm_class is None:
        path = str(snapshot_download(repo, revision=revision))
    else:
        path = str(snapshot_download(repo, revision=revision, tqdm_class=tqdm_class))
    if revision:
        point_main_at(path)
    return path


def point_main_at(snapshot_path: str) -> None:
    """Make `refs/main` name the snapshot at `snapshot_path`.

    The cache layout is `<hub>/models--<org>--<name>/snapshots/<commit>`, and
    `refs/main` holds a bare commit hash with no trailing newline — the same
    bytes `huggingface_hub` writes itself. Written via rename so a reader never
    sees a half-written ref.
    """
    snapshot_path = os.path.normpath(snapshot_path)
    commit = os.path.basename(snapshot_path)
    storage = os.path.dirname(os.path.dirname(snapshot_path))
    refs = os.path.join(storage, "refs")
    os.makedirs(refs, exist_ok=True)
    tmp = os.path.join(refs, ".main.tmp")
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(commit)
    os.replace(tmp, os.path.join(refs, "main"))
