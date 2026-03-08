import Foundation

extension SymbolExtractor {
    // MARK: - C#

    static func extractCSharpSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let accessPat = #"(?:(public|protected|private|internal)\s+)?"#
        let classPattern =
            #"^\s*"# + accessPat
            + #"(?:static\s+)?(?:abstract\s+)?(?:sealed\s+)?(?:partial\s+)?class\s+(\w+)"#
        let interfacePattern = #"^\s*"# + accessPat + #"(?:partial\s+)?interface\s+(\w+)"#
        let structPattern = #"^\s*"# + accessPat + #"(?:readonly\s+)?(?:partial\s+)?struct\s+(\w+)"#
        let enumPattern = #"^\s*"# + accessPat + #"enum\s+(\w+)"#
        let methodPattern =
            #"^\s*"# + accessPat
            + #"(?:static\s+)?(?:virtual\s+)?(?:override\s+)?(?:abstract\s+)?(?:async\s+)?(?:[\w<>\[\]?]+)\s+(\w+)\s*\("#
        let propPattern =
            #"^\s*"# + accessPat
            + #"(?:static\s+)?(?:virtual\s+)?(?:override\s+)?(?:[\w<>\[\]?]+)\s+(\w+)\s*\{"#
        let namespacePattern = #"^\s*namespace\s+([\w.]+)"#

        var currentClass: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*") || trimmed.hasPrefix("[")
            {
                continue
            }

            // Namespace
            if let groups = matchGroupsFull(pattern: namespacePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .module, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: .csharp
                    ))
                continue
            }

            // Class
            if let groups = matchGroupsFull(pattern: classPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let access = parseCSharpAccess(groups[safe: 1])
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                currentClass = name
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .class, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: access,
                        signature: trimmed.prefix(200).description, language: .csharp
                    ))
                continue
            }

            // Interface
            if let groups = matchGroupsFull(pattern: interfacePattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let access = parseCSharpAccess(groups[safe: 1])
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .interface, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: access,
                        signature: trimmed.prefix(200).description, language: .csharp
                    ))
                continue
            }

            // Struct
            if let groups = matchGroupsFull(pattern: structPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let access = parseCSharpAccess(groups[safe: 1])
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .struct, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: access,
                        signature: trimmed.prefix(200).description, language: .csharp
                    ))
                continue
            }

            // Enum
            if let groups = matchGroupsFull(pattern: enumPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let access = parseCSharpAccess(groups[safe: 1])
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .enum, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: access,
                        signature: trimmed.prefix(200).description, language: .csharp
                    ))
                continue
            }

            // Method
            if trimmed.contains("("), !trimmed.contains("new "),
                let groups = matchGroupsFull(pattern: methodPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty,
                !["if", "for", "while", "switch", "catch", "return", "using", "foreach"].contains(
                    name)
            {
                let access = parseCSharpAccess(groups[safe: 1])
                let isStatic = trimmed.contains("static ")
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                let isTest =
                    lineIndex > 0
                    && (lines[lineIndex - 1].contains("[Test")
                        || lines[lineIndex - 1].contains("[Fact"))
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: isTest ? .test : .method, filePath: filePath,
                        line: lineIndex + 1, endLine: endLine + 1, accessLevel: access,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(300).description,
                        isStatic: isStatic, language: .csharp
                    ))
                continue
            }

            // Property
            if currentClass != nil, trimmed.contains("{"),
                let groups = matchGroupsFull(pattern: propPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty,
                !["if", "for", "while", "switch", "catch", "return", "get", "set"].contains(name)
            {
                let access = parseCSharpAccess(groups[safe: 1])
                let isStatic = trimmed.contains("static ")
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .property, filePath: filePath, line: lineIndex + 1,
                        accessLevel: access,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(200).description,
                        isStatic: isStatic, language: .csharp
                    ))
            }
        }

        return symbols
    }

}
