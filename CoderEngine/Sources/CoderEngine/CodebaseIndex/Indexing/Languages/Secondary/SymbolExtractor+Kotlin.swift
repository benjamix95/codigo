import Foundation

extension SymbolExtractor {
    // MARK: - Kotlin

    static func extractKotlinSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let classPattern =
            #"^\s*(?:(?:public|private|internal|protected|open|abstract|sealed|data|inner|annotation|value)\s+)*class\s+(\w+)"#
        let objectPattern =
            #"^\s*(?:(?:public|private|internal)\s+)?(?:companion\s+)?object\s+(\w+)"#
        let interfacePattern = #"^\s*(?:(?:public|private|internal|sealed)\s+)*interface\s+(\w+)"#
        let enumPattern = #"^\s*(?:(?:public|private|internal)\s+)?enum\s+class\s+(\w+)"#
        let funcPattern =
            #"^\s*(?:(?:public|private|internal|protected|open|override|abstract|suspend|inline)\s+)*fun\s+(?:<[^>]+>\s+)?(\w+)"#
        let valPattern =
            #"^\s*(?:(?:public|private|internal|protected|override|open|const)\s+)*(?:val|var)\s+(\w+)"#
        let typePattern = #"^\s*(?:(?:public|private|internal)\s+)?typealias\s+(\w+)"#

        var currentClass: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*") || trimmed.hasPrefix("@")
            {
                continue
            }

            let isPub = !trimmed.contains("private ") && !trimmed.contains("internal ")

            // Class
            if let groups = matchGroupsFull(pattern: classPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                currentClass = name
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .class, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .kotlin
                    ))
                continue
            }

            // Object
            if let groups = matchGroupsFull(pattern: objectPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .class, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .kotlin
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
                        endLine: endLine + 1, accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .kotlin
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
                        signature: trimmed.prefix(200).description, language: .kotlin
                    ))
                continue
            }

            // Function
            if let groups = matchGroupsFull(pattern: funcPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: currentClass != nil ? .method : .function,
                        filePath: filePath, line: lineIndex + 1, endLine: endLine + 1,
                        accessLevel: isPub ? .public : .private,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(300).description, language: .kotlin
                    ))
                continue
            }

            // Val/Var
            if let groups = matchGroupsFull(pattern: valPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let isConst = trimmed.contains("const ") || trimmed.contains("val ")
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: isConst ? .constant : .property,
                        filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPub ? .public : .private,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(200).description, language: .kotlin
                    ))
                continue
            }

            // Typealias
            if let groups = matchGroupsFull(pattern: typePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .typeAlias, filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .kotlin
                    ))
            }
        }

        return symbols
    }
}
