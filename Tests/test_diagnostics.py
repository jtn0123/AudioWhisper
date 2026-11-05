"""Operational metadata stays request-local and contains no model inputs."""
import unittest
from ml.diagnostics import model_load, operation


class DiagnosticsTests(unittest.TestCase):
    def test_cold_warm_and_reset(self):
        cache = {}

        @model_load(cache)
        def load(repo):
            cache[repo] = object()
            return cache[repo]

        def run():
            load("model")
            return {"success": True, "text": "fixture"}

        cold = operation(run)["diagnostics"]
        warm = operation(run)["diagnostics"]
        self.assertEqual(cold["cache"], "cold")
        self.assertGreaterEqual(cold["operationMilliseconds"], cold["loadMilliseconds"])
        self.assertEqual(warm["cache"], "warm")
        self.assertEqual(warm["loadMilliseconds"], 0)
        self.assertEqual(set(cold), {"cache", "loadMilliseconds", "operationMilliseconds", "cpuSeconds", "peakResidentBytes"})
        self.assertNotIn("model", repr(cold))
        with self.assertRaises(ValueError):
            operation(lambda: (_ for _ in ()).throw(ValueError("private input")))
        reset = operation(lambda: {"text": "new request"})["diagnostics"]
        self.assertEqual(reset["cache"], "unknown")
        self.assertEqual(reset["loadMilliseconds"], 0)


if __name__ == "__main__":
    unittest.main()
