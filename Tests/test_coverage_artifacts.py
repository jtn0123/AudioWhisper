"""Coverage reuse must reject stale, altered and empty reports."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CoverageArtifactsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.report = self.directory / "coverage.xml"
        self.report.write_text(
            '<coverage version="1"><file path="Sources/App.swift">'
            '<lineToCover lineNumber="1" covered="true"/></file></coverage>'
        )

    def artifact(self, action, kind="swift", commit="tested-sha", run="123", attempt="1"):
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/coverage-artifact.py"), action, kind,
             str(self.report), "--commit", commit, "--run-id", run, "--attempt", attempt],
            capture_output=True, text=True, check=False,
        )

    def test_matching_tested_report_is_accepted(self):
        self.assertEqual(self.artifact("create").returncode, 0)
        self.assertEqual(self.artifact("verify").returncode, 0)

    def test_wrong_commit_run_attempt_kind_or_content_is_rejected(self):
        self.assertEqual(self.artifact("create").returncode, 0)
        for kwargs in ({"commit": "other"}, {"run": "other"}, {"attempt": "2"}, {"kind": "python"}):
            with self.subTest(kwargs=kwargs):
                self.assertNotEqual(self.artifact("verify", **kwargs).returncode, 0)
        self.report.write_text(self.report.read_text().replace('covered="true"', 'covered="false"'))
        self.assertNotEqual(self.artifact("verify").returncode, 0)

    def test_missing_manifest_or_report_is_rejected(self):
        self.assertNotEqual(self.artifact("verify").returncode, 0)
        self.report.unlink()
        self.assertNotEqual(self.artifact("create").returncode, 0)

    def test_empty_malformed_or_dependency_only_reports_are_rejected(self):
        for text in ("", "broken XML", '<coverage version="1"/>',
                     '<coverage><file path=".build/App.swift"><lineToCover/></file></coverage>'):
            with self.subTest(text=text):
                self.report.write_text(text)
                self.assertNotEqual(self.artifact("create").returncode, 0)

    def test_python_report_requires_application_lines(self):
        self.report.write_text(
            '<coverage><packages><package><classes><class filename="Sources/ml/rpc.py">'
            '<lines><line number="1" hits="1"/></lines></class></classes></package></packages></coverage>'
        )
        self.assertEqual(self.artifact("create", kind="python").returncode, 0)
        self.assertEqual(self.artifact("verify", kind="python").returncode, 0)
        self.report.write_text(self.report.read_text().replace("Sources/ml/rpc.py", "Tests/test_rpc.py"))
        self.assertNotEqual(self.artifact("create", kind="python").returncode, 0)

    def test_lcov_export_filters_dependencies_and_merges_hits(self):
        lcov = self.directory / "input.lcov"
        lcov.write_text(
            f"SF:{ROOT}/Sources/App.swift\nDA:1,0\nend_of_record\n"
            f"SF:{ROOT}/Sources/App.swift\nDA:1,2\nend_of_record\n"
            f"SF:{ROOT}/.build/checkouts/vendor.swift\nDA:1,9\nend_of_record\n"
        )
        result = self.convert(lcov)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('path="Sources/App.swift"', self.report.read_text())
        self.assertIn('covered="true"', self.report.read_text())
        self.assertNotIn("vendor", self.report.read_text())

    def test_lcov_export_rejects_missing_or_empty_application_data(self):
        lcov = self.directory / "input.lcov"
        self.assertNotEqual(self.convert(lcov).returncode, 0)
        lcov.write_text(f"SF:{ROOT}/Tests/Test.swift\nDA:1,1\nend_of_record\n")
        self.assertNotEqual(self.convert(lcov).returncode, 0)

    def convert(self, lcov):
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/lcov-to-sonar.py"), str(lcov), str(self.report), str(ROOT)],
            capture_output=True, text=True, check=False,
        )

    def test_binary_resolves_native_and_xcbuild_bundle_names(self):
        for name in ("AudioWhisperPackageTests", "AudioWhisperTests"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                binary = directory / f"{name}.xctest" / "Contents" / "MacOS" / name
                binary.parent.mkdir(parents=True)
                binary.touch()
                result = self.resolve_binary(directory)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), str(binary))

    def test_binary_rejects_missing_incomplete_and_ambiguous_bundles(self):
        self.assertNotEqual(self.resolve_binary(self.directory).returncode, 0)
        (self.directory / "First.xctest").mkdir()
        self.assertNotEqual(self.resolve_binary(self.directory).returncode, 0)
        (self.directory / "Second.xctest").mkdir()
        self.assertNotEqual(self.resolve_binary(self.directory).returncode, 0)

    def resolve_binary(self, directory):
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/coverage-test-binary.py"), str(directory)],
            capture_output=True, text=True, check=False,
        )


if __name__ == "__main__":
    unittest.main()
