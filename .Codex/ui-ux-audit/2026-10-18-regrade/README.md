# Native preview evidence, 2026-10-18

Source: master `9634ed53eb0c774f433186177070c96c896a847c` (saved modes merged).
These are fresh AppKit/SwiftUI offscreen renders using the production workspace
hosting controller. `capture.swift.txt` preserves the temporary XCTest harness.
The final harness completed one test with zero failures in 5.31 seconds. An
initial active-display-gated attempt skipped; it is not counted as runtime proof.

Settings are test-process isolated. Capture, transcription, copy, history and
permission effects are fixtures; no real microphone capture, paste, transcript
history or permission dialog was exercised. Record readiness is a fixture, not
a model/permission verification. Real model availability labels may reflect the
local cache. No user transcript content is included. The Models image was
inspected locally but excluded because it displays the local account's path.

Nine retained PNGs cover Record, history-off Library, Writing, Preferences, two
dark variants, a 900x600 Preferences render, a mocked recording state and setup
needed. Normal previews use 1100x760 points. Offscreen captures can omit cached
sidebar layers or clip headers; these artifacts are not evidence of real-window
placement defects. No mobile layout is expected for this macOS-only app.

Physical shortcut/hold keys, VoiceOver, Spaces, multiple displays, microphone
hotplug and sleep/wake were not retested. No matched competitor latency or
accuracy measurement was collected. Full interactive layout acceptance remains
open.
