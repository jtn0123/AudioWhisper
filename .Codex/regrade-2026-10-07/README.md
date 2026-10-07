# Fresh PR regrade evidence — 2026-10-07

After [PR #40](https://github.com/jtn0123/AudioWhisper/pull/40) was opened, the
current app was sampled across nine codebase categories.
[Report and ranked items](../grade-report-b64f707.md): **B overall** after the PR coverage result; Testing **C+**.

Code: `b64f7071688a705d380e6ace5fb2382c92205f5c`; app sources unchanged from `224473e`. The signed installed package
was built from `a9a0fed`; the intervening commit adds evidence/docs only.
Both host and guest binary SHA-256:
`58e531e1bc1e19dcadac4aa34af0330363897bcb34691dc85444b4f5f3e6b218`.

## Fresh checks

- [Verification metadata](verification.json): full local Swift run exited 0,
  2,979 discovered cases; 121 Python and 6 acceptance utility tests passed;
  pinned strict lint and typing passed. Optional hardware/model/snapshot cases
  can skip. Exact-head [hosted CI](https://github.com/jtn0123/AudioWhisper/actions/runs/37643160057)
  passed with 40.80% Sources-only coverage. The PR's checks are separate.
- [Exact-head PR CI](b64-pr-ci.json) and [CodeQL](b64-pr-codeql.json) on `b64f707` completed successfully: tests, lint, analyzer and universal packaged smoke. [Checks](b64-pr-checks.json) retain the separate failing Sonar result. Later audit-only commits leave source/tests unchanged; inspect the live PR for their checks.
- [PR Sonar gate](sonar-pr40-status.json) / [measures](sonar-pr40-measures.json): **45.7% new-code coverage against 80%**, sole gate failure on `b64f707`. Ratings A, duplication 0%, hotspots reviewed 100%. Overall 40.80% measures a different code population. PR remains blocked.
- [Headless Models behavioral probe](headless-probe/README.md): failed to expose a real button; only an AX group with no children. Fake services, isolated preferences and no real permission/capture/download. Preserved failed feasibility evidence, not a passing regression fixture or a universal headless limitation.
- [Ten native page captures](pages/capture-report.json): macOS 26.6.2,
  light/dark for all five screens, 870×620-point bounds contained on the
  1024×768-point guest display, with selected/focused AX navigation dumps.
- [Fresh desktop acceptance](desktop/report.json): ten actual shortcut starts
  and native Cancel clicks, actual Stop, public fixture transcription, exactly
  one app-generated paste into disposable TextEdit, and valid signature.
  The prepared guest was restarted and existing consent retained. The harness
  is the committed [enabled-native-control runner](../opus-visuals-2026-10-07/qa/run-hud-button-acceptance.py).
- [B1 reproduction](import-duration.json): native file chooser imported the
  public 2.67075-second WAV. Text was correct, but the new saved history row's
  duration was SQL NULL. [Reproduction helper](check-import-duration.py) drives
  only the named QA guest; it does not modify host settings.
- [Changed Swift line coverage](changed-coverage.json): 4,406 changed executable
  lines, 1,968 covered, 2,438 uncovered. Hosted unit coverage and VM native
  acceptance are separate. Unhit rendering lines do not represent that many
  distinct untested behaviors.
- [I1 reproduction](missing-tools.json): restricted-PATH local lint/typecheck
  wrappers print that they skipped and both return exit 0.
- [Read-only host snapshot](host-snapshot.json): exact installed binary,
  14 protected preference keys, zero history records, SQLite quick_check `ok`.
  Preference values and user content are not included. Strict host signature
  verification passed; host permission/preferences were untouched.

## Native screenshots

| Screen | Light | Dark |
|--------|-------|------|
| Record | [Light](pages/record-light.png) | [Dark](pages/record-dark.png) |
| Library | [Light](pages/library-light.png) | [Dark](pages/library-dark.png) |
| Models & setup | [Light](pages/models-light.png) | [Dark](pages/models-dark.png) |
| Writing cleanup | [Light](pages/writing-light.png) | [Dark](pages/writing-dark.png) |
| Preferences | [Light](pages/preferences-light.png) | [Dark](pages/preferences-dark.png) |

[Recorder HUD](desktop/recording-hud.png) ·
[Exactly-once native paste](desktop/smart-paste-result.png) ·
[Imported-file result](import-duration-result.png)

These are original native captures, not generated mockups. Audio, clipboard
and USB passthrough to the host were disabled.

## Limits

Physical hold keys, unplugging/input changes, sleep recovery and a complete
VoiceOver pass remain unaccepted. Synthetic guest events do not establish
physical host behavior. Host live recording was not accepted; read-only command-line readiness was false and native GUI inspection timed out, so no new host consent-defect inference is made. Existing same-source fullscreen, install cancellation,
Library export and high-contrast evidence remains in the earlier UI packages
and was not all repeated here. No release was published, PR merged, host consent
reset or app profile restored.

The new report is an audit; its new work is not claimed fixed. Old report IDs
remain in [the previous report](../baseline-pre-pr-2026-10-07/grade-report.md).
