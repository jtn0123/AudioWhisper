#!/usr/bin/env python3
"""Tests for ml.hub, the model loaders built on it, and download_model.py.

Run with: python3 Tests/test_hub.py

`huggingface_hub` is not installed in the checkout (it lives in the app's
runtime venv), so these run against a fake that reproduces the three behaviours
the code depends on, each confirmed against huggingface_hub 1.9.1 itself:

* a download by commit hash writes the snapshot but NOT `refs/main`;
* a download by branch (revision None) writes `refs/main`;
* `local_files_only=True` resolves `refs/main` and raises if it is absent.

The first is the whole reason `download_snapshot` writes the ref: without it a
pinned download is invisible to every offline lookup.
"""

import json
import io
import os
import subprocess
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout
from typing import Any, Dict, List, Optional

SOURCES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Sources")
sys.path.insert(0, SOURCES)
# Importing download_model from Sources/ would otherwise leave
# Sources/__pycache__/*.pyc behind, which SwiftPM then warns about as an
# undeclared file in the app target.
sys.dont_write_bytecode = True

LATEST = "f" * 40
PINNED = "a" * 40


class LocalEntryNotFoundError(Exception):
    pass


class FakeHub:
    """Stands in for `huggingface_hub.snapshot_download` over a temp cache."""

    def __init__(self, root: str) -> None:
        self.root = root
        self.calls: List[Dict[str, Any]] = []

    def storage(self, repo: str) -> str:
        return os.path.join(self.root, "models--" + repo.replace("/", "--"))

    def snapshot_download(
        self, repo: str, revision: Optional[str] = None, local_files_only: bool = False
    ) -> str:
        self.calls.append({"repo": repo, "revision": revision, "local_files_only": local_files_only})
        storage = self.storage(repo)
        if local_files_only:
            ref = os.path.join(storage, "refs", revision or "main")
            if not os.path.exists(ref):
                raise LocalEntryNotFoundError(f"{repo} is not cached")
            with open(ref, encoding="utf-8") as handle:
                return os.path.join(storage, "snapshots", handle.read())
        commit = revision or LATEST
        snapshot = os.path.join(storage, "snapshots", commit)
        os.makedirs(snapshot, exist_ok=True)
        with open(os.path.join(snapshot, "config.json"), "w", encoding="utf-8") as handle:
            handle.write("{}")
        if revision is None:  # a branch download records the ref; a commit download does not
            os.makedirs(os.path.join(storage, "refs"), exist_ok=True)
            with open(os.path.join(storage, "refs", "main"), "w", encoding="utf-8") as handle:
                handle.write(commit)
        return snapshot

    @property
    def network_calls(self) -> List[Dict[str, Any]]:
        return [c for c in self.calls if not c["local_files_only"]]


class HubTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.hub = FakeHub(self.tmp.name)
        module = types.ModuleType("huggingface_hub")
        module.snapshot_download = self.hub.snapshot_download  # type: ignore[attr-defined]
        self._saved = sys.modules.get("huggingface_hub")
        sys.modules["huggingface_hub"] = module

    def tearDown(self) -> None:
        if self._saved is None:
            sys.modules.pop("huggingface_hub", None)
        else:
            sys.modules["huggingface_hub"] = self._saved
        self.tmp.cleanup()

    def read_ref(self, repo: str) -> str:
        with open(os.path.join(self.hub.storage(repo), "refs", "main"), encoding="utf-8") as handle:
            return handle.read()


class TestCachedSnapshotPath(HubTestCase):
    def test_never_touches_the_network(self) -> None:
        from ml.hub import cached_snapshot_path

        self.hub.snapshot_download("org/model")  # populate via a branch download
        self.hub.calls.clear()

        cached_snapshot_path("org/model")

        self.assertEqual(self.hub.network_calls, [], "a cache lookup must be local_files_only")

    def test_raises_when_the_repo_is_not_cached(self) -> None:
        from ml.hub import cached_snapshot_path

        with self.assertRaises(LocalEntryNotFoundError):
            cached_snapshot_path("org/never-downloaded")
        self.assertEqual(self.hub.network_calls, [])


