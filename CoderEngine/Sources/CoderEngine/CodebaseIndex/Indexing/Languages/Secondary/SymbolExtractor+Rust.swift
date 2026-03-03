import Foundation

extension SymbolExtractor {
    static func extractRustSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let structPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?struct\s+(\w+)"#
        let enumPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?enum\s+(\w+)"#
        let traitPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?trait\s+(\w+)"#
        let implPattern = #"^\s*impl(?:<[^>]+>)?\s+(?:(\w+)\s+for\s+)?(\w+)"#
        let funcPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(\w+)"#
        let constPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?(?:const|static)\s+(\w+)"#
        let typePattern = #"^\s*(?:pub(?:\(crate\))?\s+)?type\s+(\w+)"#
        let modPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?mod\s+(\w+)"#

        var currentImpl: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*")
            {
                continue
            }

            let isPub = trimmed.hasPrefix("pub")

            // Struct
            if let groups = matchGroupsFull(pattern: structPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .struct, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
                continue
            }

            // Enum
            if let groups = matchGroupsFull(pattern: enumPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .enum, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
                continue
            }

            // Trait
            if let groups = matchGroupsFull(pattern: traitPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .trait, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
                continue
            }

            // Impl block
            if let groups = matchGroupsFull(pattern: implPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                currentImpl = name
                let traitName = groups[safe: 1]
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                var inherits: [String] = []
                if let t = traitName, !t.isEmpty { inherits.append(t) }
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .extension, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description,
                        inherits: inherits, language: .rust
                    ))
                continue
            }

            // Function
            if let groups = matchGroupsFull(pattern: funcPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                let isTest =
                    name.hasPrefix("test_")
                    || (lineIndex > 0 && lines[lineIndex - 1].contains("#[test]"))
                symbols.append(
                    IndexedSymbol(
                        name: name,
                        kind: isTest ? .test : (currentImpl != nil ? .method : .function),
                        filePath: filePath, line: lineIndex + 1, endLine: endLine + 1,
                        accessLevel: isPub ? .public : .private,
                        qualifiedName: currentImpl.map { "\($0).\(name)" },
                        containerName: currentImpl,
                        signature: trimmed.prefix(300).description,
                        documentation: extractDocComment(lines: lines, beforeLine: lineIndex),
                        language: .rust
                    ))
                continue
            }

            // Const/Static
            if let groups = matchGroupsFull(pattern: constPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .constant, filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
                continue
            }

            // Type alias
            if let groups = matchGroupsFull(pattern: typePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .typeAlias, filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
                continue
            }

            // Module
            if let groups = matchGroupsFull(pattern: modPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .module, filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
            }
        }

        return symbols
    }

    // MARK: - Java
}
