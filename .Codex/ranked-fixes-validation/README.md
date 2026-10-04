# Evidence provenance

All fixtures contain public test speech; no live microphone audio or user Library record was captured.

- Unsuffixed native AX files and `long-import-allocation-failure.txt`: predecessor app source `3f6621026ebe24e8c7b0bad859bbee54854443d1`, tested 2026-10-04. Shortcut/search/accessibility UI did not change in the final follow-up.
- `*-b47.txt` and `native-long-acceptance.json`: final packaged source `b47fe8e798ab5176afe8606e6327f43c1f11ca46`, tested 2026-10-04. The long success AX file truncates the repeated public-fixture transcript line for readability. Cancellation captures idle both immediately and after worker completion.
- `parakeet-long-failure-rss.json`: sampled app/subprocess RSS during the failed predecessor 30-minute import; sampling is not guaranteed peak memory.
- `parakeet-long-inference.json`: real repaired Python/model component, same 30-minute repeated speech fixture; separate process RSS and MLX peak counters.
- `performance.json`: three-hour synthetic loader benchmarks in separate XCTest processes, active preparation/consumption cancellation and waveform benchmark. These exclude model inference.

- `ci-result.json`: successful final-source CI job outcomes; Sonar consumer is explicitly skipped on this branch.
- `ci-coverage-provenance.json`: downloaded primary reports verified against final commit, CI run 37219846937, attempt 1 and SHA-256; final Sources-only Swift gate metrics from the completed job log.

The parent validation report records unperformed OS/hardware rows separately.
