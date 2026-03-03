import Foundation

extension SymbolExtractor {
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
