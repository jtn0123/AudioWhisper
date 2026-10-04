#!/bin/bash

# Needs `actool` (Xcode, not Command Line Tools) for Sources/Assets.xcassets.
# shellcheck source=scripts/lib/xcode-env.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/xcode-env.sh"
ensure_xcode_toolchain || exit 1

# Resource-complete AudioWhisper packaging. --debug reuses the host build;
# the default remains a universal release build.

# Change to repo root (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Parse command line arguments
NOTARIZE=false
DEBUG_BUILD=false
while [[ $# -gt 0 ]]; do
  case $1 in
  --debug)
    DEBUG_BUILD=true
    shift
    ;;
  --notarize)
    NOTARIZE=true
    shift
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [--debug | --notarize]"
    exit 1
    ;;
  esac
done

if [ "$DEBUG_BUILD" = true ] && [ "$NOTARIZE" = true ]; then
  echo "Debug packaging cannot be notarized; use the universal release build." >&2
  exit 1
fi

# Create entitlements file for hardened runtime
echo "Creating entitlements for hardened runtime..."
cat >AudioWhisper.entitlements <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

SIGNING_IDENTITY=""
SIGNING_NAME=""

if [ -n "$CODE_SIGN_IDENTITY" ]; then
  SIGNING_IDENTITY="$CODE_SIGN_IDENTITY"
else
  # Try to auto-detect signing identity in order of preference:
  # 1. Developer ID Application (paid account, best for distribution)
  # 2. Apple Development (free account, good for local development)
  # 3. Mac Developer (older certificate type)

  for CERT_TYPE in "Developer ID Application" "Apple Development" "Mac Developer"; do
    DETECTED_HASH=$(security find-identity -v -p codesigning | grep "$CERT_TYPE" | head -1 | awk '{print $2}')
    DETECTED_NAME=$(security find-identity -v -p codesigning | grep "$CERT_TYPE" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    if [ -n "$DETECTED_HASH" ]; then
      echo "🔍 Auto-detected signing identity: $DETECTED_NAME"
      SIGNING_IDENTITY="$DETECTED_HASH"
      SIGNING_NAME="$DETECTED_NAME"
      break
    fi
  done
fi

export SIGNING_IDENTITY
bash "$SCRIPT_DIR/prepare-uv.sh" || exit 1

# Generate version info
GIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date '+%Y-%m-%d')

# Capture bundled uv version (best effort — empty string if uv missing)
BUNDLED_UV_VERSION=""
if [ -x "Sources/Resources/bin/uv" ]; then
    BUNDLED_UV_VERSION=$("Sources/Resources/bin/uv" --version 2>/dev/null | awk '{print $2}' || echo "")
fi

# Capture bundled uv SHA-256 so the app can verify the binary at runtime
BUNDLED_UV_SHA256=""
if [ -f "Sources/Resources/bin/uv" ]; then
    BUNDLED_UV_SHA256=$(shasum -a 256 "Sources/Resources/bin/uv" | awk '{print $1}' || echo "")
fi

# Read version from VERSION file or use environment variable
DEFAULT_VERSION=$(cat VERSION | tr -d '[:space:]')
VERSION="${AUDIO_WHISPER_VERSION:-$DEFAULT_VERSION}"

echo "🎙️ Building AudioWhisper version $VERSION..."

# Update Info.plist with current version
if [ -f "Info.plist" ]; then
  echo "Updating Info.plist version to $VERSION..."
  # Update CFBundleShortVersionString
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist 2>/dev/null ||
    sed -i '' "s|<key>CFBundleShortVersionString</key>[[:space:]]*<string>[^<]*</string>|<key>CFBundleShortVersionString</key><string>$VERSION</string>|" Info.plist

  # Update CFBundleVersion (remove dots for build number)
  BUILD_NUMBER="${VERSION//./}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Info.plist 2>/dev/null ||
    sed -i '' "s|<key>CFBundleVersion</key>[[:space:]]*<string>[^<]*</string>|<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>|" Info.plist
fi

# Clean previous builds
if [ "$DEBUG_BUILD" = false ]; then rm -rf .build/release; fi
rm -rf AudioWhisper.app
rm -f Sources/AudioProcessorCLI

# Create version file from template
if [ -f "Sources/VersionInfo.swift.template" ]; then
  # BUNDLED_UV_* placeholders must be substituted before VERSION_PLACEHOLDER,
  # which is a substring of BUNDLED_UV_VERSION_PLACEHOLDER.
  sed -e "s/BUNDLED_UV_VERSION_PLACEHOLDER/$BUNDLED_UV_VERSION/g" \
    -e "s/BUNDLED_UV_SHA256_PLACEHOLDER/$BUNDLED_UV_SHA256/g" \
    -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    -e "s/GIT_HASH_PLACEHOLDER/$GIT_HASH/g" \
    -e "s/BUILD_DATE_PLACEHOLDER/$BUILD_DATE/g" \
    Sources/VersionInfo.swift.template >Sources/Utilities/VersionInfo.swift
  echo "Generated VersionInfo.swift from template"
