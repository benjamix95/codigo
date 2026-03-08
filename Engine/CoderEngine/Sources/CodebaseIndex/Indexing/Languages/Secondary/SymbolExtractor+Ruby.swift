import Foundation

extension SymbolExtractor {
    // MARK: - Ruby

    static func extractRubySymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let classPattern = #"^\s*class\s+(\w+)(?:\s*<\s*(\w+))?"#
        let modulePattern = #"^\s*module\s+(\w+)"#
        let defPattern = #"^\s*def\s+(self\.)?(\w+[?!=]?)"#
        let attrPattern = #"^\s*attr_(?:accessor|reader|writer)\s+:(\w+)"#
        let constPattern = #"^\s*(\w+)\s*=\s*"#

        var currentClass: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Class
            if let groups = matchGroupsFull(pattern: classPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                currentClass = name
                let parent = groups[safe: 2]
                var inherits: [String] = []
                if let p = parent, !p.isEmpty { inherits.append(p) }
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .class, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        inherits: inherits, language: .ruby
                    ))
                continue
            }

            // Module
            if let groups = matchGroupsFull(pattern: modulePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .module, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: .ruby
                    ))
                continue
            }

            // Def
            if let groups = matchGroupsFull(pattern: defPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let isSelf = groups[safe: 1]?.isEmpty == false
                let isPriv =
                    lineIndex > 0
                    && lines[lineIndex - 1].trimmingCharacters(in: .whitespaces) == "private"
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: currentClass != nil ? .method : .function,
                        filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPriv ? .private : .public,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(300).description,
                        isStatic: isSelf, language: .ruby
                    ))
                continue
            }

            // Attr
            if let groups = matchGroupsFull(pattern: attrPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .property, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(200).description, language: .ruby
                    ))
                continue
            }

            // Top-level constant (UPPER_CASE = ...)
            if currentClass == nil, let groups = matchGroupsFull(pattern: constPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty,
                name.first?.isUppercase == true
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .constant, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: .ruby
                    ))
            }
        }

        return symbols
    }

}
