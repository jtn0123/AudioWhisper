#!/usr/bin/env python3
"""Tests for verify_parakeet.py, verify_mlx.py and the ml_daemon.py entrypoint.

Run with: python3 Tests/test_verify_scripts.py

The verify scripts back the Settings "Verify" buttons. Each tries the offline
cache first and downloads the pinned revision only on a miss, then loads the
model. Here huggingface_hub, parakeet_mlx and mlx_lm are fakes, so the tests
need no venv, no network and no model.
"""

import importlib
import io
import json
import os
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout
from typing import Any, Dict, List, Optional
from unittest import mock

SOURCES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Sources")
sys.path.insert(0, SOURCES)
# Keep Sources/ free of __pycache__, which SwiftPM would warn about.
sys.dont_write_bytecode = True

PINNED = "a" * 40


class FakeHub:
    """`snapshot_download` over a temp cache; `cached` repos resolve offline."""

    def __init__(self, root: str) -> None:
        self.root = root
        self.cached: Dict[str, str] = {}
        self.calls: List[Dict[str, Any]] = []

    def snapshot(self, repo: str, commit: str) -> str:
        path = os.path.join(self.root, "models--" + repo.replace("/", "--"), "snapshots", commit)
        os.makedirs(path, exist_ok=True)
        return path

    def snapshot_download(
        self, repo: str, revision: Optional[str] = None, local_files_only: bool = False
    ) -> str:
        self.calls.append({"repo": repo, "revision": revision, "local_files_only": local_files_only})
        if local_files_only:
            if repo not in self.cached:
                raise FileNotFoundError(f"{repo} is not cached")
            return self.cached[repo]
        return self.snapshot(repo, revision or "f" * 40)


