import Foundation

extension SymbolExtractor {
    // MARK: - C / C++ / Obj-C

    static func extractCFamilySymbols(
        from content: String,
        lines: [String],
        filePath: String,
        language: FileLanguage
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let structPattern = #"^\s*(?:typedef\s+)?struct\s+(\w+)"#
        let classPattern = #"^\s*(?:class|@interface|@implementation)\s+(\w+)"#
        let enumPattern = #"^\s*(?:typedef\s+)?enum\s+(?:\w+\s+)?(\w+)?"#
        let funcPattern =
            #"^\s*(?:static\s+)?(?:inline\s+)?(?:extern\s+)?(?:virtual\s+)?(?:[\w*&:<>\s]+?)\s+(\w+)\s*\([^;]*$"#
        let definePattern = #"^\s*#define\s+(\w+)"#
        let typedefPattern = #"^\s*typedef\s+.*\s+(\w+)\s*;"#

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*") || trimmed.hasPrefix("#include")
                || trimmed.hasPrefix("#import") || trimmed.hasPrefix("#pragma")
            {
                continue
            }

            // Class / @interface / @implementation
            if let groups = matchGroupsFull(pattern: classPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .class, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description, language: language
                    ))
                continue
            }

            // Struct
            if let groups = matchGroupsFull(pattern: structPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .struct, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description, language: language
                    ))
                continue
            }

            // Enum
            if trimmed.contains("enum"),
                let groups = matchGroupsFull(pattern: enumPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .enum, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description, language: language
                    ))
                continue
            }

            // #define macro
            if let groups = matchGroupsFull(pattern: definePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .macro, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: language
                    ))
                continue
            }

            // Function definition (heuristic: has { on same or next line)
            if trimmed.contains("("), !trimmed.contains(";"), !trimmed.contains("if"),
                !trimmed.contains("for"), !trimmed.contains("while"),
                let groups = matchGroupsFull(pattern: funcPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty,
                !["if", "for", "while", "switch", "return", "sizeof", "typeof"].contains(name)
            {
                let hasBody =
                    trimmed.contains("{")
                    || (lineIndex + 1 < lines.count
                        && lines[lineIndex + 1].trimmingCharacters(in: .whitespaces).hasPrefix("{"))
                if hasBody {
                    let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                    let isStatic = trimmed.hasPrefix("static ")
                    symbols.append(
                        IndexedSymbol(
                            name: name, kind: .function, filePath: filePath,
                            line: lineIndex + 1, endLine: endLine + 1,
                            accessLevel: isStatic ? .fileprivate : .public,
                            signature: trimmed.prefix(300).description,
                            documentation: extractDocComment(lines: lines, beforeLine: lineIndex),
                            isStatic: isStatic, language: language
                        ))
                }
                continue
            }

            // Typedef
            if trimmed.hasPrefix("typedef"),
                let groups = matchGroupsFull(pattern: typedefPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .typeAlias, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: language
                    ))
            }
        }

        return symbols
    }
}
