// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AudioWhisper",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // 3.x requires the Swift 6.2 toolchain and main-actor callers, but does
        // not require changing this package's Swift language mode. 3.1 fixes
        // registered-shortcut recording and function keys while menus are open.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        // WhisperKit graduated to 1.0 and moved to the Argmax Open-Source SDK
        // repo. The package still vends a `WhisperKit` library product, so the
        // import sites are unchanged; only the URL and version move. The old
        // pin was `.upToNextMinor(from: "0.15.0")`, which capped us at 0.15.x
        // and silently skipped 0.16, 0.17, 0.18 and 1.0.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.1.0")
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
                .copy("verify_parakeet.py"),
                .copy("verify_mlx.py"),
                .copy("download_model.py"),
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
            exclude: ["README.md", "test_correction_sanitize.py", "test_hub.py", "test_rpc.py", "test_verify_scripts.py", "__Snapshots__"],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
