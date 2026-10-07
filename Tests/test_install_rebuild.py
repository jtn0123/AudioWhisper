import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("install_rebuild", Path(__file__).resolve().parents[1] / "scripts/install-rebuild.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallRebuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.target = root / "AudioWhisper Rebuild.app"
        self.source = root / "AudioWhisper.app"
        self.target.mkdir()
        (self.target / "version").write_text("old")
        self.source.mkdir()
        (self.source / "version").write_text("new")
        self.addCleanup(patch.stopall)
        patch.object(installer, "TARGET", self.target).start()
        self.verify = patch.object(installer, "verify", return_value="persistent identity").start()
        self.stop = patch.object(installer, "stop").start()
        self.launch = patch.object(installer, "launch").start()
        patch.object(installer.subprocess, "run", side_effect=lambda args, **_: shutil.copytree(args[1], args[2])).start()

    def test_validated_bundle_replaces_whole_app_and_keeps_backup(self):
        installer.install(self.source, self.target)
        self.assertEqual((self.target / "version").read_text(), "new")
        backups = list((self.target.parent / ".AudioWhisperBackups").glob("*.app"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "version").read_text(), "old")
        self.stop.assert_called_once_with(self.target)
        self.launch.assert_called_once_with(self.target)

    def test_stop_or_signature_failure_leaves_old_bundle_untouched(self):
        for failure in ("signature", "stop"):
            with self.subTest(failure=failure):
                self.verify.side_effect = RuntimeError("signature") if failure == "signature" else None
                self.stop.side_effect = RuntimeError("still running") if failure == "stop" else None
                with self.assertRaises(RuntimeError): installer.install(self.source, self.target)
                self.assertEqual((self.target / "version").read_text(), "old")

    def test_signer_change_is_rejected_before_stopping(self):
        self.verify.side_effect = ["new identity", "old identity"]
        with self.assertRaises(ValueError): installer.install(self.source, self.target)
        self.stop.assert_not_called()

    def test_launch_failure_rolls_back_the_original(self):
        self.launch.side_effect = [RuntimeError("launch failed"), None]
        with self.assertRaises(RuntimeError): installer.install(self.source, self.target)
        self.assertEqual((self.target / "version").read_text(), "old")

    def test_unexpected_destination_and_symlinks_are_rejected(self):
        with self.assertRaises(ValueError): installer.install(self.source, self.target.parent / "other.app")
        link = self.target.parent / "link.app"
        link.symlink_to(self.source)
        with self.assertRaises(ValueError): installer.install(link, self.target)


if __name__ == "__main__": unittest.main()
