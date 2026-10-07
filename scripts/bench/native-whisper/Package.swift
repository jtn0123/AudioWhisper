// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WhisperBenchmark",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.0")],
    targets: [.executableTarget(name: "WhisperBenchmark", dependencies: [
        .product(name: "WhisperKit", package: "argmax-oss-swift")
    ])]
)
