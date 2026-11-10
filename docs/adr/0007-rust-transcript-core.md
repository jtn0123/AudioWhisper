# ADR 0007: The Transcript Rules Live in a Shared Rust Core

**Status:** Accepted
**Date:** 2026-11-10

## Context

Spoken punctuation, filler removal, custom vocabulary and cursor-context fitting
(`TranscriptFormatter`, `CustomVocabulary`, `CursorContextFormatter`) decide
what is pasted into someone's document. The Android keyboard, which is mostly
Rust, needs the same rules. Two copies in two languages drift, and the first
sign is a user seeing different text from the same dictation.

The Swift ran on Foundation and ICU (`NSRegularExpression`), whose text
semantics (graphemes, full case folding, line anchors, combining marks, ICU's
Unicode version) differ from Rust's std and the regex crate in ways real text
reaches. A port that matches only on ASCII is not the same rules.

## Decision

The rules move to a Rust crate in a separate repository,
[`jtn0123/AudioWhisper-Core`](https://github.com/jtn0123/AudioWhisper-Core),
which both apps use as a git submodule. The Mac links it as a universal static
library (`libawcore.a`) through a C interface (`crates/awcore/include/awcore.h`,
the `CAWCore` system-library target). The Swift types keep their API and become
thin wrappers, so no caller changed.

The port reproduces the Swift exactly, not approximately: where Foundation or ICU
differ from Rust, the core spells out their behaviour, with Unicode data
generated from macOS itself.

## How it is held to the Swift

* The original Swift stays in `Tests/Reference/`, renamed, and
  `TranscriptCoreDifferentialTests` compares it with the Rust on random,
  deliberately awkward text (ligatures, expanding case folds, combining marks,
  every line terminator), scalar for scalar.
* While porting, a standalone harness ran 100,000+ such cases with no
  difference, and a mutation check broke the Rust 14 ways: 12 were caught, and
  the other 2 were shown to change nothing.
* The reference Swift runs on the host's ICU and Foundation, so a macOS
  update that changes them fails the differential test until the core's
  tables are regenerated.
* The core's tables are Unicode 17 (macOS 26 and later). On an older macOS
  the old Swift saw characters added since its Unicode version as unassigned,
  where the core classifies them as Unicode 17 does: a recent letter can
  start a sentence or end a word. That is the difference CI found on macOS 15,
  so the corpus draws only characters the running system has assigned,
  and CI (macOS 15, Unicode 15.1) checks everything else.

## Consequences

* Building needs rustup. The `make` targets and scripts build the core first;
  a bare `swift build` on a fresh checkout fails until `scripts/build-core.sh`
  has run once.
* A rule change is made in the core, then the submodule is bumped here.
* The reference Swift is test-only and frozen. If a rule is changed on purpose,
  change the reference in the same commit, and say why.
* Rust runs the rules 4–40× faster than the Swift did. The first call compiles
  the patterns (about 12 ms); later calls take tens of microseconds.