class TestDownloadSnapshot(HubTestCase):
    def test_pinned_download_is_visible_to_offline_lookup(self) -> None:
        from ml.hub import cached_snapshot_path, download_snapshot

        path = download_snapshot("org/model", PINNED)

        self.assertEqual(self.read_ref("org/model"), PINNED)
        self.assertEqual(cached_snapshot_path("org/model"), path)

    def test_pinned_download_replaces_an_older_ref(self) -> None:
        # A cache populated before pinning points refs/main at whatever was
        # latest then. Downloading the pin must move it, or loads keep using
        # the old snapshot.
        from ml.hub import cached_snapshot_path, download_snapshot

        self.hub.snapshot_download("org/model")
        self.assertEqual(self.read_ref("org/model"), LATEST)

        pinned_path = download_snapshot("org/model", PINNED)

        self.assertEqual(self.read_ref("org/model"), PINNED)
        self.assertEqual(cached_snapshot_path("org/model"), pinned_path)

    def test_download_requests_exactly_the_pinned_revision(self) -> None:
        from ml.hub import download_snapshot

        download_snapshot("org/model", PINNED)

        self.assertEqual(self.hub.network_calls, [
            {"repo": "org/model", "revision": PINNED, "local_files_only": False}
        ])

    def test_unpinned_download_leaves_the_ref_to_huggingface_hub(self) -> None:
        from ml.hub import download_snapshot

        download_snapshot("user/custom-model", None)

        self.assertEqual(self.read_ref("user/custom-model"), LATEST)

    def test_ref_is_a_bare_commit_with_no_trailing_newline(self) -> None:
        # Swift requires refs/main to be pure hex (isModelCachedOnDisk), and the
        # integrity record hashes its exact bytes.
        from ml.hub import download_snapshot

        download_snapshot("org/model", PINNED)

        self.assertEqual(self.read_ref("org/model"), PINNED)
        refs = os.listdir(os.path.join(self.hub.storage("org/model"), "refs"))
        self.assertEqual(refs, ["main"], "the temp file used for the atomic write must not remain")


