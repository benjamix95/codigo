import Foundation

extension SymbolExtractor {
    static func extractGoSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let structPattern = #"^\s*type\s+(\w+)\s+struct\s*\{"#
        let interfacePattern = #"^\s*type\s+(\w+)\s+interface\s*\{"#
        let funcPattern = #"^\s*func\s+(\w+)\s*\("#
        let methodPattern = #"^\s*func\s+\(\s*\w+\s+\*?(\w+)\s*\)\s*(\w+)\s*\("#
        let constPattern = #"^\s*(?:const|var)\s+(\w+)"#

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { continue }

            let isExported: (String) -> Bool = { name in
                guard let first = name.first else { return false }
                return first.isUppercase
            }

            // Struct
            if let groups = matchGroupsFull(pattern: structPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .struct, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: isExported(name) ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .go
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
                        endLine: endLine + 1, accessLevel: isExported(name) ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .go
                    ))
                continue
            }

            // Method (func (r *Receiver) Name(...))
            if let groups = matchGroupsFull(pattern: methodPattern, in: line),
                let receiver = groups[safe: 1], let name = groups[safe: 2], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .method, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: isExported(name) ? .public : .private,
                        qualifiedName: "\(receiver).\(name)", containerName: receiver,
                        signature: trimmed.prefix(300).description,
                        documentation: extractDocComment(lines: lines, beforeLine: lineIndex),
                        language: .go
                    ))
                continue
            }

            // Function
            if let groups = matchGroupsFull(pattern: funcPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                let isTest = name.hasPrefix("Test") || name.hasPrefix("Benchmark")
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: isTest ? .test : .function, filePath: filePath,
                        line: lineIndex + 1, endLine: endLine + 1,
                        accessLevel: isExported(name) ? .public : .private,
                        signature: trimmed.prefix(300).description,
                        documentation: extractDocComment(lines: lines, beforeLine: lineIndex),
                        language: .go
                    ))
                continue
            }

            // Const / Var
            if let groups = matchGroupsFull(pattern: constPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let isConst = trimmed.hasPrefix("const")
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: isConst ? .constant : .variable, filePath: filePath,
                        line: lineIndex + 1, accessLevel: isExported(name) ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .go
                    ))
            }
        }

        return symbols
    }

}
