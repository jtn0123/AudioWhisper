from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AnalyzeGateTests(unittest.TestCase):
    def run_gate(self, stdout="[]", stderr=None, status=0, log="compiler invocation"):
        if stderr is None:
            try:
                rows = json.loads(stdout)
                serious = sum(row.get("severity") == "Error" for row in rows)
                stderr = f"Done analyzing! Found {len(rows)} violations, {serious} serious in 2 files.\n"
            except (ValueError, AttributeError, TypeError):
                stderr = "Done analyzing! Found 0 violations, 0 serious in 2 files.\n"
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
        imports = [{"rule_id": "unused_import", "severity": "Warning"}]
        declarations = [{"rule_id": "unused_declaration", "severity": "Error"}]
        self.assertNotEqual(self.run_gate(stdout=json.dumps(imports)).returncode, 0)
        self.assertEqual(self.run_gate(stdout=json.dumps(declarations * 30), status=2).returncode, 0)
        self.assertNotEqual(self.run_gate(stdout=json.dumps(declarations * 31), status=2).returncode, 0)

    def test_incomplete_or_inconsistent_findings_are_rejected(self):
        declaration = json.dumps([{"rule_id": "unused_declaration", "severity": "Error"}])
        for kwargs in (
            {"stdout": declaration, "status": 0},
            {"stdout": declaration, "status": 2,
             "stderr": "Done analyzing! Found 2 violations, 1 serious in 2 files."},
            {"stdout": declaration, "status": 2,
             "stderr": "Done analyzing! Found 1 violation, 0 serious in 2 files."},
            {"stdout": declaration, "status": 2,
             "stderr": "Cannot index file\nDone analyzing! Found 1 violation, 1 serious in 2 files."},
            {"stdout": json.dumps([{"rule_id": "unused_declaration"}]), "status": 2},
            {"stdout": json.dumps([{"rule_id": "unknown_rule", "severity": "Error"}]), "status": 2},
        ):
            with self.subTest(kwargs=kwargs):
                self.assertNotEqual(self.run_gate(**kwargs).returncode, 0)


if __name__ == "__main__":
    unittest.main()
