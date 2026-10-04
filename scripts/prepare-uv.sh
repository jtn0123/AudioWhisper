#!/bin/bash
set -euo pipefail

# Published checksums from https://github.com/astral-sh/uv/releases/tag/0.8.5.
# Verify both downloads before extraction or execution, then build a universal tool.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
uv_tools_dir="$repo_root/.build/tools/uv-0.8.5"
mkdir -p "$uv_tools_dir"
for uv_arch in aarch64 x86_64; do
  case "$uv_arch" in
    aarch64) uv_expected="467e875ac84ac2155f048b56e33741d7dee6f02369048d5b6c05b74b745411e2" ;;
    x86_64) uv_expected="9ee5b34975ab4659345fc96cc08098d7ec871cdfa969a5774894bcaebdaf3b58" ;;
  esac
  uv_archive="$uv_tools_dir/uv-$uv_arch-apple-darwin.tar.gz"
  if [ ! -f "$uv_archive" ]; then
    curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
      "https://github.com/astral-sh/uv/releases/download/0.8.5/uv-$uv_arch-apple-darwin.tar.gz" \
      --output "$uv_archive.download"
    mv "$uv_archive.download" "$uv_archive"
  fi
  uv_actual=$(shasum -a 256 "$uv_archive" | awk '{print $1}')
  [ "$uv_actual" = "$uv_expected" ] || { echo "uv archive checksum mismatch: $uv_arch" >&2; exit 1; }
  tar -xzf "$uv_archive" -C "$uv_tools_dir" "uv-$uv_arch-apple-darwin/uv"
done
uv_output="${1:-$repo_root/Sources/Resources/bin/uv}"
mkdir -p "$(dirname "$uv_output")"
lipo -create "$uv_tools_dir/uv-aarch64-apple-darwin/uv" \
  "$uv_tools_dir/uv-x86_64-apple-darwin/uv" -output "$uv_output"
chmod +x "$uv_output"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime \
    --entitlements "$repo_root/AudioWhisper.entitlements" "$uv_output"
else
  codesign --force --sign - "$uv_output"
fi