class TestLoaders(HubTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.loaded_from: List[str] = []
        parakeet = types.ModuleType("parakeet_mlx")
        parakeet.from_pretrained = lambda path: self.loaded_from.append(path) or "parakeet-model"  # type: ignore[attr-defined]
        mlx_lm = types.ModuleType("mlx_lm")
        mlx_lm.load = lambda path: (self.loaded_from.append(path), ("model", "tokenizer"))[1]  # type: ignore[attr-defined]
        self._saved_libs = {name: sys.modules.get(name) for name in ("parakeet_mlx", "mlx_lm")}
        sys.modules["parakeet_mlx"] = parakeet
        sys.modules["mlx_lm"] = mlx_lm

        import ml.loader as loader
        self.loader = loader
        loader._PARAKEET_CACHE.clear()
        loader._CORRECTION_CACHE.clear()

    def tearDown(self) -> None:
        for name, module in self._saved_libs.items():
            if module is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = module
        self.loader._PARAKEET_CACHE.clear()
        self.loader._CORRECTION_CACHE.clear()
        super().tearDown()

    def test_switching_releases_old_model_before_loading_replacement(self) -> None:
        import weakref
        from ml.hub import download_snapshot

        class Model:
            pass

        for repo in ("org/first", "org/second"):
            download_snapshot(repo, PINNED)
        old = None

        def load(path: str) -> Model:
            if old is not None:
                self.assertIsNone(old(), "old weights must be released before replacement loading")
            return Model()

        sys.modules["parakeet_mlx"].from_pretrained = load
        first = self.loader.load_parakeet_model("org/first")
        old = weakref.ref(first)
        del first
        self.loader.load_parakeet_model("org/second")
        self.assertEqual(list(self.loader._PARAKEET_CACHE), ["org/second"])

    def test_cache_switching_keeps_engines_independent_and_bounded(self) -> None:
        from ml.hub import download_snapshot

        download_snapshot("org/parakeet", PINNED)
        self.loader.load_parakeet_model("org/parakeet")
        for index in range(5):
            repo = f"org/correction-{index}"
            download_snapshot(repo, PINNED)
            self.loader.load_correction_model(repo)
            self.assertEqual(len(self.loader._CORRECTION_CACHE), 1)
            self.assertEqual(list(self.loader._PARAKEET_CACHE), ["org/parakeet"])

    def test_parakeet_loads_the_pinned_snapshot_from_a_local_path(self) -> None:
        from ml.hub import download_snapshot

        self.hub.snapshot_download("org/parakeet")  # an older, pre-pinning cache
        pinned_path = download_snapshot("org/parakeet", PINNED)
        self.hub.calls.clear()

        self.loader.load_parakeet_model("org/parakeet")

        self.assertEqual(self.loaded_from, [pinned_path])
        self.assertEqual(self.hub.network_calls, [], "loading must never go online")

    def test_correction_model_loads_from_a_local_path_without_network(self) -> None:
        from ml.hub import download_snapshot

        pinned_path = download_snapshot("org/qwen", PINNED)
        self.hub.calls.clear()

        model, tokenizer = self.loader.load_correction_model("org/qwen")

        self.assertEqual((model, tokenizer), ("model", "tokenizer"))
        self.assertEqual(self.loaded_from, [pinned_path])
        self.assertEqual(self.hub.network_calls, [])

    def test_uncached_model_fails_offline_instead_of_downloading(self) -> None:
        with self.assertRaises(RuntimeError) as ctx:
            self.loader.load_parakeet_model("org/not-downloaded")
        self.assertIn("not available offline", str(ctx.exception))
        with self.assertRaises(RuntimeError):
            self.loader.load_correction_model("org/not-downloaded")
        self.assertEqual(self.hub.network_calls, [])


class TestDownloadModelScript(HubTestCase):
    def run_main(self, argv: List[str]) -> "tuple[int, List[Dict[str, str]]]":
        import download_model

        buffer = io.StringIO()
        with redirect_stdout(buffer):
            code = download_model.main(argv)
        events = [json.loads(line) for line in buffer.getvalue().splitlines() if line.strip()]
        return code, events

    def test_pinned_download_reports_complete_and_sets_the_ref(self) -> None:
        code, events = self.run_main(["download_model.py", "org/model", PINNED])

        self.assertEqual(code, 0)
        self.assertEqual([e["status"] for e in events], ["downloading", "complete"])
        self.assertEqual(self.read_ref("org/model"), PINNED)

    def test_empty_revision_argument_means_unpinned(self) -> None:
        code, _ = self.run_main(["download_model.py", "user/custom", ""])

        self.assertEqual(code, 0)
        self.assertEqual(self.hub.network_calls[0]["revision"], None)

    def test_missing_repo_is_an_error_with_exit_code_2(self) -> None:
        code, events = self.run_main(["download_model.py"])

        self.assertEqual(code, 2)
        self.assertEqual(events, [{"status": "error", "message": "Missing repo argument"}])

    def test_download_failure_is_reported_on_stdout_and_exit_code(self) -> None:
        def failing(*_args: Any, **_kwargs: Any) -> str:
            raise OSError("connection reset")

        sys.modules["huggingface_hub"].snapshot_download = failing  # type: ignore[attr-defined]
        code, events = self.run_main(["download_model.py", "org/model", PINNED])

        self.assertEqual(code, 1)
        self.assertEqual(events[-1], {"status": "error", "message": "connection reset"})

    def test_missing_huggingface_hub_is_named_in_the_error(self) -> None:
        sys.modules["huggingface_hub"] = None  # type: ignore[assignment]  # makes the import raise
        code, events = self.run_main(["download_model.py", "org/model", PINNED])

        self.assertEqual(code, 1)
        self.assertEqual(events[-1]["status"], "error")
        self.assertTrue(events[-1]["message"].startswith("huggingface_hub not installed:"))


class TestDaemonEntrypoint(unittest.TestCase):
    def test_offline_flags_are_set_before_the_daemon_imports_anything(self) -> None:
        # huggingface_hub reads HF_HUB_OFFLINE once, at import. The daemon must
        # set it before importing ml.rpc, or it is silently ignored.
        probe = (
            "import os, runpy; "
            "env_at_import = {}; "
            "import builtins; real_import = builtins.__import__\n"
            "def spy(name, *a, **k):\n"
            "    if name == 'ml.rpc' and 'seen' not in env_at_import:\n"
            "        env_at_import['seen'] = os.environ.get('HF_HUB_OFFLINE')\n"
            "    return real_import(name, *a, **k)\n"
            "builtins.__import__ = spy\n"
            "runpy.run_path('ml_daemon.py', run_name='not_main')\n"
            "print(env_at_import.get('seen'))"
        )
        env = {k: v for k, v in os.environ.items() if k not in ("HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE")}
        result = subprocess.run(
            [sys.executable, "-c", probe], cwd=SOURCES, env=env,
            capture_output=True, text=True, check=True,
        )
        self.assertEqual(result.stdout.strip(), "1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