else
  echo "Warning: VersionInfo.swift.template not found, using fallback"
  cat >Sources/Utilities/VersionInfo.swift <<EOF
import Foundation

struct VersionInfo {
    static let version = "$VERSION"
    static let gitHash = "$GIT_HASH"
    static let buildDate = "$BUILD_DATE"
    static let bundledUvVersion = "$BUNDLED_UV_VERSION"
    static let bundledUvSha256 = "$BUNDLED_UV_SHA256"

    static var displayVersion: String {
        if gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            return "\(version) (\(shortHash))"
        }
        return version
    }

    static var fullVersionInfo: String {
        var info = "AudioWhisper \(version)"
        if gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            info += " • \(shortHash)"
        }
        if buildDate.count > 0 {
            info += " • \(buildDate)"
        }
        return info
    }
}
EOF
fi

if [ "$DEBUG_BUILD" = true ]; then
  echo "📦 Building incremental debug bundle for the host..."
  swift build -c debug --product AudioWhisper || exit 1
  slice_dir="$(swift build -c debug --show-bin-path)" || exit 1
  RELEASE_BINARY="$slice_dir/AudioWhisper"
  [ -f "$RELEASE_BINARY" ] || exit 1
else
# Build for release, one architecture at a time, then lipo them together.
#
# `swift build --arch arm64 --arch x86_64` (the obvious way) cannot be used.
# Passing --arch routes the build through the XCBuild backend, and that backend
# rejects the package graph outright:
#
#   error: duplicate key found: 'ID(moduleName: "ArgmaxCLI", packageIdentity: argmax-oss-swift)'
#
# because argmax-oss-swift 1.0.0 declares two executable products pointing at
# the SAME target:
#
#     .executable(name: "argmax-cli",     targets: ["ArgmaxCLI"]),
#     .executable(name: "whisperkit-cli", targets: ["ArgmaxCLI"]),
#
# Using separate triples also avoids the duplicate executable-product graph.
# `--product AudioWhisper` does NOT avoid it — the graph is rejected before
# product selection. Xcode 26 hits this; a 6.4 toolchain tolerates it, which is
# why `make build` worked here and failed everywhere else.
#
# Building each slice with --triple keeps the ordinary SwiftPM backend, which
# has no such problem, and `lipo` gives us the same universal binary.
echo "📦 Building for release..."
UNIVERSAL_DIR=".build/universal"
rm -rf "$UNIVERSAL_DIR"
mkdir -p "$UNIVERSAL_DIR"

SLICES=()
for triple in arm64-apple-macosx x86_64-apple-macosx; do
  echo "   • $triple"
  swift build -c release --triple "$triple" --product AudioWhisper
  # Ask SwiftPM where it put the binary rather than guessing: the layout has
  # already moved once (.build/apple -> .build/out) and broke this script.
  slice_dir="$(swift build -c release --triple "$triple" --show-bin-path)"
  if [ ! -f "$slice_dir/AudioWhisper" ]; then
    echo "❌ Build failed - no $triple binary at $slice_dir"
    exit 1
  fi
  cp "$slice_dir/AudioWhisper" "$UNIVERSAL_DIR/AudioWhisper-$triple"
  SLICES+=("$UNIVERSAL_DIR/AudioWhisper-$triple")
done

RELEASE_BINARY="$UNIVERSAL_DIR/AudioWhisper"
lipo -create -output "$RELEASE_BINARY" "${SLICES[@]}"

echo "Using release binary: $RELEASE_BINARY"

# Distribution builds must be universal; a single-arch binary here would ship
# broken to Intel users and is worth failing loudly on.
if ! lipo -archs "$RELEASE_BINARY" 2>/dev/null | grep -q x86_64 \
   || ! lipo -archs "$RELEASE_BINARY" 2>/dev/null | grep -q arm64; then
  echo "❌ Release binary is not universal: $(lipo -archs "$RELEASE_BINARY" 2>/dev/null)"
  exit 1
fi

fi

# Create app bundle
echo "Creating app bundle..."
mkdir -p AudioWhisper.app/Contents/MacOS
mkdir -p AudioWhisper.app/Contents/Resources
mkdir -p AudioWhisper.app/Contents/Resources/bin

# Set build number for Info.plist
BUILD_NUMBER="${VERSION//./}"

# Copy executable (universal binary)
cp "$RELEASE_BINARY" AudioWhisper.app/Contents/MacOS/

