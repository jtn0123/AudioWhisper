"""Reject broken coverage inputs and measure only the application."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CoverageGateTests(unittest.TestCase):
    def gate(self, threshold="38", covered=39, count=100, files=None):
        if files is None:
            files = [{"filename": str(ROOT / "Sources/App.swift"),
                      "summary": {"lines": {"covered": covered, "count": count}}},
                     {"filename": str(ROOT / ".build/checkouts/vendor/Sources/App.swift"),
                      "summary": {"lines": {"covered": 10000, "count": 10000}}}]
        with tempfile.TemporaryDirectory() as temporary:
            report = Path(temporary) / "coverage.json"
            report.write_text(json.dumps({"data": [{"files": files}]}))
            return subprocess.run([sys.executable, str(ROOT / "scripts/coverage-gate.py"),
                                   str(report), str(ROOT), threshold],
                                  capture_output=True, text=True, check=False)

    def test_application_coverage_passes_and_dependency_hits_cannot_hide_a_drop(self):
        self.assertEqual(self.gate().returncode, 0)
        result = self.gate(covered=37)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("37.00%", result.stdout)

    def test_invalid_threshold_cannot_silently_disable_the_gate(self):
        for threshold in ["nan", "inf", "-1", "101", "invalid"]:
            with self.subTest(threshold=threshold):
                self.assertNotEqual(self.gate(threshold=threshold).returncode, 0)

    def test_missing_empty_and_impossible_application_data_fail(self):
        for kwargs in [{"files": []}, {"files": {}}, {"files": [None]},
                       {"covered": 101}, {"covered": -1}, {"count": "100"},
                       {"covered": 0, "count": 0}]:
            with self.subTest(kwargs=kwargs):
                self.assertNotEqual(self.gate(**kwargs).returncode, 0)


if __name__ == "__main__":
    unittest.main()
