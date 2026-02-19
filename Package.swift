// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Codigo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Codigo", targets: ["CoderIDE"])
    ],
    dependencies: [
        .package(path: "CoderEngine"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "CoderIDE",
            dependencies: ["CoderEngine", "SwiftTerm"],
            path: "Sources/CoderIDE"
        ),
        .testTarget(
            name: "CoderIDETests",
            dependencies: ["CoderIDE"],
            path: "Tests/CoderIDETests"
        )
    ]
)
