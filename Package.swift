// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tannin",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TanninCore", targets: ["TanninCore"]),
        .executable(name: "tannin", targets: ["tannin"]),
        .executable(name: "TanninApp", targets: ["TanninApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0"),
        // In-app updates. Only the app links it; the core library and the command line tool do not.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "TanninCore"),
        .executableTarget(
            name: "tannin",
            dependencies: [
                "TanninCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "TanninApp",
            dependencies: [
                "TanninCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(name: "TanninCoreTests", dependencies: ["TanninCore"]),
    ]
)
