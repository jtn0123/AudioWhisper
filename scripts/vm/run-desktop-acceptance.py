#!/usr/bin/env python3
"""Exercise the real app in a prepared Tart guest, never the host desktop.

Guest setup and consent are prerequisites; a blocked step fails with evidence,
without asking the host user to click. Uses only public fixture audio and a
throwaway TextEdit document. Native macOS events remain synthetic VM events.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time


class Guest:
    def __init__(self, tart: str, vm: str, output: Path):
        self.command = [tart, "exec", vm]
        self.output = output

    def run(self, *args: str) -> str:
        result = subprocess.run(self.command + list(args), capture_output=True, timeout=45, check=True)
        return result.stdout.decode().strip()

    def script(self, *lines: str) -> str:
        args = ["/usr/bin/osascript"]
        for line in lines:
            args.extend(["-e", line])
        return self.run(*args)

    def state(self) -> dict:
        return json.loads(self.run("/Volumes/My Shared Files/qa/probe-v2"))

    def key(self, code: int, modifiers: str = "command down") -> None:
        self.script(f'tell application "System Events" to key code {code} using {{{modifiers}}}')

    def shortcut(self) -> None:
        self.key(15, "command down, option down, shift down")

    def capture(self, name: str) -> None:
        self.run("/usr/sbin/screencapture", "-x", "/tmp/audiowhisper-qa.png")
        image = subprocess.run(self.command + ["/bin/cat", "/tmp/audiowhisper-qa.png"],
                               capture_output=True, timeout=45, check=True).stdout
        (self.output / f"{name}.png").write_bytes(image)

    def wait(self, predicate, timeout: int = 20) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.state()
            if predicate(state):
                return state
            time.sleep(0.3)
        self.capture("blocked")
        raise RuntimeError(f"Guest did not reach expected state within {timeout}s")


def hud(state: dict) -> dict | None:
    return next((window["bounds"] for window in state["windows"]
                 if window["visible"] and window["bounds"]["Width"] == 380
                 and window["bounds"]["Height"] == 230), None)


def contained(state: dict, frame: dict) -> bool:
    # QA guest has one display. Quartz uses an upper-left origin.
    assert len(state["screens"]) == 1, "Run on the QA guest's single display"
    screen = state["screens"][0]
    x, y, width, height = screen["visible"]
    top = screen["frame"][3] - (y + height)
    return (x <= frame["X"] and frame["X"] + frame["Width"] <= x + width
            and top <= frame["Y"] and frame["Y"] + frame["Height"] <= top + height)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tart", required=True)
    parser.add_argument("--vm", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cycles", type=int, default=10)
    args = parser.parse_args()
    if not args.vm.startswith("audiowhisper-qa-") or not 1 <= args.cycles <= 30:
        parser.error("Use a named AudioWhisper QA guest and 1-30 cycles")
    args.output.mkdir(parents=True, exist_ok=False)
    guest = Guest(args.tart, args.vm, args.output)
    report = {"status": "running", "vm": args.vm, "checks": [],
              "limits": ["synthetic guest key events", "virtual microphone and public audio",
                         "not physical host hardware", "not notarized release acceptance"]}
    try:
        report["os"] = guest.run("/usr/bin/sw_vers")
        guest.run("/usr/bin/codesign", "--verify", "--deep", "--strict", "/Applications/AudioWhisper.app")
        report["signature_verified"] = True
        report["binary_sha256"] = guest.run("/usr/bin/shasum", "-a", "256",
                                            "/Applications/AudioWhisper.app/Contents/MacOS/AudioWhisper").split()[0]
        guest.run("/usr/bin/open", "-a", "TextEdit")
        guest.wait(lambda state: state["frontmost"] == "com.apple.TextEdit")
        assert hud(guest.state()) is None, "Begin with recording idle"
        # Initialize only the disposable document. No real user audio or text.
        guest.run("/bin/sh", "-c", 'printf "SMART PASTE TEST: " | pbcopy')
        guest.key(0)
        guest.key(9)
        for number in range(1, args.cycles + 1):
            guest.run("/usr/bin/open", "-a", "TextEdit")
            guest.wait(lambda state: state["frontmost"] == "com.apple.TextEdit")
            baseline = guest.state()["clipboard"]
            guest.shortcut()
            state = guest.wait(lambda state: hud(state) is not None)
            frame = hud(state)
            assert contained(state, frame), "Recorder escaped the visible display"
            if number == 1:
                guest.capture("recording-visible")
            guest.run("/Volumes/My Shared Files/qa/input", "click",
                      str(frame["X"] + 47), str(frame["Y"] + frame["Height"] - 36))
            state = guest.wait(lambda state: hud(state) is None)
            assert state["clipboard"] == baseline, "Cancel unexpectedly delivered a transcript"
            assert state["frontmost"] == "com.apple.TextEdit", "Cancel stole focus from the destination"
            report["checks"].append({"case": f"start-cancel-{number}", "status": "passed",
                                      "frame": frame, "frontmost_after_cancel": state["frontmost"]})
            print(f"start/cancel {number}: passed", flush=True)
        guest.run("/usr/bin/open", "-a", "TextEdit")
        guest.wait(lambda state: state["frontmost"] == "com.apple.TextEdit")
        guest.shortcut()
        guest.wait(lambda state: hud(state) is not None)
        guest.run("/usr/bin/afplay", "/Volumes/My Shared Files/qa/speech_sample.wav")
        guest.shortcut()
        state = guest.wait(lambda state: hud(state) is None and "quick brown fox" in state["clipboard"].lower(), 90)
        transcript = state["clipboard"]
        # Allow foreground activation and actual app-generated Cmd-V to finish.
        time.sleep(2)
        guest.capture("smart-paste-result")
        assert guest.state()["frontmost"] == "com.apple.TextEdit", "Paste target changed"
        guest.key(0)
        guest.key(8)
        time.sleep(0.3)
        document = guest.state()["clipboard"]
        report["observed_delivery"] = {"transcript": transcript, "document": document}
        assert document == "SMART PASTE TEST: " + transcript, "TextEdit did not receive exactly one paste"
        report["checks"].append({"case": "record-stop-transcribe-paste", "status": "passed",
                                  "transcript": transcript, "document": document})
        guest.run("/usr/bin/codesign", "--verify", "--deep", "--strict", "/Applications/AudioWhisper.app")
        report["status"] = "passed"
        print("record/stop/transcribe/native paste: passed", flush=True)
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        try:
            guest.capture("failure")
        except Exception:
            pass
        print(f"Guest acceptance failed: {error}", flush=True)
    finally:
        (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
