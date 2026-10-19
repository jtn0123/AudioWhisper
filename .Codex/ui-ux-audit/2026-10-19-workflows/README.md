# Workflow implementation previews — October 19

Native SwiftUI/AppKit fixture renders from the review-fix working tree based on
`7be7866`, included with this evidence commit. No production-user transcripts,
meeting audio or clipboard content were captured. `capture.swift.txt` is the
reproducible temporary XCTest harness; it was copied into Tests for one explicit
render run and removed afterward. The render test passed in 9.6 seconds.

The 16 PNGs cover the six workspace pages, light/dark Record and Writing,
minimum-size Preferences, mode editing, history-version preview, restored
clipboard delivery, captured-reference disclosure, setup-needed and recording.
Capture/transcription/history are fixtures. Meeting files live in a temporary
private store and are removed at test end. No microphone or screen permission is
requested by this harness.

Offscreen AppKit drawing omits some cached header, button and background layers
(black/transparent areas in modal and repeated workspace frames). Treat those
as incomplete renders rather than proof of live-window clipping or black UI.
The populated meeting and restored-delivery body layouts are readable. Actual
normal-window, keyboard, VoiceOver, multiple-display and hardware acceptance
remain separate. These previews do not establish Superwhisper runtime parity.

Validation for this pass: 3,260 Swift tests pass (including configured skips),
strict SwiftLint passes, and local new executable Swift-line coverage is
1,762 / 2,162 (81.50%). Hosted Sonar's unchanged 80% gate remains authoritative.
Review fixes include cancellation/resource ownership, archive byte bounds,
context selection safety, stable mode identity, truthful delivery and isolated
parallel audio fixtures. See the product tracker for open acceptance.

A signed debug bundle at `73029f2` passed local signature verification. Live native
inspection through Computer Use twice returned `timeoutReached`; the QA process
was stopped afterward, and the pre-existing app was left running. No microphone
or screen permission was granted. The generic Record caption was clarified after
these renders; subsequent fixes affect meeting stop/worker ownership and strict
automation preflight rather than the pictured layouts.

The signed `4f47eec` bundle transcribed the public speech fixture through the actual
CLI with cleanup off in an isolated preferences suite. Timestamped meeting ASR
was also run with the installed Base model. It exposed decoder control tokens in
segment text; `skipSpecialTokens` now removes them. The real fixture and the
post-commit cancellation regression pass. Final full suite: 3,260 tests, with
configured skips; changed Swift-line coverage: 81.50%.
