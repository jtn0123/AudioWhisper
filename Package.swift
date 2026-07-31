// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AudioWhisper",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Pinned below 2.0: KeyboardShortcuts 2.x requires Swift 6 language
        // mode, which the universal release build (swift build --arch arm64
        // --arch x86_64 via the Xcode build system) compiles as Swift 5.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMajor(from: "1.10.0")),
        // WhisperKit graduated to 1.0 and moved to the Argmax Open-Source SDK
        // repo. The package still vends a `WhisperKit` library product, so the
        // import sites are unchanged; only the URL and version move. The old
        // pin was `.upToNextMinor(from: "0.15.0")`, which capped us at 0.15.x
        // and silently skipped 0.16, 0.17, 0.18 and 1.0.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0"),
        .package(url: "https://github.com/nalexn/ViewInspector", .upToNextMinor(from: "0.10.0"))
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
            dependencies: ["AudioWhisper", "ViewInspector"],
            path: "Tests",
            exclude: ["README.md", "test_parakeet_transcribe.py", "__Snapshots__"],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
