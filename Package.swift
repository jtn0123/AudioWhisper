// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AudioWhisper",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Was pinned below 2.0 on the belief that 2.x needed Swift 6 LANGUAGE
        // MODE, which the universal release build compiles as Swift 5. Retested
        // on 3.0.1: that is not the constraint. 3.x only isolates its own API to
        // the main actor, which callers satisfy with @MainActor — no language
        // mode change required. The universal arm64+x86_64 release build passes.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.0"),
        // WhisperKit graduated to 1.0 and moved to the Argmax Open-Source SDK
        // repo. The package still vends a `WhisperKit` library product, so the
        // import sites are unchanged; only the URL and version move. The old
        // pin was `.upToNextMinor(from: "0.15.0")`, which capped us at 0.15.x
        // and silently skipped 0.16, 0.17, 0.18 and 1.0.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AudioWhisper",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources",
            exclude: ["VersionInfo.swift.template"],
            resources: [
                .process("Assets.xcassets"),
                .copy("parakeet_transcribe_pcm.py"),
                .copy("mlx_semantic_correct.py"),
                .copy("verify_parakeet.py"),
                .copy("verify_mlx.py"),
                .copy("ml_daemon.py"),
                .copy("ml"),
                // Bundle additional resources like uv binary and lock files
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "AudioWhisperTests",
            dependencies: ["AudioWhisper"],
            path: "Tests",
            exclude: ["README.md", "test_parakeet_transcribe.py", "test_correction_sanitize.py", "__Snapshots__"],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
