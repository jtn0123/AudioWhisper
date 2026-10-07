#!/usr/bin/env python3
"""Stage, validate and atomically replace the signed local rebuild."""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

TARGET = Path("/Applications/AudioWhisper Rebuild.app")
BUNDLE_ID = "com.audiowhisper.rebuild"


def verify(app):
    with (app / "Contents/Info.plist").open("rb") as handle:
        if plistlib.load(handle).get("CFBundleIdentifier") != BUNDLE_ID:
            raise ValueError("Package is not AudioWhisper Rebuild")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    result = subprocess.run(["codesign", "-d", "-r-", str(app)],
                            capture_output=True, text=True, check=True)
    lines = (result.stdout + result.stderr).splitlines()
    requirement = next((line for line in lines if line.startswith("designated =>")), "")
    if not requirement or "certificate" not in requirement:
        raise ValueError("Rebuild needs a persistent signing certificate; use --local-signing")
    return requirement


def process_ids(app):
    executable = str(app / "Contents/MacOS/AudioWhisper")
    rows = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True).splitlines()
    return [int(parts[0]) for row in rows if len(parts := row.strip().split(maxsplit=1)) == 2
            and parts[1] == executable]


def stop(app):
    for pid in process_ids(app):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 10
    while process_ids(app):
        if time.monotonic() >= deadline:
            raise RuntimeError("The installed rebuild did not stop; its bundle was left intact")
        time.sleep(0.1)


def launch(app):
    subprocess.run(["open", str(app)], check=True)


def install(source, destination=TARGET):
    source = Path(source)
    destination = Path(destination)
    if destination != TARGET or destination.is_symlink():
        raise ValueError("Only the exact AudioWhisper Rebuild destination is allowed")
    if source.is_symlink() or not source.is_dir() or source.suffix != ".app":
        raise ValueError("Source must be a complete app directory, not a symlink")
    if source.resolve() == destination.resolve():
        raise ValueError("Source and installed app must differ")
    requirement = verify(source)
    if destination.exists() and verify(destination) != requirement:
        raise ValueError("Signing identity changed; refusing to churn existing permissions")
    staging = Path(tempfile.mkdtemp(prefix=".AudioWhisper-stage-", dir=destination.parent))
    staged = staging / destination.name
    backup = None
    try:
        subprocess.run(["ditto", str(source), str(staged)], check=True)
        if verify(staged) != requirement:
            raise ValueError("Staged signing identity did not match the source")
        stop(destination)
        if destination.exists():
            backups = destination.parent / ".AudioWhisperBackups"
            if backups.is_symlink():
                raise ValueError("Backup directory must not be a symlink")
            backups.mkdir(exist_ok=True)
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            backup = backups / f"{stamp}-{uuid.uuid4().hex[:8]}.app"
            destination.rename(backup)
        try:
            staged.rename(destination)
            verify(destination)
            launch(destination)
        except Exception:
            stop(destination)
            if destination.exists():
                destination.rename(staging / "failed.app")
            if backup is not None:
                backup.rename(destination)
                launch(destination)
            raise
    finally:
        shutil.rmtree(staging)
    print(f"Installed and launched {destination}")
    if backup is not None:
        print(f"Previous signed build retained at {backup}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    try:
        install(args.source)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Install failed: {error}\n")


if __name__ == "__main__":
    main()
