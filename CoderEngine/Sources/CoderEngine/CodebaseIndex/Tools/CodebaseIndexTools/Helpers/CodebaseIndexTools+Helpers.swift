import Foundation

// MARK: - Formatting and utility helpers

extension CodebaseIndexTools {
    func normalizedFilePattern(from rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if value == "." { return nil }
        if value.hasPrefix("./") {
            value = String(value.dropFirst(2))
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        guard !value.isEmpty, value != "." else { return nil }
        return value
    }

    func applyFilePattern(_ files: [FileNode], filePattern: String?) async -> [FileNode] {
        guard let filePattern else { return files }
        let normalizedPattern = filePattern.lowercased()
        if normalizedPattern.contains("*") {
            let allowed = Set((await index.glob(pattern: filePattern, limit: 5_000)).map {
                $0.relativePath.lowercased()
            })
            return files.filter { allowed.contains($0.relativePath.lowercased()) }
        }

        return files.filter { node in
            let path = node.relativePath.lowercased()
            if path == normalizedPattern { return true }
            if path.hasPrefix(normalizedPattern + "/") { return true }
            return path.contains(normalizedPattern)
        }
    }

    func formatSymbolResults(_ symbols: [IndexedSymbol], title: String) -> ToolOutput {
        var lines: [String] = []
        lines.append("Found \(symbols.count) result(s):\n")
        for symbol in symbols {
            lines.append(symbol.compactDescription)
        }

        return ToolOutput(
            ok: true,
            title: title,
            output: String(lines.joined(separator: "\n").prefix(8000)),
            detail: "\(symbols.count) results"
        )
    }

    func formatFileSymbols(_ symbols: [IndexedSymbol], filePath: String) -> ToolOutput {
        var lines: [String] = []
        lines.append("Symbols in \(filePath) (\(symbols.count)):\n")

        // Group: types first, then functions, then properties
        let types = symbols.filter { $0.kind.isType }
        let callables = symbols.filter { $0.kind.isCallable }
        let data = symbols.filter { $0.kind.isDataDeclaration }
        let other = symbols.filter {
            !$0.kind.isType && !$0.kind.isCallable && !$0.kind.isDataDeclaration
        }

        if !types.isEmpty {
            lines.append("Types:")
            for s in types {
                let range = s.endLine > 0 ? "L\(s.line)-\(s.endLine)" : "L\(s.line)"
                let inheritsStr = s.inherits.isEmpty ? "" : " : \(s.inherits.joined(separator: ", "))"
                lines.append("  \(s.kind.rawValue) \(s.name)\(inheritsStr) (\(range))")
            }
            lines.append("")
        }

        if !callables.isEmpty {
            lines.append("Functions/Methods:")
            for s in callables {
                let range = s.endLine > 0 ? "L\(s.line)-\(s.endLine)" : "L\(s.line)"
                let container = s.containerName.map { "\($0)." } ?? ""
                let staticStr = s.isStatic ? "static " : ""
                lines.append("  \(staticStr)\(container)\(s.name) (\(range))")
            }
            lines.append("")
        }

        if !data.isEmpty {
            lines.append("Properties/Constants:")
            for s in data {
                let container = s.containerName.map { "\($0)." } ?? ""
                let staticStr = s.isStatic ? "static " : ""
                lines.append("  \(staticStr)\(s.kind.rawValue) \(container)\(s.name) (L\(s.line))")
            }
            lines.append("")
        }

        if !other.isEmpty {
            lines.append("Other:")
            for s in other {
                lines.append("  \(s.kind.rawValue) \(s.name) (L\(s.line))")
            }
        }

        return ToolOutput(
            ok: true,
            title: "list_symbols: \(filePath)",
            output: String(lines.joined(separator: "\n").prefix(8000)),
            detail: "\(symbols.count) symbols"
        )
    }

    func formatFileResults(_ files: [FileNode], title: String) -> ToolOutput {
        var lines: [String] = []
        lines.append("Found \(files.count) file(s):\n")
        for file in files {
            let sizeStr = ByteCountFormatter.string(
                fromByteCount: Int64(file.size), countStyle: .file)
            let langStr = file.language != .unknown ? " [\(file.language.rawValue)]" : ""
            lines.append("  \(file.relativePath) (\(sizeStr))\(langStr)")
        }

        return ToolOutput(
            ok: true,
            title: title,
            output: lines.joined(separator: "\n"),
            detail: "\(files.count) files"
        )
    }
}

struct ToolOutput {
    let ok: Bool
    let title: String
    let output: String
    let detail: String?

    init(ok: Bool, title: String, output: String, detail: String? = nil) {
        self.ok = ok
        self.title = title
        self.output = output
        self.detail = detail
    }
}
