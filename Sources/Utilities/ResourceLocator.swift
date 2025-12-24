import Foundation

private class BundleFinder {}

internal enum ResourceLocator {
    /// Safe accessor for the SPM module bundle that returns nil instead of crashing
    /// when the bundle is not found (e.g., when built with build.sh instead of SPM)
    private static var moduleBundle: Bundle? {
        let bundleName = "AudioWhisper_AudioWhisper"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: BundleFinder.self).resourceURL,
            Bundle.main.bundleURL,
        ]
        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
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

