import Foundation

extension SymbolExtractor {
    // MARK: - Swift

    static func extractSwiftSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []
        var containerStack: [(name: String, kind: SymbolKind, indent: Int)] = []

        let accessPattern = #"(?:(open|public|internal|fileprivate|private)\s+)?"#
        let staticPattern = #"(?:(static|class)\s+)?"#
        let annotationPattern = #"(?:(@\w+(?:\([^)]*\))?)\s+)*"#

        // Combined pattern for type declarations
        let typePatterns: [(String, SymbolKind)] = [
            (#"^\s*"# + annotationPattern + accessPattern + #"(?:final\s+)?class\s+(\w+)"#, .class),
            (#"^\s*"# + annotationPattern + accessPattern + #"struct\s+(\w+)"#, .struct),
            (#"^\s*"# + annotationPattern + accessPattern + #"enum\s+(\w+)"#, .enum),
            (#"^\s*"# + annotationPattern + accessPattern + #"protocol\s+(\w+)"#, .protocol),
            (#"^\s*"# + annotationPattern + accessPattern + #"actor\s+(\w+)"#, .class),
            (#"^\s*"# + annotationPattern + accessPattern + #"extension\s+(\w+)"#, .extension),
        ]

        let funcPattern =
            #"^\s*"# + annotationPattern + accessPattern + staticPattern
            + #"(?:mutating\s+|nonmutating\s+|nonisolated\s+)?func\s+(\w+(?:\s*\([^)]*\))?)"#

        let initPattern =
            #"^\s*"# + annotationPattern + accessPattern
            + #"(?:convenience\s+|required\s+)?init\s*(\([^)]*\))?"#

        let varPattern =
            #"^\s*"# + annotationPattern + accessPattern + staticPattern
            + #"(let|var)\s+(\w+)"#

        let typealiasPattern =
            #"^\s*"# + accessPattern + #"typealias\s+(\w+)"#

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*")
            {
                continue
            }

            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count

            // Pop containers with deeper or equal indent (heuristic)
            while let last = containerStack.last, indent <= last.indent {
                containerStack.removeLast()
            }

            let currentContainer = containerStack.last?.name

            // Type declarations
            for (pattern, kind) in typePatterns {
                if let match = firstMatch(pattern: pattern, in: line) {
                    let groups = matchGroups(pattern: pattern, in: line)
                    let name = groups.last ?? match
                    let access = parseAccessLevel(from: groups)
                    let inherits = extractSwiftInheritance(from: line, afterName: name)
                    let generics = extractGenericParams(from: line)
                    let annotations = extractAnnotations(from: line)

                    let endLine = findBlockEnd(lines: lines, startLine: lineIndex)

                    let symbol = IndexedSymbol(
                        name: name,
                        kind: kind,
                        filePath: filePath,
                        line: lineIndex + 1,
                        endLine: endLine + 1,
                        accessLevel: access,
                        qualifiedName: currentContainer.map { "\($0).\(name)" } ?? name,
                        containerName: currentContainer,
                        signature: trimmed.prefix(200).description,
                        documentation: extractDocComment(lines: lines, beforeLine: lineIndex),
                        inherits: inherits,
                        genericParameters: generics,
                        isStatic: false,
                        annotations: annotations,
                        language: .swift
                    )
                    symbols.append(symbol)

                    if kind != .extension {
                        containerStack.append((name: name, kind: kind, indent: indent))
                    } else {
                        containerStack.append((name: name, kind: kind, indent: indent))
                    }
                    break
                }
            }

            // Functions
            if firstMatch(pattern: funcPattern, in: line) != nil {
                let groups = matchGroups(pattern: funcPattern, in: line)
                let nameRaw = groups.last ?? ""
                let name =
                    nameRaw.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces)
                    ?? nameRaw
                guard !name.isEmpty else { continue }
                let access = parseAccessLevel(from: groups)
                let isStatic = groups.contains("static") || groups.contains("class")
                let annotations = extractAnnotations(from: line)
                let isTest = name.hasPrefix("test") && currentContainer != nil
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)

                let symbol = IndexedSymbol(
                    name: name,
                    kind: isTest ? .test : (currentContainer != nil ? .method : .function),
                    filePath: filePath,
                    line: lineIndex + 1,
                    endLine: endLine + 1,
                    accessLevel: access,
                    qualifiedName: currentContainer.map { "\($0).\(name)" } ?? name,
                    containerName: currentContainer,
                    signature: trimmed.prefix(300).description,
                    documentation: extractDocComment(lines: lines, beforeLine: lineIndex),
                    isStatic: isStatic,
                    annotations: annotations,
                    language: .swift
                )
                symbols.append(symbol)
            }

            // Init
            if firstMatch(pattern: initPattern, in: line) != nil, trimmed.contains("init") {
                let groups = matchGroups(pattern: initPattern, in: line)
                let access = parseAccessLevel(from: groups)
                let annotations = extractAnnotations(from: line)
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)

                let symbol = IndexedSymbol(
                    name: "init",
                    kind: .method,
                    filePath: filePath,
                    line: lineIndex + 1,
                    endLine: endLine + 1,
                    accessLevel: access,
                    qualifiedName: currentContainer.map { "\($0).init" } ?? "init",
                    containerName: currentContainer,
                    signature: trimmed.prefix(300).description,
                    documentation: extractDocComment(lines: lines, beforeLine: lineIndex),
                    annotations: annotations,
                    language: .swift
                )
                symbols.append(symbol)
            }

            // Properties (let/var)
            if firstMatch(pattern: varPattern, in: line) != nil,
                !trimmed.contains("func "), !trimmed.contains("class "),
                !trimmed.contains("struct ")
            {
                let groups = matchGroups(pattern: varPattern, in: line)
                let name = groups.last ?? ""
                guard !name.isEmpty, name != "let", name != "var" else { continue }
                let access = parseAccessLevel(from: groups)
                let isStatic = groups.contains("static") || groups.contains("class")
                let isConstant = groups.contains("let")

                // Skip local variables (inside functions)
                let isTopOrTypeMember =
                    containerStack.isEmpty || containerStack.last?.kind.isType == true
                    || containerStack.last?.kind == .extension
                guard isTopOrTypeMember else { continue }

                let symbol = IndexedSymbol(
                    name: name,
                    kind: isConstant ? .constant : .property,
                    filePath: filePath,
                    line: lineIndex + 1,
                    accessLevel: access,
                    qualifiedName: currentContainer.map { "\($0).\(name)" } ?? name,
                    containerName: currentContainer,
                    signature: trimmed.prefix(200).description,
                    isStatic: isStatic,
                    language: .swift
                )
                symbols.append(symbol)
            }

            // Typealias
            if firstMatch(pattern: typealiasPattern, in: line) != nil {
                let groups = matchGroups(pattern: typealiasPattern, in: line)
                let name = groups.last ?? ""
                guard !name.isEmpty else { continue }
                let access = parseAccessLevel(from: groups)

                let symbol = IndexedSymbol(
                    name: name,
                    kind: .typeAlias,
                    filePath: filePath,
                    line: lineIndex + 1,
                    accessLevel: access,
                    qualifiedName: currentContainer.map { "\($0).\(name)" } ?? name,
                    containerName: currentContainer,
                    signature: trimmed.prefix(200).description,
                    language: .swift
                )
                symbols.append(symbol)
            }
        }

        return symbols
    }
}
