# Fresh audit evidence — f30c081

Audit date: 2026-10-06. Source commit: `f30c081ed0bc324bf29c882052a6033d7028783b`.
No application implementation or host permission changes.

- `transcript-repro.swift`: current cleaner/safeMerge/edit-distance functions
  extracted unchanged into isolated namespaces. Harness examples are public,
  constructed prose/code, not user transcripts. Compiled `swiftc -O`; results
  are in `transcript-repro.txt`. This reproduces implementation behavior;
  bracketed examples are not claims about a particular speech model's output.
- `analyzer-repro.json`: fresh SwiftLint missing-log error. Exit 1 with empty
  stdout becomes apparent success through CI's discarded stderr / `|| true`.
  It does not show that the successful remote analysis job failed internally.
- `ci.json`: successful exact-code GitHub Actions run and job conclusions,
  including skipped SonarCloud. Coverage is from that run's source-only summary.
- [Current native VM evidence](../ui-ux-audit/2026-10-06-f30c081/README.md):
  matching binary identity, native screenshots, ten cancellations, real fixture
  transcription and exactly-once Smart Paste.
- [Production model outputs](../bench/2026-10-06-qwen-integration/README.md):
  two pinned Qwen models, 64 edits each. Meaning-loss examples are original
  artifact lines 57/63 in the 9B delivered JSONL and line57 in the 27B file.

Dependency finding: current `Sources/Resources/uv.lock` pins fsspec2025.7.0.
[GitHub Reviewed GHSA-27vj-qcqg-25rc](https://github.com/advisories/GHSA-27vj-qcqg-25rc)
was reviewed live, affected range >=0.9.0,<2026.6.0, patched2026.6.0.
The vulnerable reference/Kerchunk parser has no established normal app input
path: no direct ReferenceFileSystem/reference:// or xarray usage in Sources.
This is a vulnerable runtime dependency, not demonstrated app compromise.