# SwiftPM dependency code calls Bundle.module at runtime. Flattening only our
# Python resources omitted KeyboardShortcuts' localizations and crashed as soon
# as Preferences created its shortcut recorder. Carry every generated resource
# bundle, then reject missing required bundles before signing.
for resource_bundle in "$slice_dir"/*.bundle; do
  [ -d "$resource_bundle" ] || continue
  ditto "$resource_bundle" "AudioWhisper.app/Contents/Resources/$(basename "$resource_bundle")" || exit 1
done
for required_bundle in AudioWhisper_AudioWhisper KeyboardShortcuts_KeyboardShortcuts; do
  if [ ! -d "AudioWhisper.app/Contents/Resources/$required_bundle.bundle" ]; then
    echo "Missing required resource bundle: $required_bundle" >&2
    exit 1
  fi
done

# Copy dashboard logo
if [ -f "Sources/Resources/DashboardLogo.jpg" ]; then
  cp Sources/Resources/DashboardLogo.jpg AudioWhisper.app/Contents/Resources/
  echo "Copied dashboard logo"
fi

# Copy Python scripts for Parakeet and MLX support
# Copy verify scripts
if [ -f "Sources/verify_parakeet.py" ]; then
  cp Sources/verify_parakeet.py AudioWhisper.app/Contents/Resources/
fi
if [ -f "Sources/verify_mlx.py" ]; then
  cp Sources/verify_mlx.py AudioWhisper.app/Contents/Resources/
fi

# Model downloads run this. Like the verify scripts it imports the ml package,
# so it must sit beside Resources/ml. Missing it breaks every MLX and Parakeet
# download, so fail the build rather than ship that.
if [ -f "Sources/download_model.py" ]; then
  cp Sources/download_model.py AudioWhisper.app/Contents/Resources/
else
  echo "❌ Sources/download_model.py not found; model downloads would not work"
  exit 1
fi

# Copy ML daemon entrypoint and package
if [ -f "Sources/ml_daemon.py" ]; then
  cp Sources/ml_daemon.py AudioWhisper.app/Contents/Resources/
  echo "Copied ML daemon entrypoint"
fi
if [ -d "Sources/ml" ]; then
  cp -R Sources/ml AudioWhisper.app/Contents/Resources/
  echo "Copied ml package"
else
  echo "⚠️ Sources/ml package not found, ML daemon will not work"
fi

# Test/dev interpreters can leave bytecode beside Sources/ml. Strip it from
# both the flat resources and the copied SwiftPM bundle before sealing the app.
find AudioWhisper.app/Contents/Resources -name "__pycache__" -type d -exec rm -rf {} + || exit 1

# Copy the verified, already signed bytes whose final hash was stamped above.
cp Sources/Resources/bin/uv AudioWhisper.app/Contents/Resources/bin/uv || exit 1
chmod +x AudioWhisper.app/Contents/Resources/bin/uv

# Bundle pyproject.toml and uv.lock.
#
# The lock is load-bearing, not decorative: UvBootstrap runs `uv sync --frozen`
# against it. Without a bundled lock, the app resolved its entire Python
# dependency tree fresh from PyPI on first launch, subject only to range
# constraints — arbitrary code execution in an unsandboxed app holding
# Microphone and Accessibility permissions. This step previously claimed to
# bundle uv.lock in its comment but only ever copied pyproject.toml.
if [ -f "Sources/Resources/pyproject.toml" ]; then
  cp Sources/Resources/pyproject.toml AudioWhisper.app/Contents/Resources/pyproject.toml
  echo "Bundled pyproject.toml"
else
  echo "Missing required pyproject.toml" >&2
  exit 1
fi

if [ -f "Sources/Resources/uv.lock" ]; then
  cp Sources/Resources/uv.lock AudioWhisper.app/Contents/Resources/uv.lock
  echo "Bundled uv.lock"
else
  echo "Missing required uv.lock; refusing to build an app without its dependency lock" >&2
  exit 1
fi

# Note: AudioProcessorCLI binary no longer needed - using direct Swift audio processing

# Create proper Info.plist
echo "Creating Info.plist..."
cat >AudioWhisper.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AudioWhisper</string>
    <key>CFBundleIdentifier</key>
    <string>com.audiowhisper.rebuild</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AudioWhisper Rebuild</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>AudioWhisper needs access to your microphone to record audio for transcription.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>AudioWhisper needs accessibility access to monitor global keyboard shortcuts for quick recording.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>api.openai.com</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
            <key>generativelanguage.googleapis.com</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
            <key>huggingface.co</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
        </dict>
    </dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Generate app icon from our source image
if [ -f "AudioWhisperIcon.png" ]; then
  "$SCRIPT_DIR/generate-icons.sh"

  # Create proper icns file directly in app bundle
  if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns AudioWhisper.iconset -o AudioWhisper.app/Contents/Resources/AppIcon.icns 2>/dev/null || echo "Note: iconutil failed, app will use default icon"
  fi

  # Clean up temporary files
  rm -rf AudioWhisper.iconset
  rm -f AppIcon.icns # Remove any stray icns file from root
else
  echo "⚠️ AudioWhisperIcon.png not found, app will use default icon"
fi

# Make executable
chmod +x AudioWhisper.app/Contents/MacOS/AudioWhisper

# Function to sign the app with a given identity
sign_app() {
  local identity="$1"
  local identity_name="$2"

  if [ -n "$identity_name" ]; then
    echo "🔏 Code signing app with: $identity_name ($identity)"
  else
    echo "🔏 Code signing app with: $identity"
  fi

  codesign --force --sign "$identity" --options runtime --entitlements AudioWhisper.entitlements AudioWhisper.app || return 1
  echo "🔍 Verifying signature..."
  codesign --verify --strict --verbose AudioWhisper.app || return 1
  echo "✅ App signed successfully"
}

# TCC identifies microphone clients through their code signing requirement.
# The linker's executable-only signature has neither a bound Info.plist nor
# sealed bundle resources. Even local previews must sign the completed bundle.
# Ad-hoc signing retains permission for this build across launches; a Developer
# ID is still required to retain that identity across different releases.
if [ -n "$SIGNING_IDENTITY" ]; then
  sign_app "$SIGNING_IDENTITY" "$SIGNING_NAME" || exit 1
else
  echo "🔏 Signing the local preview ad hoc (not a notarized release)."
  codesign --force --sign - --entitlements AudioWhisper.entitlements AudioWhisper.app || exit 1
  codesign --verify --strict --verbose AudioWhisper.app || exit 1
fi

FINAL_UV_SHA256=$(shasum -a 256 AudioWhisper.app/Contents/Resources/bin/uv | awk '{print $1}')
if [ "$FINAL_UV_SHA256" != "$BUNDLED_UV_SHA256" ]; then
  echo "Bundled uv changed after its checksum was stamped" >&2
  exit 1
fi

# Clean up entitlements file
rm -f AudioWhisper.entitlements

# Notarization (requires code signing first)
if [ "$NOTARIZE" = true ]; then
  echo ""
  echo "🔐 Starting notarization process..."

  # Check for required environment variables
  if [ -z "$AUDIO_WHISPER_APPLE_ID" ] || [ -z "$AUDIO_WHISPER_APPLE_PASSWORD" ] || [ -z "$AUDIO_WHISPER_TEAM_ID" ]; then
    echo "❌ Notarization requires the following environment variables:"
    echo "   AUDIO_WHISPER_APPLE_ID - Your Apple ID email"
    echo "   AUDIO_WHISPER_APPLE_PASSWORD - App-specific password for notarization"
    echo "   AUDIO_WHISPER_TEAM_ID - Your Apple Developer Team ID"
    echo ""
    echo "To create an app-specific password:"
    echo "1. Go to https://appleid.apple.com/account/manage"
    echo "2. Sign in and go to Security > App-Specific Passwords"
    echo "3. Generate a new password for AudioWhisper notarization"
    echo ""
    exit 1
  fi

  # Check if app is signed
  if codesign -dvvv AudioWhisper.app 2>&1 | grep -q "Signature=adhoc"; then
    echo "❌ App must be properly signed before notarization (not adhoc signed)"
    echo "Please ensure CODE_SIGN_IDENTITY is set or a Developer ID is available"
    exit 1
  fi

  # Create a zip file for notarization
  echo "Creating zip for notarization..."
  ditto -c -k --keepParent AudioWhisper.app AudioWhisper.zip

  # Submit for notarization
  echo "📤 Submitting to Apple for notarization..."
  xcrun notarytool submit AudioWhisper.zip \
    --apple-id "$AUDIO_WHISPER_APPLE_ID" \
    --password "$AUDIO_WHISPER_APPLE_PASSWORD" \
    --team-id "$AUDIO_WHISPER_TEAM_ID" \
    --wait 2>&1 | tee notarization.log

  # Check if notarization was successful
  if grep -q "status: Accepted" notarization.log; then
    # Staple the notarization ticket to the app
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple AudioWhisper.app

    if [ $? -eq 0 ]; then
      echo "✅ Notarization ticket stapled successfully!"
    else
      echo "⚠️ Failed to staple notarization ticket, but app is notarized"
    fi
  else
    echo "❌ Notarization failed. Check notarization.log for details"
    echo ""
    echo "Common issues:"
    echo "- Ensure your Apple ID has accepted all developer agreements"
    echo "- Check that your app-specific password is correct"
    echo "- Verify your Team ID is correct"
    exit 1
  fi

  # Clean up
  rm -f AudioWhisper.zip
  rm -f notarization.log
fi

echo "✅ Build complete!"
echo ""
echo "Preview: $PWD/AudioWhisper.app"
