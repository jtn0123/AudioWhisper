import Foundation
import CryptoKit

extension UvBootstrap {
    static func bundledProjectFile(_ name: String) throws -> URL {
        let roots = [Bundle.main.resourceURL, ResourceLocator.moduleBundle?.resourceURL].compactMap { $0 }
        for root in roots {
            for file in [root.appendingPathComponent(name), root.appendingPathComponent("Resources/" + name)]
                where FileManager.default.fileExists(atPath: file.path) { return file }
        }
        throw UvError.syncFailed("bundled \(name) is missing; reinstall AudioWhisper")
    }

    /// Changes to the lock, project, selected tools, or interpreter invalidate reuse.
    /// No subprocess executes while computing this key.
    static func preparationKey(project: URL, python: String?) throws -> String {
        let fm = FileManager.default
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var parts = [project.path, python ?? defaultPythonVersion, path, VersionInfo.bundledUvSha256]
        for name in ["pyproject.toml", "uv.lock"] {
            parts.append(try fileHash(bundledProjectFile(name)))
            parts.append((try? fileHash(project.appendingPathComponent(name))) ?? "missing")
        }
        let resourceRoots = [Bundle.main.resourceURL, ResourceLocator.moduleBundle?.resourceURL].compactMap { $0 }
        var tools = path.split(separator: ":", omittingEmptySubsequences: false).map {
            URL(fileURLWithPath: $0.isEmpty ? fm.currentDirectoryPath : String($0)).appendingPathComponent("uv")
        }
        tools += resourceRoots.flatMap {
            [$0.appendingPathComponent("bin/uv"), $0.appendingPathComponent("Resources/bin/uv")]
        }
        tools += [project.appendingPathComponent(".venv/bin/python3"), project.appendingPathComponent(".venv/bin/python")]
        for tool in tools where fm.fileExists(atPath: tool.path) {
            parts.append(tool.path)
            parts.append(fileIdentity(tool))
        }
        parts.append((try? fileHash(project.appendingPathComponent(".venv/pyvenv.cfg"))) ?? "missing")
        let libraries = project.appendingPathComponent(".venv/lib")
        if let libs = try? fm.contentsOfDirectory(at: libraries, includingPropertiesForKeys: nil) {
            for lib in libs.sorted(by: { $0.path < $1.path }) {
                parts.append(fileIdentity(lib.appendingPathComponent("site-packages")))
            }
        }
        return SHA256.hash(data: try JSONEncoder().encode(parts)).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileIdentity(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        guard let values = try? FileManager.default.attributesOfItem(atPath: resolved.path) else { return "missing" }
        return "\(resolved.path):\(values[.size] ?? 0):\(values[.modificationDate] ?? ""):"
            + "\(values[.systemFileNumber] ?? 0)"
    }

    static func environmentImportsWork(python: URL, project: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return false }
        return runInDir(python.path, ["-c", "import mlx.core, mlx_lm, parakeet_mlx"], cwd: project).status == 0
    }
}
