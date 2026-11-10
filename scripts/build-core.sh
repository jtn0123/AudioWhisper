#!/usr/bin/env bash
# Builds the Rust transcript rules (Vendor/AudioWhisper-Core) into
# .build/awcore/libawcore.a, universal (arm64 + x86_64), which Package.swift
# links. Does nothing when the library is newer than the core's sources, so it
# is cheap to run before every build. Needs rustup: the core pins its own
# toolchain in rust-toolchain.toml, which rustup installs on first use.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

core="Vendor/AudioWhisper-Core"
if [[ ! -x "$core/tools/build-macos.sh" ]]; then
  echo "❌ $core is empty. Run: git submodule update --init" >&2
  exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "❌ cargo not found. Install Rust with rustup: https://rustup.rs" >&2
  exit 1
fi
"$core/tools/build-macos.sh" "$PWD/.build/awcore"
