#!/usr/bin/env python3
"""Give an already-built /tmp QA bundle its own identity, settings and data.

Does not launch the app, change macOS settings, or copy production data.
Build into /tmp first with scripts/build.sh --debug --local-signing --output.
"""
import argparse
from pathlib import Path
import plistlib
import subprocess
import uuid


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    temporary = Path("/tmp").resolve()
    if temporary not in app.parents or app.suffix != ".app":
        parser.error("QA staging only accepts a bundle inside /tmp")
    plist = app / "Contents/Info.plist"
    with plist.open("rb") as stream:
        settings = plistlib.load(stream)
    identity = "com.audiowhisper.qa.run" + uuid.uuid4().hex
    data = app.parent / "isolated-data"
    settings.update(CFBundleIdentifier=identity, CFBundleName="AudioWhisper QA", CFBundleDisplayName="AudioWhisper QA")
    settings["LSEnvironment"] = {
        "AUDIOWHISPER_DEFAULTS_SUITE": identity + ".settings",
        "AUDIOWHISPER_APP_SUPPORT_DIR": str(data),
    }
    for entry in settings.get("CFBundleURLTypes", []):
        entry["CFBundleURLSchemes"] = [identity.replace(".", "-")]
    with plist.open("wb") as stream:
        plistlib.dump(settings, stream)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    print(f"Bundle: {identity}\nData: {data}\nApp: {app}")


if __name__ == "__main__":
    main()
