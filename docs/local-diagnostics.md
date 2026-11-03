# Local diagnostics and window acceptance

AudioWhisper keeps operational metadata locally by default. Open Preferences → Local diagnostics to view recent stage timings, export a JSON file, disable future collection, or clear the stored history. Nothing is uploaded automatically. Exported metadata can be shared for investigation; the assistant cannot read future usage without that file or access to this Mac.

The archive contains up to 100 sessions and 100 window events from the last seven days, bounded to 2 MiB on disk. It records build/system/architecture, model identifiers, an opaque mode ID, entry/outcome, fixed failure categories, delivery status, cache state, capture sample rate/channels, stage durations, and process resources. It excludes audio, transcripts, vocabulary, instructions, selected text, clipboard contents, file paths, microphone names/IDs, other-app names and window titles. A damaged file is preserved and reported; it cannot interrupt transcription. Clear explicitly resets it.

Application CPU is a cumulative process counter; subtract samples to measure the interval. Application memory is current resident memory. Model-worker CPU is the delta for that operation; worker memory is the lifetime peak RSS, including previous operations. Neither is a GPU allocation measurement. Start/end samples are always included; optional one-second application sampling is bounded. Cold/warm means the engine cache at the actual loader, not a guess based on app launch.

Stages can overlap. Voice/writing worker operation includes model loading and preprocessing; it does not claim isolated GPU inference time. Stop to delivery ends before clipboard restoration and history completion. Full session includes capture. Median/p95 use nearest rank from the available completed stage spans and are descriptive of the small local sample, not a benchmark against another app. Cancellation closes owned spans; late callbacks cannot modify a finished trace. Diagnostic metadata from older or future workers is optional and cannot discard successful text.

Window events include only this app's numeric window ID, frame, level, collection behavior, visibility, key/active-Space flags, activation policy, and the observed system full-screen presentation option. That option is not a private Space identifier and does not prove which desktop is active. Normal windows have `.primary` / `.fullScreenPrimary`, normal level, and no overlay eligibility. A later Space notification never reorders them with `.moveToActiveSpace`. Only the recorder HUD joins all Spaces and moves to the display under the pointer.

## Isolated native QA

Build a separate bundle under `/tmp`, then run `python3 scripts/stage-isolated-qa.py /tmp/<qa-directory>/AudioWhisper.app`. The script changes only that staged bundle, creates a unique app identity and preferences suite, redirects Application Support, isolates its URL scheme, and signs it ad hoc. It does not launch the app, grant permissions or copy user data. Do not use fake HOME as preferences isolation: AppKit/LaunchServices preferences also require a separate bundle identity. This QA identity is not a distribution-signing test.

Native acceptance still requires an actual window session: open/reopen and minimize/restore from a desktop and another app's full-screen Space, switch back immediately, test multiple displays and HUD placement, then export window events. Unit tests use unshown windows and injected activation; live window/activation effects are suppressed under XCTest. A passing policy fixture does not close physical Space/display acceptance.

## Recording keys

The key-combination field accepts a modifier plus another key (or a supported function key). Fn/Globe alone is a modifier event and belongs under Preferences → Recording → Single modifier key. Choose Globe / Fn and either Press and Hold or Press to Toggle. Global modifier monitoring requires Accessibility access. If macOS also uses Globe for emoji or input switching, its Keyboard action can be set to Do Nothing by the user. AudioWhisper does not change that system preference.
