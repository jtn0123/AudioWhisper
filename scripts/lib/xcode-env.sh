#!/usr/bin/env bash
# Ensure a FULL Xcode toolchain is active, not just Command Line Tools.
#
# Source this from any script that builds: `. "$(dirname "$0")/lib/xcode-env.sh"`
#
# Why this exists: the Swift package compiles an asset catalog
# (Sources/Assets.xcassets), which needs `actool`. `actool` ships with Xcode, NOT
# with Command Line Tools. If `xcode-select -p` points at
# /Library/Developer/CommandLineTools — which happens routinely after a CLT
# update, and silently — every build fails with:
#
#   error: Failed to decode version info for '/usr/bin/actool' …
#          tool 'actool' requires Xcode, but active developer directory
#          '/Library/Developer/CommandLineTools' is a command line tools instance
#
# The global fix is `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`,
# but that needs admin rights and changes the setting for every project on the
# machine. Setting DEVELOPER_DIR for this process instead is equivalent for our
# purposes, needs no privileges, and leaves the user's global config alone.

ensure_xcode_toolchain() {
  # Already fine? Nothing to do. (DEVELOPER_DIR, if exported, wins here.)
  if xcrun --find actool >/dev/null 2>&1; then
    return 0
  fi

  # Prefer a released Xcode over a beta; highest version first within each.
  #
  # Uses `find` with a QUOTED pattern, not a shell glob. `shopt -s nullglob` is
  # bash-only and macOS defaults to zsh, so anyone sourcing this interactively
  # would hit "command not found: shopt". But `ls -d /Applications/Xcode_*.app`
  # is no better: zsh errors on an unmatched glob before `ls` ever runs, so the
  # `2>/dev/null` catches nothing and the caller sees
  #   ensure_xcode_toolchain:13: no matches found: /Applications/Xcode_*.app
  # on any Mac without a versioned Xcode. Quoting the pattern hands it to
  # `find`, which does its own matching and stays silent when nothing matches.
  local candidate
  for candidate in \
    /Applications/Xcode.app \
    $(find /Applications -maxdepth 1 -name 'Xcode_*.app' 2>/dev/null | sort -V -r) \
    /Applications/Xcode-beta.app; do
    [ -d "$candidate/Contents/Developer" ] || continue
    # Validate by USE, not by probing for a binary at a guessed path: Xcode
    # betas do not ship xcrun at Contents/Developer/usr/bin/xcrun, so an
    # existence check there rejects a perfectly good toolchain.
    if DEVELOPER_DIR="$candidate/Contents/Developer" xcrun --find actool >/dev/null 2>&1; then
      export DEVELOPER_DIR="$candidate/Contents/Developer"
      echo "note: active toolchain lacks actool; using DEVELOPER_DIR=$DEVELOPER_DIR" >&2
      return 0
    fi
  done

  echo "error: no Xcode toolchain with 'actool' found." >&2
  echo "       'xcode-select -p' is $(xcode-select -p 2>/dev/null), which has no actool," >&2
  echo "       and no /Applications/Xcode*.app provided one." >&2
  echo "       Install Xcode, or point at it globally with:" >&2
  echo "         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  return 1
}
