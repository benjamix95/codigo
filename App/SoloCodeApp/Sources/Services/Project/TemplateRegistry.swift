import Foundation

// MARK: - Template Registry

/// Registro dei template di progetto disponibili.
/// Fornisce template built-in e carica template custom da disco.
actor TemplateRegistry {
    private var templates: [String: ProjectTemplateService.ProjectTemplate] = [:]
    private var loaded = false

    // MARK: - Query

    /// Restituisce un template per ID.
    func template(for id: String) async -> ProjectTemplateService.ProjectTemplate? {
        await ensureLoaded()
        return templates[id]
    }

    /// Restituisce tutti i template, opzionalmente filtrati per categoria.
    func allTemplates(
        category: ProjectTemplateService.TemplateCategory? = nil
    ) async -> [ProjectTemplateService.ProjectTemplate] {
        await ensureLoaded()
        let all = Array(templates.values)
        if let cat = category {
            return all.filter { $0.category == cat }.sorted { $0.name < $1.name }
        }
        return all.sorted { $0.name < $1.name }
    }

    /// Registra un template custom.
    func register(template: ProjectTemplateService.ProjectTemplate) {
        templates[template.id] = template
    }

    // MARK: - Caricamento

    private func ensureLoaded() async {
        guard !loaded else { return }
        loadBuiltInTemplates()
        await loadCustomTemplates()
        loaded = true
    }

    private func loadBuiltInTemplates() {
        let swiftPackage = ProjectTemplateService.ProjectTemplate(
            id: "swift-package",
            name: "Swift Package",
            description: "Package Swift con struttura standard",
            category: .swiftPackage,
            files: [
                .init(
                    relativePath: "Package.swift",
                    content: """
                    // swift-tools-version: 5.9
                    import PackageDescription

                    let package = Package(
                        name: "{{PROJECT_NAME}}",
                        targets: [
                            .target(name: "{{PROJECT_NAME}}"),
                            .testTarget(name: "{{PROJECT_NAME}}Tests", dependencies: ["{{PROJECT_NAME}}"]),
                        ]
                    )
                    """
                ),
                .init(
                    relativePath: "Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.swift",
                    content: "// {{PROJECT_NAME}} - Created {{DATE}}\n\npublic struct {{PROJECT_NAME}} {\n    public init() {}\n}\n"
                ),
                .init(
                    relativePath: "Tests/{{PROJECT_NAME}}Tests/{{PROJECT_NAME}}Tests.swift",
                    content: "import XCTest\n@testable import {{PROJECT_NAME}}\n\nfinal class {{PROJECT_NAME}}Tests: XCTestCase {\n    func testExample() {\n        XCTAssertNotNil({{PROJECT_NAME}}())\n    }\n}\n"
                ),
                .init(relativePath: ".gitignore", content: ".build/\n.swiftpm/\nPackage.resolved\n"),
            ],
            dependencies: []
        )

        let commandLine = ProjectTemplateService.ProjectTemplate(
            id: "command-line",
            name: "Command Line Tool",
            description: "Tool da linea di comando con ArgumentParser",
            category: .commandLine,
            files: [
                .init(
                    relativePath: "Package.swift",
                    content: """
                    // swift-tools-version: 5.9
                    import PackageDescription

                    let package = Package(
                        name: "{{PROJECT_NAME}}",
                        dependencies: [
                            .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
                        ],
                        targets: [
                            .executableTarget(
                                name: "{{PROJECT_NAME}}",
                                dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]
                            ),
                        ]
                    )
                    """
                ),
                .init(
                    relativePath: "Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.swift",
                    content: "import ArgumentParser\n\n@main\nstruct {{PROJECT_NAME}}: ParsableCommand {\n    static let configuration = CommandConfiguration(\n        abstract: \"{{PROJECT_NAME}} CLI tool\"\n    )\n\n    func run() throws {\n        print(\"Hello from {{PROJECT_NAME}}!\")\n    }\n}\n"
                ),
                .init(relativePath: ".gitignore", content: ".build/\n.swiftpm/\nPackage.resolved\n"),
            ],
            dependencies: ["swift-argument-parser"]
        )

        let library = ProjectTemplateService.ProjectTemplate(
            id: "library",
            name: "Swift Library",
            description: "Libreria Swift con documentazione DocC",
            category: .library,
            files: [
                .init(
                    relativePath: "Package.swift",
                    content: """
                    // swift-tools-version: 5.9
                    import PackageDescription

                    let package = Package(
                        name: "{{PROJECT_NAME}}",
                        products: [
                            .library(name: "{{PROJECT_NAME}}", targets: ["{{PROJECT_NAME}}"]),
                        ],
                        targets: [
                            .target(name: "{{PROJECT_NAME}}"),
                            .testTarget(name: "{{PROJECT_NAME}}Tests", dependencies: ["{{PROJECT_NAME}}"]),
                        ]
                    )
                    """
                ),
                .init(
                    relativePath: "Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.swift",
                    content: "/// {{PROJECT_NAME}} library.\n///\n/// Created {{DATE}}.\npublic struct {{PROJECT_NAME}} {\n    public init() {}\n}\n"
                ),
                .init(
                    relativePath: "Tests/{{PROJECT_NAME}}Tests/{{PROJECT_NAME}}Tests.swift",
                    content: "import XCTest\n@testable import {{PROJECT_NAME}}\n\nfinal class {{PROJECT_NAME}}Tests: XCTestCase {\n    func testInit() {\n        XCTAssertNotNil({{PROJECT_NAME}}())\n    }\n}\n"
                ),
                .init(relativePath: ".gitignore", content: ".build/\n.swiftpm/\nPackage.resolved\n"),
            ],
            dependencies: []
        )

        templates["swift-package"] = swiftPackage
        templates["command-line"] = commandLine
        templates["library"] = library
    }

    private func loadCustomTemplates() async {
        let customDir = NSHomeDirectory() + "/.solocode/templates"
        let fm = FileManager.default
        guard fm.fileExists(atPath: customDir),
              let entries = try? fm.contentsOfDirectory(atPath: customDir) else { return }

        let decoder = JSONDecoder()
        for entry in entries {
            let templatePath = (customDir as NSString).appendingPathComponent(entry)
            let manifestPath = (templatePath as NSString).appendingPathComponent("template.json")
            guard let data = fm.contents(atPath: manifestPath),
                  let manifest = try? decoder.decode(CustomTemplateManifest.self, from: data) else {
                continue
            }
            let files = loadTemplateFiles(at: templatePath, manifest: manifest)
            let template = ProjectTemplateService.ProjectTemplate(
                id: "custom-\(entry)",
                name: manifest.name,
                description: manifest.description,
                category: manifest.category,
                files: files,
                dependencies: manifest.dependencies
            )
            templates[template.id] = template
        }
    }

    private func loadTemplateFiles(
        at path: String,
        manifest: CustomTemplateManifest
    ) -> [ProjectTemplateService.ProjectTemplate.TemplateFile] {
        manifest.files.compactMap { relativePath in
            let filePath = (path as NSString).appendingPathComponent(relativePath)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }
            return .init(relativePath: relativePath, content: content)
        }
    }
}

// MARK: - Custom Template Manifest

private struct CustomTemplateManifest: Codable {
    let name: String
    let description: String
    let category: ProjectTemplateService.TemplateCategory
    let files: [String]
    let dependencies: [String]
}

extension ProjectTemplateService.TemplateCategory: Codable {}
