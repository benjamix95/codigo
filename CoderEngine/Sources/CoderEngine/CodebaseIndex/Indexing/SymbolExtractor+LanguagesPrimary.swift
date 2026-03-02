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

    // MARK: - JavaScript

    static func extractJavaScriptSymbols(
        from content: String,
        lines: [String],
        filePath: String,
        language: FileLanguage
    ) -> [IndexedSymbol] {
        return extractJSTSSymbols(
            from: content, lines: lines, filePath: filePath, language: language, isTypeScript: false
        )
    }

    // MARK: - TypeScript

    static func extractTypeScriptSymbols(
        from content: String,
        lines: [String],
        filePath: String,
        language: FileLanguage
    ) -> [IndexedSymbol] {
        return extractJSTSSymbols(
            from: content, lines: lines, filePath: filePath, language: language, isTypeScript: true)
    }

    /// Shared JS/TS extractor
    static func extractJSTSSymbols(
        from content: String,
        lines: [String],
        filePath: String,
        language: FileLanguage,
        isTypeScript: Bool
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let exportPrefix = #"(?:export\s+(?:default\s+)?)?"#

        // Classes
        let classPattern =
            #"^\s*"# + exportPrefix
            + #"(?:abstract\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?(?:\s+implements\s+([\w,\s]+))?"#
        // Interfaces (TS)
        let interfacePattern =
            #"^\s*"# + exportPrefix + #"interface\s+(\w+)(?:\s+extends\s+([\w,\s]+))?"#
        // Type aliases (TS)
        let typePattern = #"^\s*"# + exportPrefix + #"type\s+(\w+)"#
        // Enums
        let enumPattern = #"^\s*"# + exportPrefix + #"(?:const\s+)?enum\s+(\w+)"#
        // Functions
        let funcPattern = #"^\s*"# + exportPrefix + #"(?:async\s+)?function\s*\*?\s+(\w+)"#
        // Arrow / const functions
        let arrowPattern =
            #"^\s*"# + exportPrefix
            + #"(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[^=])\s*=>"#
        // Const/let/var
        let varPattern = #"^\s*"# + exportPrefix + #"(const|let|var)\s+(\w+)"#

        var currentClass: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*")
            {
                continue
            }

            // Class
            if let groups = matchGroupsFull(pattern: classPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let extends_ = groups[safe: 2]
                let implements_ = groups[safe: 3]
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
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description,
                        inherits: inherits, language: language
                    ))
                continue
            }

            // Interface (TS)
            if isTypeScript, let groups = matchGroupsFull(pattern: interfacePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                let extends_ =
                    groups[safe: 2]?.components(separatedBy: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    } ?? []
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .interface, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description,
                        inherits: extends_.filter { !$0.isEmpty }, language: language
                    ))
                continue
            }

            // Type alias (TS)
            if isTypeScript, let groups = matchGroupsFull(pattern: typePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .typeAlias, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: language
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
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description, language: language
                    ))
                continue
            }

            // Function declaration
            if let groups = matchGroupsFull(pattern: funcPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                let isTest =
                    name.hasPrefix("test") || name.hasPrefix("it") || name.hasPrefix("describe")
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: isTest ? .test : .function, filePath: filePath,
                        line: lineIndex + 1, endLine: endLine + 1, accessLevel: .public,
                        containerName: currentClass,
                        signature: trimmed.prefix(300).description, language: language
                    ))
                continue
            }

            // Arrow function / const function
            if let groups = matchGroupsFull(pattern: arrowPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .function, filePath: filePath,
                        line: lineIndex + 1, endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(300).description, language: language
                    ))
                continue
            }

            // Const/let/var (only top-level or module scope)
            if line.first != " " && line.first != "\t",
                let groups = matchGroupsFull(pattern: varPattern, in: line),
                let varKind = groups[safe: 1], let name = groups[safe: 2], !name.isEmpty
            {
                // Skip if it's also a function (arrow)
                if line.contains("=>") || line.contains("function") { continue }
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: varKind == "const" ? .constant : .variable,
                        filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: language
                    ))
            }
        }

        return symbols
    }
}
