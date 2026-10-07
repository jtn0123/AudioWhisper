#!/usr/bin/env python3
"""Full-screen and hold-key checks inside the prepared macOS QA guest."""
import argparse
import importlib.util
import json
from pathlib import Path
import time

spec = importlib.util.spec_from_file_location("desktop", Path(__file__).with_name("run-desktop-acceptance.py"))
desktop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tart", required=True)
    parser.add_argument("--vm", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not args.vm.startswith("audiowhisper-qa-"):
        parser.error("Use a disposable AudioWhisper QA guest")
    args.output.mkdir(parents=True, exist_ok=False)
    guest = desktop.Guest(args.tart, args.vm, args.output)
    report = {"status": "running", "checks": []}

    def focus_text():
        guest.run("/usr/bin/open", "-a", "TextEdit")
        guest.wait(lambda state: state["frontmost"] == "com.apple.TextEdit")

    def document(prefix):
        focus_text()
        guest.run("/bin/sh", "-c", 'printf "%s" "$1" | pbcopy', "fixture", prefix)
        guest.key(0)
        guest.key(9)

    def fullscreen():
        return guest.script('tell application "System Events" to tell process "TextEdit" '
                            'to get value of attribute "AXFullScreen" of window 1') == "true"

    def deliver(prefix):
        guest.run("/usr/bin/afplay", "/Volumes/My Shared Files/qa/speech_sample.wav")
        guest.shortcut()
        state = guest.wait(lambda state: desktop.hud(state) is None and "quick brown fox" in state["clipboard"].lower(), 90)
        transcript = state["clipboard"]
        time.sleep(2)
        guest.key(0)
        guest.key(8)
        time.sleep(0.3)
        body = guest.state()["clipboard"]
        assert body == prefix + transcript, f"Native paste failed: {body!r}"
        return body

    try:
        focus_text()
        if fullscreen():
            guest.key(3, "command down, control down")
            time.sleep(2)
        guest.run("/usr/bin/open", "/Applications/AudioWhisper.app")
        guest.script('tell application "System Events" to tell process "AudioWhisper" to set frontmost to true')
        state = guest.wait(lambda state: any(w["visible"] and w["bounds"]["Width"] >= 870 for w in state["windows"]))
        workspace = next(w["bounds"] for w in state["windows"] if w["visible"] and w["bounds"]["Width"] >= 870)
        guest.run("/Volumes/My Shared Files/qa/input", "click", str(workspace["X"] + 85), str(workspace["Y"] + 429))
        time.sleep(0.5)
        guest.capture("preferences-minimum-size")
        document("FULLSCREEN TEST: ")
        guest.key(3, "command down, control down")
        time.sleep(2)
        assert fullscreen(), "TextEdit did not enter full screen"
        guest.shortcut()
        state = guest.wait(lambda state: desktop.hud(state) is not None)
        assert not any(w["visible"] and w["bounds"]["Width"] >= 870 for w in state["windows"]), \
            "Preferences covered the full-screen destination"
        assert desktop.contained(state, desktop.hud(state))
        guest.capture("overlay-over-fullscreen")
        body = deliver("FULLSCREEN TEST: ")
        guest.capture("paste-in-fullscreen")
        report["checks"].append({"case": "fullscreen-preferences-overlay-paste", "status": "passed", "document": body})
        print("full-screen isolation, overlay and native paste: passed", flush=True)
        guest.key(3, "command down, control down")
        time.sleep(2)
        assert not fullscreen()

        # Record through macOS's real modifier event stream; no injected app callbacks.
        guest.run("/bin/sh", "-c", 'defaults write com.audiowhisper.rebuild pressAndHoldEnabled -bool true; '
                  'defaults write com.audiowhisper.rebuild pressAndHoldKeyIdentifier -string leftOption; '
                  'defaults write com.audiowhisper.rebuild pressAndHoldMode -string hold; '
                  'killall AudioWhisper; open /Applications/AudioWhisper.app')
        document("HOLD TEST: ")
        guest.script('tell application "System Events" to key down option')
        flags = guest.state()["modifierFlags"]
        if not flags & 0x20:
            report["checks"].append({"case": "modifier-hold-release-paste", "status": "incomplete",
                "modifier_flags": flags,
                "reason": "Guest remote input supplies Option but omits physical Left Option state"})
            report["status"] = "incomplete"
            print("hold: incomplete (guest input lacks left/right modifier state)", flush=True)
        else:
            state = guest.wait(lambda state: desktop.hud(state) is not None)
            guest.capture("hold-recording")
            guest.run("/usr/bin/afplay", "/Volumes/My Shared Files/qa/speech_sample.wav")
            guest.script('tell application "System Events" to key up option')
            state = guest.wait(lambda state: desktop.hud(state) is None and "quick brown fox" in state["clipboard"].lower(), 90)
            transcript = state["clipboard"]
            time.sleep(2)
            guest.key(0)
            guest.key(8)
            time.sleep(0.3)
            body = guest.state()["clipboard"]
            assert body == "HOLD TEST: " + transcript, "Hold release did not paste exactly once"
            guest.capture("hold-release-paste")
            report["checks"].append({"case": "modifier-hold-release-paste", "status": "passed",
                                      "modifier_flags": flags, "document": body})
            print("hold/release/transcribe/native paste: passed", flush=True)
            report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        try:
            guest.capture("failure")
        except Exception:
            pass
        print(f"Extra guest acceptance failed: {error}", flush=True)
    finally:
        try:
            guest.script('tell application "System Events" to key up option')
            guest.run("/bin/sh", "-c", 'defaults write com.audiowhisper.rebuild pressAndHoldEnabled -bool false; '
                      'killall AudioWhisper; open /Applications/AudioWhisper.app')
        except Exception as error:
            report["cleanup_error"] = str(error)
            report["status"] = "failed"
        (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
