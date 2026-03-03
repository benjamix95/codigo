import Foundation

extension SymbolExtractor {
    static func extractPHPSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let classPattern =
            #"^\s*(?:(?:abstract|final)\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?(?:\s+implements\s+([\w,\s\\]+))?"#
        let interfacePattern = #"^\s*interface\s+(\w+)"#
        let traitPattern = #"^\s*trait\s+(\w+)"#
        let funcPattern =
            #"^\s*(?:(?:public|protected|private|static|abstract|final)\s+)*function\s+(\w+)"#
        let constPattern = #"^\s*(?:public|protected|private)?\s*const\s+(\w+)"#

        var currentClass: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*") || trimmed.hasPrefix("#")
            {
                continue
            }

            // Class
            if let groups = matchGroupsFull(pattern: classPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                currentClass = name
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                var inherits: [String] = []
                if let e = groups[safe: 2], !e.isEmpty { inherits.append(e) }
                if let i = groups[safe: 3], !i.isEmpty {
                    inherits += i.components(separatedBy: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                }
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .class, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description,
                        inherits: inherits, language: .php
                    ))
                continue
            }

            // Interface
            if let groups = matchGroupsFull(pattern: interfacePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .interface, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description, language: .php
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
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description, language: .php
                    ))
                continue
            }

            // Function / Method
            if let groups = matchGroupsFull(pattern: funcPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                let isStatic = trimmed.contains("static ")
                let access: AccessLevel =
                    trimmed.contains("private ")
                    ? .private : (trimmed.contains("protected ") ? .fileprivate : .public)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: currentClass != nil ? .method : .function,
                        filePath: filePath, line: lineIndex + 1, endLine: endLine + 1,
                        accessLevel: access,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(300).description,
                        isStatic: isStatic, language: .php
                    ))
                continue
            }

            // Const
            if let groups = matchGroupsFull(pattern: constPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .constant, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(200).description, language: .php
                    ))
            }
        }

        return symbols
    }
}
