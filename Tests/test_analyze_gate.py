from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AnalyzeGateTests(unittest.TestCase):
    def run_gate(self, stdout="[]", stderr="Done analyzing! Found 0 violations, 0 serious in 2 files.\n",
                 status=0, log="compiler invocation"):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            compiler = directory / "compiler.log"
            if log is not None:
                compiler.write_text(log)
            fake = directory / "swiftlint"
            fake.write_text(f"#!{sys.executable}\nimport sys\n"
                            f"print({stdout!r})\nprint({stderr!r}, file=sys.stderr)\n"
                            f"sys.exit({status})\n")
            fake.chmod(0o700)
            return subprocess.run(
                [sys.executable, str(ROOT / "scripts/analyze-gate.py"), str(compiler),
                 "--swiftlint", str(fake), "--output", str(directory / "report.json")],
                text=True, capture_output=True, check=False,
            )

    def test_empty_but_completed_analysis_passes(self):
        self.assertEqual(self.run_gate().returncode, 0)

    def test_execution_and_indexing_failures_are_rejected(self):
        for kwargs in ({"log": None}, {"log": ""}, {"status": 1}, {"status": 2},
                       {"stderr": "Cannot index file\nDone analyzing! Found 0 violations, 0 serious in 2 files."},
                       {"stderr": ""}, {"stderr": "Done analyzing! Found 0 violations, 0 serious in 0 files."},
                       {"stdout": ""}, {"stdout": "{}"}):
            with self.subTest(kwargs=kwargs):
                self.assertNotEqual(self.run_gate(**kwargs).returncode, 0)

    def test_rule_findings_are_gated(self):
        self.assertNotEqual(self.run_gate(stdout=json.dumps([{"rule_id": "unused_import"}])).returncode, 0)
        self.assertEqual(self.run_gate(stdout=json.dumps([{"rule_id": "unused_declaration"}]*30)).returncode, 0)
        self.assertNotEqual(self.run_gate(stdout=json.dumps([{"rule_id": "unused_declaration"}]*31)).returncode, 0)


if __name__ == "__main__":
    unittest.main()
