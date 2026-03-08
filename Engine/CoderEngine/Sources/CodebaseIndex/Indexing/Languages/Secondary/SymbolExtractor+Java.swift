import Foundation

extension SymbolExtractor {
    // MARK: - Java

    static func extractJavaSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let accessPat = #"(?:(public|protected|private)\s+)?"#
        let classPattern =
            #"^\s*"# + accessPat
            + #"(?:static\s+)?(?:abstract\s+)?(?:final\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?(?:\s+implements\s+([\w,\s]+))?"#
        let interfacePattern =
            #"^\s*"# + accessPat + #"interface\s+(\w+)(?:\s+extends\s+([\w,\s]+))?"#
        let enumPattern = #"^\s*"# + accessPat + #"enum\s+(\w+)"#
        let methodPattern =
            #"^\s*"# + accessPat
            + #"(?:static\s+)?(?:final\s+)?(?:synchronized\s+)?(?:abstract\s+)?(?:[\w<>\[\]]+)\s+(\w+)\s*\("#
        let fieldPattern =
            #"^\s*"# + accessPat + #"(?:static\s+)?(?:final\s+)?(?:[\w<>\[\]]+)\s+(\w+)\s*[=;]"#

        var currentClass: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*") || trimmed.hasPrefix("@")
            {
                continue
            }

            // Class
            if let groups = matchGroupsFull(pattern: classPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let access = parseJavaAccess(groups[safe: 1])
                let extends_ = groups[safe: 3]
                let implements_ = groups[safe: 4]
                var inherits: [String] = []
                if let e = extends_, !e.isEmpty { inherits.append(e) }
                if let i = implements_, !i.isEmpty {
                    inherits += i.components(separatedBy: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                }
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                currentClass = name
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .class, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: access,
                        signature: trimmed.prefix(200).description,
                        inherits: inherits, language: .java
                    ))
                continue
            }

            // Interface
            if let groups = matchGroupsFull(pattern: interfacePattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let access = parseJavaAccess(groups[safe: 1])
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .interface, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: access,
                        signature: trimmed.prefix(200).description, language: .java
                    ))
                continue
            }

            // Enum
            if let groups = matchGroupsFull(pattern: enumPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let access = parseJavaAccess(groups[safe: 1])
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .enum, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: access,
                        signature: trimmed.prefix(200).description, language: .java
                    ))
                continue
            }

            // Method
            if trimmed.contains("("), !trimmed.contains("new "),
                let groups = matchGroupsFull(pattern: methodPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty,
                !["if", "for", "while", "switch", "catch", "return"].contains(name)
            {
                let access = parseJavaAccess(groups[safe: 1])
                let isStatic = trimmed.contains("static ")
                let isTest =
                    lineIndex > 0
                    && lines[lineIndex - 1].trimmingCharacters(in: .whitespaces).hasPrefix("@Test")
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: isTest ? .test : .method, filePath: filePath,
                        line: lineIndex + 1, endLine: endLine + 1, accessLevel: access,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(300).description,
                        isStatic: isStatic, language: .java
                    ))
                continue
            }

            // Field (only inside class)
            if currentClass != nil, !trimmed.contains("("),
                let groups = matchGroupsFull(pattern: fieldPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty,
                !["if", "for", "while", "return", "class", "interface"].contains(name)
            {
                let access = parseJavaAccess(groups[safe: 1])
                let isStatic = trimmed.contains("static ")
                let isFinal = trimmed.contains("final ")
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: isFinal ? .constant : .property, filePath: filePath,
                        line: lineIndex + 1, accessLevel: access,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(200).description,
                        isStatic: isStatic, language: .java
                    ))
            }
        }

        return symbols
    }
}
