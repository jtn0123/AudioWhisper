#!/usr/bin/env python3
"""Drive only a Tart guest through its password-protected loopback VNC server.

Install vncdotool in a dedicated venv. Pass Tart's private run log via --log;
credentials never appear in command arguments or output. No host key injection.
"""
import argparse
import json
from pathlib import Path
import re
import time
from urllib.parse import unquote, urlparse

from vncdotool import api
from vncdotool.client import VNCDoToolFactory


class GuestFactory(VNCDoToolFactory):
    force_caps = True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--key")
    parser.add_argument("--down")
    parser.add_argument("--up")
    parser.add_argument("--type")
    parser.add_argument("--click", type=int, nargs=2, metavar=("X", "Y"))
    parser.add_argument("--sequence", type=Path, help="JSON list of guest actions on one connection")
    args = parser.parse_args()
    match = re.search(r"vnc://\S+", args.log.read_text())
    if match is None:
        parser.error("Tart has not published a VNC endpoint yet")
    endpoint = urlparse(match.group())
    if endpoint.hostname != "127.0.0.1" or endpoint.port is None:
        parser.error("Only Tart's loopback endpoint is allowed")
    with api.connect(f"127.0.0.1::{endpoint.port}", password=unquote(endpoint.password or ""),
                     factory_class=GuestFactory, timeout=15) as client:
        if args.sequence:
            for action in json.loads(args.sequence.read_text()):
                operation, value = action["action"], action["value"]
                if operation == "key":
                    client.keyPress(value)
                elif operation == "down":
                    client.keyDown(value)
                elif operation == "up":
                    client.keyUp(value)
                elif operation == "click":
                    client.mouseMove(*value)
                    client.mousePress(1)
                elif operation == "capture":
                    Path(value).parent.mkdir(parents=True, exist_ok=True)
                    client.captureScreen(value)
                elif operation == "pause" and 0 <= value <= 30:
                    time.sleep(value)
                else:
                    parser.error(f"Unsupported guest action: {operation}")
        if args.click:
            client.mouseMove(*args.click)
            client.mousePress(1)
        if args.key:
            client.keyPress(args.key)
        if args.down:
            client.keyDown(args.down)
        if args.up:
            client.keyUp(args.up)
        if args.type:
            for character in args.type:
                client.keyPress(character)
        if args.capture:
            args.capture.parent.mkdir(parents=True, exist_ok=True)
            client.pause(0.35)
            client.captureScreen(str(args.capture))
            print(f"Guest screenshot: {args.capture}")


if __name__ == "__main__":
    main()
