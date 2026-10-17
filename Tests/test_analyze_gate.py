from pathlib import Path
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('analyze_cache', ROOT / 'scripts/analyze_cache.py')
CACHE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CACHE)


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


class AnalyzerCacheTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.compiler = self.directory / 'compiler.log'
        self.compiler.write_text('compiler invocation')
        self.fake = self.directory / 'swiftlint'
        self.calls = self.directory / 'calls'
        self.bundle = self.directory / 'cache'
        self.key = 'a' * 64
        self.write_fake()

    def write_fake(self, rows=None, status=0):
        rows = rows or []
        serious = sum(row['severity'] == 'Error' for row in rows)
        stderr = f'Done analyzing! Found {len(rows)} violations, {serious} serious in 2 files.'
        self.fake.write_text(f'#!{sys.executable}\nfrom pathlib import Path\nimport sys\n'
                             f'p=Path({str(self.calls)!r})\n'
                             'p.write_text(p.read_text()+"x" if p.exists() else "x")\n'
                             f'print({json.dumps(rows)!r})\nprint({stderr!r},file=sys.stderr)\n'
                             f'sys.exit({status})\n')
        self.fake.chmod(0o700)

    def run_gate(self, *extra):
        return subprocess.run(
            [sys.executable, str(ROOT / 'scripts/analyze-gate.py'), str(self.compiler),
             '--swiftlint', str(self.fake), '--output', str(self.directory / 'report.json'),
             '--cache-directory', str(self.bundle), '--cache-key', self.key, *extra],
            capture_output=True, text=True, check=False,
        )

    def test_cache_hit_revalidates_without_compiler_log_or_analyzer_execution(self):
        self.assertEqual(self.run_gate().returncode, 0)
        self.compiler.unlink()
        result = self.run_gate('--check-cache')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('gates revalidated', result.stdout)
        self.assertEqual(self.calls.read_text(), 'x')

    def test_invalid_or_incomplete_cache_falls_back_to_full_analysis(self):
        self.assertEqual(self.run_gate().returncode, 0)
        for name, content in [('manifest.json', '{}'), ('report.json', '[{}]'),
                              ('diagnostics.txt', 'partial analysis'), ('manifest.json', 'not JSON')]:
            with self.subTest(name=name, content=content):
                before = self.calls.read_text()
                (self.bundle / name).write_text(content)
                result = self.run_gate()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls.read_text(), before+'x')
                self.assertNotIn('::error::', result.stderr)

    def test_different_input_key_forces_full_analysis(self):
        self.assertEqual(self.run_gate().returncode, 0)
        self.key = 'b' * 64
        self.assertEqual(self.run_gate().returncode, 0)
        self.assertEqual(self.calls.read_text(), 'xx')

    def test_cached_findings_cannot_bypass_a_stricter_gate(self):
        self.write_fake([{'rule_id': 'unused_declaration', 'severity': 'Error'}], status=2)
        self.assertEqual(self.run_gate().returncode, 0)
        self.assertNotEqual(self.run_gate('--check-cache', '--baseline', '0').returncode, 0)
        rows = [{'rule_id': 'unused_import', 'severity': 'Warning'}]
        CACHE.write_bundle(self.bundle, self.key, json.dumps(rows),
                           'Done analyzing! Found 1 violation, 0 serious in 2 files.', 0)
        self.assertNotEqual(self.run_gate('--check-cache').returncode, 0)

    def test_failed_analysis_never_creates_a_cache(self):
        self.write_fake([{'rule_id': 'unused_import', 'severity': 'Warning'}])
        self.assertNotEqual(self.run_gate().returncode, 0)
        self.assertFalse((self.bundle / 'manifest.json').exists())

    def test_progress_is_visible_before_the_analyzer_finishes(self):
        finished = self.directory / 'finished'
        resume = self.directory / 'resume'
        self.fake.write_text(f'#!{sys.executable}\nfrom pathlib import Path\nimport sys,time\n'
                             'print("Analyzing first.swift",file=sys.stderr,flush=True)\n'
                             f'resume=Path({str(resume)!r})\ndeadline=time.monotonic()+5\n'
                             'while not resume.exists() and time.monotonic()<deadline: time.sleep(0.01)\n'
                             f'Path({str(finished)!r}).touch()\nprint("[]")\n'
                             'print("Done analyzing! Found 0 violations, 0 serious in 2 files.",file=sys.stderr)\n')
        self.fake.chmod(0o700)
        with subprocess.Popen(
            [sys.executable, str(ROOT / 'scripts/analyze-gate.py'), str(self.compiler),
             '--swiftlint', str(self.fake), '--output', str(self.directory / 'report.json')],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        ) as process:
            try:
                self.assertEqual(process.stderr.readline().strip(), 'Analyzing first.swift')
                self.assertFalse(finished.exists(), 'Progress was buffered until analysis completed')
            finally:
                resume.touch()
                process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0)


class AnalyzerFingerprintTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ('Sources/App.swift', 'Tests/AppTests.swift', 'Package.resolved', '.swiftlint.yml',
                     'README.md', 'docs/guide.md', '.Codex/evidence.txt', '.github/workflows/ci.yml'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', 'add', '.'], cwd=self.root, check=True)
        self.original = CACHE.fingerprint(self.root, {'toolchain': 'one'})

    def test_changes_anywhere_in_the_graph_or_toolchain_invalidate(self):
        for name in ('Sources/App.swift', 'Tests/AppTests.swift', 'Package.resolved', '.swiftlint.yml',
                     '.github/workflows/ci.yml'):
            with self.subTest(name=name):
                path = self.root / name
                previous = path.read_text()
                path.write_text(previous+'changed')
                self.assertNotEqual(CACHE.fingerprint(self.root, {'toolchain': 'one'}), self.original)
                path.write_text(previous)
        self.assertNotEqual(CACHE.fingerprint(self.root, {'toolchain': 'two'}), self.original)

    def test_generated_untracked_and_removed_swift_inputs_invalidate(self):
        path = self.root / 'Sources/VersionInfo.swift'
        path.write_text('generated version')
        self.assertNotEqual(CACHE.fingerprint(self.root, {'toolchain': 'one'}), self.original)
        path.unlink()
        path = self.root / 'Tests/NewTests.swift'
        path.write_text('new tests')
        self.assertNotEqual(CACHE.fingerprint(self.root, {'toolchain': 'one'}), self.original)
        path.unlink()
        (self.root / 'Sources/App.swift').unlink()
        self.assertNotEqual(CACHE.fingerprint(self.root, {'toolchain': 'one'}), self.original)

    def test_documentation_only_changes_reuse_the_complete_graph_result(self):
        for name in ('README.md', 'docs/guide.md', '.Codex/evidence.txt'):
            (self.root / name).write_text('updated documentation')
        self.assertEqual(CACHE.fingerprint(self.root, {'toolchain': 'one'}), self.original)


if __name__ == "__main__":
    unittest.main()
