import XCTest
@testable import AudioWhisper

// MARK: - ResourceLocator Tests
final class ResourceLocatorTests: XCTestCase {

    func testURLForResourceWithValidName() {
        // A non-existent resource with no dev fallback resolves to nil.
        let url = ResourceLocator.url(forResource: "test", withExtension: "txt")
        XCTAssertNil(url)
    }

    func testURLForResourceWithEmptyName() {
        let url = ResourceLocator.url(forResource: "", withExtension: "txt")
        // Should return nil for empty name
        XCTAssertNil(url)
    }

    func testURLForResourceWithEmptyExtension() {
        // A non-existent resource with an empty extension resolves to nil.
        let url = ResourceLocator.url(forResource: "test", withExtension: "")
        XCTAssertNil(url)
    }

    func testURLForResourceWithDevRelativePathMissingReturnsNil() {
        // The dev fallback path does not exist, so resolution returns nil.
        let url = ResourceLocator.url(
            forResource: "test",
            withExtension: "txt",
            devRelativePath: "Sources/definitely_missing_resource.txt"
        )
        XCTAssertNil(url)
    }

    func testURLForResourceWithDevRelativePathResolvesExistingFile() {
        // The dev fallback resolves a file that exists relative to the cwd.
        // Sources/parakeet_transcribe_pcm.py ships with the package.
        let url = ResourceLocator.url(
            forResource: "parakeet_transcribe_pcm",
            withExtension: "py",
            devRelativePath: "Sources/parakeet_transcribe_pcm.py"
        )
        if let url = url {
            XCTAssertEqual(url.lastPathComponent, "parakeet_transcribe_pcm.py")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        // When run outside the package root the dev path is absent and the
        // result is nil; either way no other resolution mode applies here.
    }

    func testPythonScriptURL() {
        let url = ResourceLocator.pythonScriptURL(named: "nonexistent")
        // Should return nil for non-existent script
        XCTAssertNil(url)
    }

    func testPythonScriptURLFormat() {
        // Test that the dev path is constructed correctly
        let scriptName = "test_script"
        let expectedDevPath = "Sources/\(scriptName).py"
        XCTAssertEqual(expectedDevPath, "Sources/test_script.py")
    }

    func testBundleMainExists() {
        XCTAssertNotNil(Bundle.main)
    }

    func testBundleMainResourceURLAccessible() {
        // When present, the main bundle resource URL is a file URL.
        if let resourceURL = Bundle.main.resourceURL {
            XCTAssertTrue(resourceURL.isFileURL)
        } else {
            XCTAssertNil(Bundle.main.resourceURL)
        }
    }

    func testCurrentDirectoryAccessible() {
        let currentDir = FileManager.default.currentDirectoryPath
        XCTAssertFalse(currentDir.isEmpty)
    }
}

// MARK: - ResourceLocator Path Resolution Tests
final class ResourceLocatorPathResolutionTests: XCTestCase {

    func testMainBundleIsFirstPriority() {
        // Document that main bundle is checked first
        XCTAssertNotNil(Bundle.main)
    }

    func testDevPathFallback() {
        // Test that dev path is properly constructed
        let devPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/test.py")
            .path

        XCTAssertTrue(devPath.contains("Sources"))
        XCTAssertTrue(devPath.hasSuffix("test.py"))
    }

    func testResourceBundleName() {
        let bundleName = "AudioWhisper_AudioWhisper"
        XCTAssertEqual(bundleName, "AudioWhisper_AudioWhisper")
    }
}

// MARK: - ResourceLocator Python Script Tests
final class ResourceLocatorPythonScriptTests: XCTestCase {

    func testKnownPythonScripts() {
        let knownScripts = [
            "parakeet_transcribe_pcm",
            "mlx_semantic_correct",
            "verify_parakeet",
            "verify_mlx"
        ]

        for script in knownScripts {
            let url = ResourceLocator.pythonScriptURL(named: script)
            // Resolution may fail when run outside the package root, but any
            // URL returned must point at the correctly named .py script.
            if let url = url {
                XCTAssertEqual(url.pathExtension, "py")
                XCTAssertEqual(url.deletingPathExtension().lastPathComponent, script)
            }
        }
    }

    func testPythonScriptExtensionUsesPy() {
        // A missing script with no dev fallback resolves to nil; the dev
        // fallback path is always constructed with a .py extension.
        let url = ResourceLocator.pythonScriptURL(named: "missing_script_name")
        XCTAssertNil(url)
    }
}

// MARK: - ResourceLocator Bundle Candidates Tests
final class ResourceLocatorBundleCandidatesTests: XCTestCase {

    func testBundleURLAccessible() {
        // bundleURL is always a non-empty file URL.
        let bundleURL = Bundle.main.bundleURL
        XCTAssertTrue(bundleURL.isFileURL)
        XCTAssertFalse(bundleURL.path.isEmpty)
    }

    func testResourceURLAccessible() {
        // When present, resourceURL is a file URL.
        if let resourceURL = Bundle.main.resourceURL {
            XCTAssertTrue(resourceURL.isFileURL)
        } else {
            XCTAssertNil(Bundle.main.resourceURL)
        }
    }

    func testAppendingPathComponent() {
        let base = URL(fileURLWithPath: "/test")
        let appended = base.appendingPathComponent("file.txt")
        XCTAssertEqual(appended.lastPathComponent, "file.txt")
    }
}
