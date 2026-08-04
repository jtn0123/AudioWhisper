.PHONY: help build build-notarize test clean update-brew-cask publish-brew-cask release run

SCRIPTS := scripts

# Default target
help:
	@echo "AudioWhisper Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  run                - Build, deploy to /Applications, and launch"
	@echo "  build              - Build the release app bundle"
	@echo "  build-notarize     - Build and notarize the app"
	@echo "  test               - Run tests"
	@echo "  clean              - Clean build artifacts"
	@echo "  release            - Create a new GitHub release (jtn0123/AudioWhisper)"
	@echo ""
	@echo "Disabled in this fork (they target upstream's tap — see HOMEBREW.md):"
	@echo "  update-brew-cask, publish-brew-cask"

# Build the app
build:
	$(SCRIPTS)/build.sh

# Build, deploy to /Applications, and launch
run: build
	@echo "Deploying to /Applications..."
	@pkill -x AudioWhisper 2>/dev/null || true
	@rm -rf /Applications/AudioWhisper.app
	@cp -R AudioWhisper.app /Applications/
	@echo "Launching AudioWhisper..."
	@open /Applications/AudioWhisper.app

# Build and notarize the app
build-notarize:
	$(SCRIPTS)/build.sh --notarize

# Run tests
test:
	$(SCRIPTS)/run-tests.sh

# Clean build artifacts
clean:
	rm -rf .build
	rm -rf AudioWhisper.app
	rm -f AudioWhisper.zip
	rm -f Sources/AudioProcessorCLI
	rm -f Sources/Resources/bin/uv

# Homebrew publishing — DISABLED IN THIS FORK.
#
# These targets are upstream's, inherited by the fork and never adapted. As
# written, `publish-brew-cask` ran `git push` inside ../homebrew-tap, and its own
# error message told you to clone that from mazdak/homebrew-tap — so the target
# published INTO THE UPSTREAM AUTHOR'S REPOSITORY. update-brew-cask likewise
# reads releases that only upstream publishes and prints
# `brew install mazdak/tap/audiowhisper` on success.
#
# This fork publishes no releases and no tap (see README "Installation"), so
# there is nothing here to publish and no tap of our own to publish it to.
# Refusing is deliberate: a stale target that pushes to someone else's repo is a
# footgun, not a feature. Restore these only alongside a tap you actually own.
update-brew-cask publish-brew-cask:
	@echo "❌ '$@' is disabled in this fork."
	@echo "   It targets upstream's tap (mazdak/homebrew-tap), not one we own,"
	@echo "   and this fork ships no releases for a cask to point at."
	@echo "   See README.md 'Installation' and HOMEBREW.md."
	@exit 1

# Create a new release
#
# --repo is explicit and must stay that way. This repo is a fork, and `gh` will
# resolve an unqualified command against the PARENT (mazdak/AudioWhisper) unless
# a local default is set — a per-clone, ungitted setting that a fresh clone does
# not have. Without the flag, `make release` can publish to upstream.
release:
	@VERSION=$$(cat VERSION | tr -d '[:space:]'); \
	echo "Creating release v$$VERSION..."; \
	if git diff --quiet && git diff --cached --quiet; then \
		$(SCRIPTS)/build.sh && \
		zip -r AudioWhisper.zip AudioWhisper.app && \
		gh release create "v$$VERSION" AudioWhisper.zip --repo jtn0123/AudioWhisper \
			--title "v$$VERSION" --generate-notes && \
		echo "✅ Release v$$VERSION created"; \
	else \
		echo "❌ Error: Working directory is not clean. Commit or stash changes first."; \
		exit 1; \
	fi
