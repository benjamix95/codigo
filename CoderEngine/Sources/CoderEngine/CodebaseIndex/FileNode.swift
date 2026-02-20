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

// MARK: - FileNodeKind

public enum FileNodeKind: String, Sendable, Codable {
    case file
    case directory
    case symlink
}

// MARK: - FileLanguage

public enum FileLanguage: String, Sendable, CaseIterable {
    case swift
    case objectiveC
    case objectiveCPP
    case c
    case cpp
    case header
    case python
    case javascript
    case typescript
    case typescriptReact
    case javascriptReact
    case go
    case rust
    case java
    case kotlin
    case ruby
    case php
    case csharp
    case html
    case css
    case scss
    case json
    case yaml
    case toml
    case xml
    case markdown
    case shell
    case sql
    case graphql
    case proto
    case dart
    case elixir
    case lua
    case r
    case scala
    case haskell
    case zig
    case unknown

    public static func from(extension ext: String) -> FileLanguage {
        switch ext {
        case "swift": return .swift
        case "m": return .objectiveC
        case "mm": return .objectiveCPP
        case "c": return .c
        case "cpp", "cc", "cxx": return .cpp
        case "h", "hpp", "hxx": return .header
        case "py", "pyw", "pyi": return .python
        case "js", "mjs", "cjs": return .javascript
        case "ts", "mts", "cts": return .typescript
        case "tsx": return .typescriptReact
        case "jsx": return .javascriptReact
        case "go": return .go
        case "rs": return .rust
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "rb", "rake": return .ruby
        case "php": return .php
        case "cs": return .csharp
        case "html", "htm": return .html
        case "css": return .css
        case "scss", "sass", "less": return .scss
        case "json", "jsonc", "json5": return .json
        case "yml", "yaml": return .yaml
        case "toml": return .toml
        case "xml", "plist", "xib", "storyboard": return .xml
        case "md", "markdown", "rst": return .markdown
        case "sh", "bash", "zsh", "fish": return .shell
        case "sql": return .sql
        case "graphql", "gql": return .graphql
        case "proto": return .proto
        case "dart": return .dart
        case "ex", "exs": return .elixir
        case "lua": return .lua
        case "r", "R": return .r
        case "scala", "sc": return .scala
        case "hs": return .haskell
        case "zig": return .zig
        default: return .unknown
        }
    }

    /// Commento di linea per il linguaggio
    public var lineComment: String? {
        switch self {
        case .swift, .objectiveC, .objectiveCPP, .c, .cpp, .header,
            .javascript, .typescript, .typescriptReact, .javascriptReact,
            .go, .rust, .java, .kotlin, .csharp, .scala, .dart, .proto, .zig:
            return "//"
        case .python, .ruby, .shell, .r, .elixir:
            return "#"
        case .lua, .sql:
            return "--"
        case .haskell:
            return "--"
        case .php:
            return "//"
        default:
            return nil
        }
    }

    /// Estensioni comuni per il linguaggio
    public var commonExtensions: [String] {
        switch self {
        case .swift: return ["swift"]
        case .objectiveC: return ["m"]
        case .objectiveCPP: return ["mm"]
        case .c: return ["c"]
        case .cpp: return ["cpp", "cc", "cxx"]
        case .header: return ["h", "hpp"]
        case .python: return ["py"]
        case .javascript: return ["js", "mjs"]
        case .typescript: return ["ts", "mts"]
        case .typescriptReact: return ["tsx"]
        case .javascriptReact: return ["jsx"]
        case .go: return ["go"]
        case .rust: return ["rs"]
        case .java: return ["java"]
        case .kotlin: return ["kt"]
        case .ruby: return ["rb"]
        case .php: return ["php"]
        case .csharp: return ["cs"]
        case .html: return ["html", "htm"]
        case .css: return ["css"]
        case .scss: return ["scss", "sass"]
        case .json: return ["json"]
        case .yaml: return ["yml", "yaml"]
        case .toml: return ["toml"]
        case .xml: return ["xml"]
        case .markdown: return ["md"]
        case .shell: return ["sh", "bash", "zsh"]
        case .sql: return ["sql"]
        case .graphql: return ["graphql"]
        case .proto: return ["proto"]
        case .dart: return ["dart"]
        case .elixir: return ["ex", "exs"]
        case .lua: return ["lua"]
        case .r: return ["r", "R"]
        case .scala: return ["scala"]
        case .haskell: return ["hs"]
        case .zig: return ["zig"]
        case .unknown: return []
        }
    }
}

// MARK: - FileStats

/// Statistiche aggregate su un set di file
public struct FileStats: Sendable {
    public let totalFiles: Int
    public let totalDirectories: Int
    public let totalSize: UInt64
    public let languageBreakdown: [FileLanguage: Int]
    public let largestFiles: [(path: String, size: UInt64)]
    public let deepestPath: (path: String, depth: Int)?

    public init(
        totalFiles: Int,
        totalDirectories: Int,
        totalSize: UInt64,
        languageBreakdown: [FileLanguage: Int],
        largestFiles: [(path: String, size: UInt64)],
        deepestPath: (path: String, depth: Int)?
    ) {
        self.totalFiles = totalFiles
        self.totalDirectories = totalDirectories
        self.totalSize = totalSize
        self.languageBreakdown = languageBreakdown
        self.largestFiles = largestFiles
        self.deepestPath = deepestPath
    }

    /// Formato leggibile per contesto LLM
    public var summary: String {
        var lines: [String] = []
        lines.append("📊 Project Stats")
        lines.append("  Files: \(totalFiles) | Directories: \(totalDirectories)")
        lines.append(
            "  Total size: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))"
        )

        if !languageBreakdown.isEmpty {
            lines.append("  Languages:")
            let sorted = languageBreakdown.sorted { $0.value > $1.value }
            for (lang, count) in sorted.prefix(10) {
                lines.append("    \(lang.rawValue): \(count) files")
            }
        }

        if !largestFiles.isEmpty {
            lines.append("  Largest files:")
            for (path, size) in largestFiles.prefix(5) {
                lines.append(
                    "    \(path) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"
                )
            }
        }

        if let deepest = deepestPath {
            lines.append("  Deepest path (depth \(deepest.depth)): \(deepest.path)")
        }

        return lines.joined(separator: "\n")
    }
}
