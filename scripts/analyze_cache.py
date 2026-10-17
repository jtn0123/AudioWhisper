"""Fingerprint complete analyzer inputs and store verified report bundles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess


def fingerprint(root, context):
    root = root.resolve()
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root)
    paths = {Path(os.fsdecode(name)) for name in tracked.split(b'\0') if name}
    # Include generated and untracked inputs too, especially VersionInfo.swift.
    for directory in ('Sources', 'Tests'):
        paths.update(path.relative_to(root) for path in (root / directory).rglob('*') if path.is_file())
    paths.update(path.relative_to(root) for path in root.glob('.swiftlint*') if path.is_file())
    paths.update(Path(name) for name in ('scripts/analyze_cache.py', 'scripts/analyze-gate.py')
                 if (root / name).is_file())
    digest = hashlib.sha256(json.dumps({'root': str(root), 'context': context}, sort_keys=True).encode())
    for relative in sorted(paths):
        # These directories and root Markdown are evidence/docs, not compiler inputs.
        if relative.parts[0] in ('.Codex', 'docs') or (len(relative.parts) == 1 and relative.suffix == '.md'):
            continue
        path = root / relative
        digest.update(os.fsencode(relative.as_posix()) + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest() if path.exists() else b'missing\0')
    return digest.hexdigest()


def toolchain_context(swiftlint):
    commands = {
        'xcode': ['xcodebuild', '-version'],
        'swift': ['swift', '--version'],
        'sdk': ['xcrun', '--sdk', 'macosx', '--show-sdk-build-version'],
        'os': ['sw_vers', '-buildVersion'],
        'swiftlint': [swiftlint, 'version'],
    }
    context = {name: subprocess.check_output(command, stderr=subprocess.STDOUT, text=True).strip()
               for name, command in commands.items()}
    executable = shutil.which(swiftlint)
    if executable is None:
        raise ValueError('SwiftLint executable not found')
    context['swiftlint_sha256'] = hashlib.sha256(Path(executable).read_bytes()).hexdigest()
    context['architecture'] = platform.machine()
    prefixes = ('SWIFT', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET', 'OTHER_SWIFT', 'DEVELOPER_DIR', 'TOOLCHAINS')
    context['environment'] = {key: value for key, value in os.environ.items() if key.startswith(prefixes)}
    return context


def read_bundle(directory, key):
    try:
        manifest = json.loads((directory / 'manifest.json').read_text())
        report = (directory / 'report.json').read_bytes()
        diagnostics = (directory / 'diagnostics.txt').read_bytes()
        if (manifest['version'] != 1 or manifest['key'] != key
                or type(manifest['status']) is not int
                or manifest['report_sha256'] != hashlib.sha256(report).hexdigest()
                or manifest['diagnostics_sha256'] != hashlib.sha256(diagnostics).hexdigest()):
            return None
        return report.decode(), diagnostics.decode(), manifest['status']
    except (OSError, ValueError, KeyError, TypeError):
        return None


def write_bundle(directory, key, report, diagnostics, status):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'report.json').write_text(report)
    (directory / 'diagnostics.txt').write_text(diagnostics)
    manifest = {'version': 1, 'key': key, 'status': status,
                'report_sha256': hashlib.sha256(report.encode()).hexdigest(),
                'diagnostics_sha256': hashlib.sha256(diagnostics.encode()).hexdigest()}
    temporary = directory / 'manifest.tmp'
    temporary.write_text(json.dumps(manifest, sort_keys=True))
    temporary.replace(directory / 'manifest.json')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swiftlint', default='swiftlint')
    args = parser.parse_args()
    print(fingerprint(Path.cwd(), toolchain_context(args.swiftlint)))
