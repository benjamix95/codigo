import Foundation

extension SymbolExtractor {
    // MARK: - Python

    static func extractPythonSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []
        var currentClass: String?
        var classIndent: Int = -1

        let classPattern = #"^(\s*)class\s+(\w+)\s*(?:\(([^)]*)\))?\s*:"#
        let funcPattern = #"^(\s*)(?:async\s+)?def\s+(\w+)\s*\(([^)]*)\)"#
        let assignPattern = #"^(\w+)\s*(?::\s*\w+\s*)?="#

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Class
            if let groups = matchGroupsFull(pattern: classPattern, in: line) {
                let indent = groups[safe: 1]?.count ?? 0
                let name = groups[safe: 2] ?? ""
                let bases =
                    groups[safe: 3]?.components(separatedBy: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    } ?? []

                currentClass = name
                classIndent = indent
                let endLine = findPythonBlockEnd(
                    lines: lines, startLine: lineIndex, startIndent: indent)

                symbols.append(
                    IndexedSymbol(
                        name: name,
                        kind: .class,
                        filePath: filePath,
                        line: lineIndex + 1,
                        endLine: endLine + 1,
                        accessLevel: name.hasPrefix("_") ? .private : .public,
                        containerName: nil,
                        signature: trimmed.prefix(200).description,
                        documentation: extractPythonDocstring(lines: lines, afterLine: lineIndex),
                        inherits: bases.filter { !$0.isEmpty },
                        language: .python
                    ))
                continue
            }

            // Function / method
            if let groups = matchGroupsFull(pattern: funcPattern, in: line) {
                let indent = groups[safe: 1]?.count ?? 0
                let name = groups[safe: 2] ?? ""

                // If we're inside a class
                let isMethod = currentClass != nil && indent > classIndent
                if indent <= classIndent {
                    currentClass = nil
                    classIndent = -1
                }

                let container = isMethod ? currentClass : nil
                let access: AccessLevel =
                    name.hasPrefix("__") && !name.hasSuffix("__")
                    ? .private
                    : (name.hasPrefix("_") ? .fileprivate : .public)

                let isTest = name.hasPrefix("test_") || name.hasPrefix("test")
                let isStatic =
                    lineIndex > 0
                    && lines[lineIndex - 1].trimmingCharacters(in: .whitespaces).contains(
                        "@staticmethod")
                let endLine = findPythonBlockEnd(
                    lines: lines, startLine: lineIndex, startIndent: indent)

                var annotations: [String] = []
                if lineIndex > 0 {
                    let prev = lines[lineIndex - 1].trimmingCharacters(in: .whitespaces)
                    if prev.hasPrefix("@") {
                        annotations.append(prev)
                    }
                }

                symbols.append(
                    IndexedSymbol(
                        name: name,
                        kind: isTest ? .test : (isMethod ? .method : .function),
                        filePath: filePath,
                        line: lineIndex + 1,
                        endLine: endLine + 1,
                        accessLevel: access,
                        qualifiedName: container.map { "\($0).\(name)" },
                        containerName: container,
                        signature: trimmed.prefix(300).description,
                        documentation: extractPythonDocstring(lines: lines, afterLine: lineIndex),
                        isStatic: isStatic,
                        annotations: annotations,
                        language: .python
                    ))
                continue
            }

            // Top-level assignments (module-level constants/variables)
            if currentClass == nil, let groups = matchGroupsFull(pattern: assignPattern, in: line) {
                let name = groups[safe: 1] ?? ""
                guard !name.isEmpty, !name.hasPrefix(" "), name != "if", name != "else",
                    name != "for"
                else { continue }
                let isConstant = name == name.uppercased() && name.count > 1
                symbols.append(
                    IndexedSymbol(
                        name: name,
                        kind: isConstant ? .constant : .variable,
                        filePath: filePath,
                        line: lineIndex + 1,
                        accessLevel: name.hasPrefix("_") ? .private : .public,
                        signature: trimmed.prefix(120).description,
                        language: .python
                    ))
            }
        }

        return symbols
    }
}
