import Foundation

// MARK: - FileNode

/// Nodo dell'albero del filesystem indicizzato
public struct FileNode: Sendable, Identifiable, Hashable {
    public let id: String  // path relativo al workspace root
    public let name: String
    public let kind: FileNodeKind
    public let extension_: String?
    public let relativePath: String
    public let absolutePath: String
    public let depth: Int
    public let size: UInt64
    public let modifiedAt: Date
    public var children: [FileNode]

    public init(
        name: String,
        kind: FileNodeKind,
        extension_: String? = nil,
        relativePath: String,
        absolutePath: String,
        depth: Int,
        size: UInt64 = 0,
        modifiedAt: Date = .distantPast,
        children: [FileNode] = []
    ) {
        self.id = relativePath
        self.name = name
        self.kind = kind
        self.extension_ = extension_
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.depth = depth
        self.size = size
        self.modifiedAt = modifiedAt
        self.children = children
    }

    // MARK: - Hashable (by path, no children)

    public func hash(into hasher: inout Hasher) {
        hasher.combine(relativePath)
    }

    public static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.relativePath == rhs.relativePath
    }

    // MARK: - Computed

    /// Linguaggio dedotto dall'estensione
    public var language: FileLanguage {
        guard let ext = extension_?.lowercased() else { return .unknown }
        return FileLanguage.from(extension: ext)
    }

    /// true se è un file sorgente di codice
    public var isSourceFile: Bool {
        language != .unknown && kind == .file
    }

    /// true se è un file di configurazione/manifest
    public var isConfigFile: Bool {
        guard kind == .file else { return false }
        let configNames: Set<String> = [
            "Package.swift", "Package.resolved",
            "Podfile", "Podfile.lock",
            "Cartfile", "Cartfile.resolved",
            "package.json", "package-lock.json",
            "tsconfig.json", "webpack.config.js",
            "Cargo.toml", "Cargo.lock",
            "go.mod", "go.sum",
            "Gemfile", "Gemfile.lock",
            "requirements.txt", "setup.py", "pyproject.toml",
            "Makefile", "CMakeLists.txt",
            "Dockerfile", "docker-compose.yml",
            ".gitignore", ".editorconfig",
            "build.gradle", "build.gradle.kts", "pom.xml",
        ]
        return configNames.contains(name)
    }

    /// Numero totale di file nel sottoalbero (incluso se stesso se file)
    public var totalFileCount: Int {
        if kind == .file { return 1 }
        return children.reduce(0) { $0 + $1.totalFileCount }
    }

    /// Dimensione totale in byte del sottoalbero
    public var totalSize: UInt64 {
        if kind == .file { return size }
        return children.reduce(0) { $0 + $1.totalSize }
    }

    /// Lista piatta di tutti i file nel sottoalbero
    public var allFiles: [FileNode] {
        if kind == .file { return [self] }
        return children.flatMap { $0.allFiles }
    }

    /// Lista piatta di tutti i file sorgente nel sottoalbero
    public var allSourceFiles: [FileNode] {
        allFiles.filter { $0.isSourceFile }
    }

    /// Rappresentazione ad albero testuale (per debug / contesto LLM)
    public func treeString(prefix: String = "", isLast: Bool = true) -> String {
        let connector = isLast ? "└── " : "├── "
        let childPrefix = isLast ? "    " : "│   "
        var line = prefix + connector + name
        if kind == .directory {
            line += "/"
        }
        var result = line + "\n"
        let sortedChildren = children.sorted { a, b in
            if a.kind != b.kind {
                return a.kind == .directory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        for (i, child) in sortedChildren.enumerated() {
            let last = i == sortedChildren.count - 1
            result += child.treeString(prefix: prefix + childPrefix, isLast: last)
        }
        return result
    }
}
