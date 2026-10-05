#!/usr/bin/env python3
"""Run repeatable acceptance checks without microphone/Accessibility prompts.

Uses isolated settings, in-memory history and a named test pasteboard. Hardware,
consent, foreground PID and key events are injected in the deterministic checks.
--real-engines additionally runs actual Whisper inference on public fixture audio
(may download the base model). Neither mode proves physical hotkey/mic behavior.
"""

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parent.parent
STAGES = [
    ("setup", "RebuildSetupTests|RebuildModelVerificationTests"),
    ("capture", "RebuildStartupTests|RebuildSessionTests|AudioHardwarePreparationTests|AudioInputRoutingTests"),
    ("delivery", "RebuildDeliveryIntegrationTests"),
    ("paste-destination", "SmartPasteDestinationTests"),
    ("hold-events", "PressAndHoldKeyMonitorTests|PressAndHoldKeyMonitorLocalEventTests"),
]
ENGINE_FILTER = "LocalEngineFixtureTests/testWhisper"
SUMMARY = re.compile(r"Executed (\d+) tests?(?:, with (\d+) tests? skipped)?, with (\d+) failures?")


def outcome(log: str, returncode: int, timed_out: bool) -> dict[str, object]:
    """Zero tests or skipped tests cannot silently count as acceptance."""
    summaries = SUMMARY.findall(log)
    tests, skipped, failures = (0, 0, 0)
    if summaries:
        tests, skipped, failures = (int(value or "0") for value in summaries[-1])
    status = "passed"
    if timed_out:
        status = "timeout"
    elif returncode != 0 or failures:
        status = "failed"
    elif tests == 0 or skipped:
        status = "incomplete"
    return {"status": status, "tests": tests, "skipped": skipped, "failures": failures,
            "returncode": returncode}


def run_stage(name: str, test_filter: str, directory: Path, timeout: int,
              environment: dict[str, str]) -> dict[str, object]:
    log_path = directory / f"{name}.log"
    # Fixed shell code uses the project's toolchain discovery; filter is passed
    # as an argument, never interpolated into shell source.
    command = ["bash", "-c", '. scripts/lib/xcode-env.sh; ensure_xcode_toolchain || exit 1; '
               'exec swift test --no-parallel -Xswiftc -DTESTING --filter "$1"', "acceptance", test_filter]
    start = time.monotonic()
    timed_out = False
    with log_path.open("w") as stream:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            returncode = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                returncode = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                returncode = process.wait()
    result = outcome(log_path.read_text(errors="replace"), returncode, timed_out)
    result.update(name=name, filter=test_filter, log=str(log_path),
                  seconds=round(time.monotonic() - start, 2))
    print(f"{name}: {result['status']} ({result['tests']} tests, {result['skipped']} skipped)", flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--real-engines", action="store_true")
    parser.add_argument("--timeout", type=int, default=900, help="Maximum seconds per stage")
    parser.add_argument("--output", type=Path, help="New directory for logs and report.json")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    output = args.output or ROOT / ".build" / "acceptance" / str(uuid.uuid4())
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ)
    environment["AUDIOWHISPER_DEFAULTS_SUITE"] = f"com.audiowhisper.tests.acceptance.{uuid.uuid4()}"
    environment["OS_ACTIVITY_MODE"] = "disable"
    environment["RUN_E2E"] = "1" if args.real_engines else "0"
    stages = STAGES + ([("real-whisper", ENGINE_FILTER)] if args.real_engines else [])
    report: dict[str, object] = {
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
        "real_engine_requested": args.real_engines,
        "not_verified": ["physical microphone capture", "macOS consent persistence",
                         "OS global shortcut dispatch", "paste into an external application",
                         "physical hold-key down/up"],
        "checks": [],
    }
    checks: list[dict[str, object]] = []
    report["checks"] = checks
    report_path = output / "report.json"
    for name, test_filter in stages:
        checks.append(run_stage(name, test_filter, output, args.timeout, environment))
        report["status"] = "passed" if all(check["status"] == "passed" for check in checks) else "failed"
        report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Report: {report_path}")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
