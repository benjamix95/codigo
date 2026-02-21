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
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(
            url: "https://github.com/mchakravarty/CodeEditorView.git",
            revision: "5386056ab53d43363083cb96069715a9608aa048"
        )
    ],
    targets: [
        .executableTarget(
            name: "CoderIDE",
            dependencies: [
                .product(name: "CoderEngine", package: "CoderEngine"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "CodeEditorView", package: "CodeEditorView")
            ],
            path: "Sources/CoderIDE",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CoderIDETests",
            dependencies: ["CoderIDE"],
            path: "Tests/CoderIDETests"
        )
    ]
)
