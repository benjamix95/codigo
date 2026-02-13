// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CoderEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CoderEngine", targets: ["CoderEngine"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
    ],
    targets: [
        .target(
            name: "CoderEngine",
            dependencies: [.product(name: "MCP", package: "swift-sdk")],
            path: "Sources/CoderEngine"
        ),
        .testTarget(
            name: "CoderEngineTests",
            dependencies: ["CoderEngine"]
        )
    ]
)
