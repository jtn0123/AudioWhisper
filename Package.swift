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
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMinor(from: "0.15.0")),
        .package(url: "https://github.com/nalexn/ViewInspector", .upToNextMinor(from: "0.10.0"))
    ],
    targets: [
        .executableTarget(
            name: "AudioWhisper",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                "WhisperKit"
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
