// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AudioWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AudioWhisperLib", targets: ["AudioWhisperLib"]),
        .executable(name: "AudioWhisper", targets: ["AudioWhisper"])
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0"),
        .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.0")
    ],
    targets: [
        // Library target containing all app code (testable)
        .target(
            name: "AudioWhisperLib",
            dependencies: ["Alamofire", "HotKey", "WhisperKit"],
            path: "Sources",
            exclude: ["VersionInfo.swift.template", "AudioWhisperApp"],
            resources: [
                .process("Assets.xcassets"),
                .copy("parakeet_transcribe_pcm.py"),
                .copy("mlx_semantic_correct.py"),
                .copy("verify_parakeet.py"),
                .copy("verify_mlx.py"),
                .copy("ml_daemon.py"),
                .copy("ml"),
                .copy("Resources")
            ]
        ),
        // Executable target with @main entry point
        .executableTarget(
            name: "AudioWhisper",
            dependencies: ["AudioWhisperLib"],
            path: "Sources/AudioWhisperApp"
        ),
        // Tests depend on the library, not the executable
        .testTarget(
            name: "AudioWhisperTests",
            dependencies: ["AudioWhisperLib", "ViewInspector"],
            path: "Tests",
            exclude: ["README.md", "test_parakeet_transcribe.py", "__Snapshots__"],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
