import Foundation

private class BundleFinder {}

internal enum ResourceLocator {
    /// The SwiftPM resource bundle, or nil instead of crashing when there is
    /// none (the `.app` that build.sh assembles copies resources flat into
    /// Contents/Resources, so it has no separate bundle).
    ///
    /// `UvBootstrap` used to keep its own copy of this lookup; both now share it.
    static var moduleBundle: Bundle? {
        let bundleName = "AudioWhisper_AudioWhisper.bundle"
        let codeBundle = Bundle(for: BundleFinder.self)
        var candidates = [
            Bundle.main.resourceURL,
            codeBundle.resourceURL,
            Bundle.main.bundleURL
        ]
        // Under `swift test`, SwiftPM's native build system (the default on CI's
        // Swift 6.2 toolchain) puts the resource bundle BESIDE the .xctest;
        // Swift Build, the default from 6.4, puts it inside. Missing this case meant a test
        // process found no pyproject.toml or uv.lock, so the nightly end-to-end
        // run could never build its Python environment. Only looked for next to
        // a test bundle, so a shipped app never loads resources from whatever
        // folder it happens to sit in.
        if codeBundle.bundleURL.pathExtension == "xctest" {
            candidates.append(codeBundle.bundleURL.deletingLastPathComponent())
        }
        for candidate in candidates {
            if let bundle = candidate.flatMap({ Bundle(url: $0.appendingPathComponent(bundleName)) }) {
                return bundle
            }
        }
        return nil
    }

    /// Locates a bundled resource across common packaging modes:
    /// - `.app` bundle (copied into `Bundle.main`)
    /// - SwiftPM resources (`Bundle.module` via safe accessor)
    /// - SwiftPM resource bundle (historical fallback for `swift run`)
    /// - Dev fallback path (relative to current directory)
    static func url(forResource name: String, withExtension ext: String, devRelativePath: String? = nil) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

        if let bundle = moduleBundle, let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }

        if let resourceBundleURL = Bundle.main.url(forResource: "AudioWhisper_AudioWhisper", withExtension: "bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL),
           let url = resourceBundle.url(forResource: name, withExtension: ext) {
            return url
        }

        if let devRelativePath {
            let devPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(devRelativePath)
                .path
            if FileManager.default.fileExists(atPath: devPath) {
                return URL(fileURLWithPath: devPath)
            }
        }

        return nil
    }

    static func pythonScriptURL(named name: String) -> URL? {
        url(forResource: name, withExtension: "py", devRelativePath: "Sources/\(name).py")
    }
}
