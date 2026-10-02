/// Thin delegation to `RecordingViewModel`'s paste implementation.
///
/// Audit item J1 — the paste-layer twin of A1, and a sharper problem than the
/// recording one was.
///
/// This file used to carry a second, near-complete implementation of Smart
/// Paste: `performUserTriggeredPaste`, `findValidTargetApp`,
/// `findFallbackTargetApp`, `hideRecordingWindow`, `fadeOutWindow`,
/// `activateTargetAppAndPaste`, `activateApplication` and
/// `waitForApplicationActivation` all existed here *and* in
/// `RecordingViewModel+Paste.swift`.
///
/// Unlike the recording layer, where the ViewModel copy was dead, **both paste
/// copies were live and reached by different triggers**: tapping the recording
/// window ran this one (`ContentView.body` → `performUserTriggeredPaste`),
/// while the automatic paste after a transcription ran the ViewModel's
/// (`showConfirmationAndPaste` → `performUserTriggeredPaste`). Same feature,
/// two code paths, chosen by how the user got there.
///
/// They had already drifted. The ViewModel captured `[weak self]` in the
/// post-delay block and this one captured `self` strongly; this one had detailed
/// target-resolution logging the ViewModel lacked. Neither difference was
/// intentional — which is exactly the failure mode duplication produces. The
/// logging was ported into the ViewModel rather than dropped, since it is what
/// makes a Smart Paste bug report diagnosable.
///
/// `performUserTriggeredPaste()` was the only member called from outside this
/// file, so nothing else needs a forwarder.
internal extension ContentView {

    func performUserTriggeredPaste() {
        viewModel.performUserTriggeredPaste()
    }
}
