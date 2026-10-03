/// The exact Hugging Face commit downloaded for each model the app offers.
///
/// Without a pin, a download fetches whatever the repo's `main` branch is at
/// that moment, so two users installing the same build could get different
/// weights — and a repo change upstream, malicious or just breaking, reaches
/// every new install with nothing in between. That is not hypothetical:
/// `Qwen3-4B-Instruct-2507-4bit` was revised in January 2026, months after the
/// app first offered it.
///
/// A commit hash names the repo's full tree, LFS pointers (and so each weight
/// file's SHA-256) included, so downloading by commit over TLS gets exactly the
/// files this build was tested against. `download_model.py` fetches the pinned
/// commit and points `refs/main` at it, which is what the offline loaders
/// resolve; the trust-on-first-use record taken right after the download then
/// anchors to it (ADR 0006).
///
/// **Updating a model means updating its pin here.** Take the new value from
/// `https://huggingface.co/api/models/<repo>` (the `sha` field), test with it,
/// and change it in the same commit as anything that depends on the new
/// revision. `ModelPinsTests` fails if an offered model has no pin.
///
/// Scope: MLX and Parakeet only. WhisperKit's download API has no revision
/// parameter — it always fetches `main` — so WhisperKit models cannot be pinned
/// from here and remain trust-on-first-use.
///
/// User-added repos are not in this table and download at their latest revision.
internal enum ModelPins {
    static let revisions: [String: String] = [
        // Parakeet (ParakeetModel)
        "mlx-community/parakeet-tdt_ctc-110m": "d62547387c356a1ab6bb3d85d98b2103f655282e",
        "mlx-community/parakeet-tdt-0.6b-v2": "8ae155301e23d820d82aa60d24817c900e69e487",
        "mlx-community/parakeet-tdt-0.6b-v3": "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15",
        // Semantic correction (MLXModelManager.recommendedModels)
        "mlx-community/gemma-3-1b-it-qat-4bit": "15fed4eafb456c6fcb2a1165f19ac609670ed14b",
        "mlx-community/Qwen3-1.7B-4bit": "3b1b1768f8f8cf8351c712464f906e86c2b8269e",
        "mlx-community/Qwen3-4B-Instruct-2507-4bit": "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"
    ]

    /// The pinned commit for `repo`, or nil for a repo the app does not ship.
    static func revision(for repo: String) -> String? {
        revisions[repo]
    }

    /// Extra arguments for the download/verify scripts: the pinned revision if
    /// there is one, else nothing (the scripts then fetch the latest revision).
    static func scriptArguments(for repo: String) -> [String] {
        revision(for: repo).map { [$0] } ?? []
    }
}
