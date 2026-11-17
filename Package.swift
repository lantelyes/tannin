// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tannin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TanninCore", targets: ["TanninCore"]),
        .executable(name: "tannin", targets: ["tannin"]),
        .executable(name: "TanninApp", targets: ["TanninApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0"),
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
        .executableTarget(name: "TanninApp", dependencies: ["TanninCore"]),
        .testTarget(name: "TanninCoreTests", dependencies: ["TanninCore"]),
    ]
)