class ScriptTestCase(unittest.TestCase):
    """Installs the fakes in sys.modules and restores everything afterwards."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.hub = FakeHub(self.tmp.name)
        self.loaded: List[str] = []

        hub_module = types.ModuleType("huggingface_hub")
        hub_module.snapshot_download = self.hub.snapshot_download  # type: ignore[attr-defined]
        parakeet_module = types.ModuleType("parakeet_mlx")
        parakeet_module.from_pretrained = self.load_parakeet  # type: ignore[attr-defined]
        mlx_lm_module = types.ModuleType("mlx_lm")
        mlx_lm_module.load = self.load_mlx  # type: ignore[attr-defined]

        self.modules = mock.patch.dict(sys.modules, {
            "huggingface_hub": hub_module,
            "parakeet_mlx": parakeet_module,
            "mlx_lm": mlx_lm_module,
        })
        self.modules.start()
        self.env = mock.patch.dict(os.environ)
        self.env.start()

    def tearDown(self) -> None:
        self.env.stop()
        self.modules.stop()
        self.tmp.cleanup()

    def load_parakeet(self, path: str) -> object:
        self.loaded.append(path)
        return object()

    def load_mlx(self, path: str) -> "tuple[object, object]":
        self.loaded.append(path)
        return object(), object()

    def run_script(self, name: str, argv: List[str]) -> "tuple[int, List[Dict[str, str]]]":
        module = importlib.import_module(name)
        buffer = io.StringIO()
        with mock.patch.object(sys, "argv", [name + ".py"] + argv), redirect_stdout(buffer):
            code = module.main()
        events = [json.loads(line) for line in buffer.getvalue().splitlines() if line.strip()]
        return code, events

    @property
    def downloads(self) -> List[Dict[str, Any]]:
        return [c for c in self.hub.calls if not c["local_files_only"]]


class VerifyScriptBehaviour:
    """Shared cases, run once per script by the subclasses below."""

    script = ""
    repo = ""

    def test_a_cached_model_loads_offline_without_downloading(self) -> None:
        cached = self.hub.snapshot(self.repo, PINNED)
        self.hub.cached[self.repo] = cached

        code, events = self.run_script(self.script, [self.repo, PINNED])

        self.assertEqual(code, 0)
        self.assertEqual(events[-1], {"status": "complete", "message": "Model ready (offline)"})
        self.assertEqual(self.downloads, [])
        self.assertEqual(self.loaded, [cached])

    def test_a_cache_miss_downloads_the_pinned_revision_then_loads_it(self) -> None:
        code, events = self.run_script(self.script, [self.repo, PINNED])

        self.assertEqual(code, 0)
        self.assertIn("downloading", [e["status"] for e in events])
        self.assertEqual(events[-1], {"status": "complete", "message": "Model downloaded and ready"})
        self.assertEqual(self.downloads, [{"repo": self.repo, "revision": PINNED, "local_files_only": False}])
        self.assertEqual(len(self.loaded), 1)
        self.assertTrue(self.loaded[0].endswith(PINNED))

    def test_an_empty_revision_downloads_the_latest(self) -> None:
        code, _ = self.run_script(self.script, [self.repo, ""])

        self.assertEqual(code, 0)
        self.assertIsNone(self.downloads[0]["revision"])

    def test_a_load_failure_is_reported_with_its_traceback(self) -> None:
        def broken(_path: str) -> Any:
            raise RuntimeError("weights are corrupt")

        self.hub.cached[self.repo] = self.hub.snapshot(self.repo, PINNED)
        self.break_loader(broken)

        code, events = self.run_script(self.script, [self.repo])

        self.assertEqual(code, 1)
        self.assertEqual(events[-1]["status"], "error")
        self.assertIn("weights are corrupt", events[-1]["message"])
        self.assertIn("Traceback", events[-1]["message"])

    def test_a_missing_library_points_at_install_dependencies(self) -> None:
        sys.modules[self.library] = None  # makes `import` raise ImportError

        code, events = self.run_script(self.script, [self.repo])

        self.assertEqual(code, 1)
        self.assertEqual(events[-1]["status"], "error")
        self.assertIn("Use Install Dependencies", events[-1]["message"])

    def test_no_token_is_picked_up_from_the_environment(self) -> None:
        os.environ.pop("HF_HUB_DISABLE_IMPLICIT_TOKEN", None)
        self.hub.cached[self.repo] = self.hub.snapshot(self.repo, PINNED)

        self.run_script(self.script, [self.repo])

        self.assertEqual(os.environ.get("HF_HUB_DISABLE_IMPLICIT_TOKEN"), "1")


class TestVerifyParakeet(VerifyScriptBehaviour, ScriptTestCase):
    script = "verify_parakeet"
    repo = "mlx-community/parakeet-tdt-0.6b-v3"
    library = "parakeet_mlx"

    def break_loader(self, loader: Any) -> None:
        sys.modules["parakeet_mlx"].from_pretrained = loader  # type: ignore[attr-defined]

    def test_with_no_arguments_it_verifies_the_default_model(self) -> None:
        code, _ = self.run_script(self.script, [])

        self.assertEqual(code, 0)
        self.assertEqual(self.hub.calls[0]["repo"], "mlx-community/parakeet-tdt-0.6b-v2")


class TestVerifyMLX(VerifyScriptBehaviour, ScriptTestCase):
    script = "verify_mlx"
    repo = "mlx-community/Qwen3-1.7B-4bit"
    library = "mlx_lm"

    def break_loader(self, loader: Any) -> None:
        sys.modules["mlx_lm"].load = loader  # type: ignore[attr-defined]

    def test_a_missing_repo_is_an_error(self) -> None:
        code, events = self.run_script(self.script, [])

        self.assertEqual(code, 1)
        self.assertEqual(events, [{"status": "error", "message": "No repo specified"}])
        self.assertEqual(self.hub.calls, [])


class TestDaemonEntrypointInProcess(unittest.TestCase):
    """test_hub.py checks the ordering in a subprocess; this imports it here."""

    def test_importing_the_entrypoint_forces_offline_mode_and_exposes_main(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("HF_HUB_OFFLINE", None)
            os.environ.pop("TRANSFORMERS_OFFLINE", None)
            sys.modules.pop("ml_daemon", None)
            daemon = importlib.import_module("ml_daemon")

            self.assertEqual(os.environ["HF_HUB_OFFLINE"], "1")
            self.assertEqual(os.environ["TRANSFORMERS_OFFLINE"], "1")

        from ml.rpc import main
        self.assertIs(daemon.main, main)


if __name__ == "__main__":
    unittest.main()
