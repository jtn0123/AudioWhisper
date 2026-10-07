"""Acceptance reporting must never turn absent/blocked checks into a pass."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "unattended_acceptance", Path(__file__).with_name("run-unattended-acceptance.py"))
assert SPEC is not None and SPEC.loader is not None
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class AcceptanceReportingTests(unittest.TestCase):
    def test_success_uses_final_total_instead_of_summing_nested_suites(self):
        log = ("Executed 3 tests, with 0 failures (0 unexpected)\n"
               "Executed 7 tests, with 0 failures (0 unexpected)")
        result = RUNNER.outcome(log, 0, False)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["tests"], 7)

    def test_skipped_engine_cannot_count_as_pass(self):
        result = RUNNER.outcome("Executed 2 tests, with 2 tests skipped, with 0 failures", 0, False)
        self.assertEqual(result["status"], "incomplete")
        self.assertEqual(result["skipped"], 2)

    def test_zero_tests_or_missing_summary_cannot_count_as_pass(self):
        for log in ("Build complete!", "Executed 0 tests, with 0 failures"):
            self.assertEqual(RUNNER.outcome(log, 0, False)["status"], "incomplete")

    def test_crash_and_assertion_failures_override_success(self):
        self.assertEqual(RUNNER.outcome("Executed 7 tests, with 0 failures", -11, False)["status"], "failed")
        self.assertEqual(RUNNER.outcome("Executed 7 tests, with 1 failure", 0, False)["status"], "failed")

    def test_timeout_cannot_count_as_pass(self):
        self.assertEqual(RUNNER.outcome("Executed 7 tests, with 0 failures", 0, True)["status"], "timeout")

    def test_hung_process_is_terminated_and_reported_without_a_prompt(self):
        popen = subprocess.Popen
        children = []

        def hung_command(_command, **kwargs):
            child = popen([sys.executable, "-c", "import time; time.sleep(60)"], **kwargs)
            children.append(child)
            return child

        with tempfile.TemporaryDirectory() as directory, patch.object(RUNNER.subprocess, "Popen", hung_command):
            result = RUNNER.run_stage("hung", "unused", Path(directory), 1, dict(os.environ))
        self.assertEqual(result["status"], "timeout")
        self.assertIsNotNone(children[0].poll(), "The timed-out child must not keep running")


if __name__ == "__main__":
    unittest.main()
