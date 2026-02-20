import Foundation

// MARK: - SymbolExtractor

/// Motore di estrazione simboli multi-linguaggio basato su regex.
/// Leggero e veloce, non richiede SourceKit o LSP.
public enum SymbolExtractor {

    // MARK: - Public API

    /// Indicizza un file sorgente ed estrae tutti i simboli
    public static func indexFile(
        absolutePath: String,
        relativePath: String,
        language: FileLanguage? = nil
    ) -> IndexedFile? {
        guard let data = FileManager.default.contents(atPath: absolutePath),
            let content = String(data: data, encoding: .utf8)
        else { return nil }

        let ext = (absolutePath as NSString).pathExtension.lowercased()
        let lang = language ?? FileLanguage.from(extension: ext)
        guard lang != .unknown else { return nil }

        let lines = content.components(separatedBy: "\n")
        let lineCount = lines.count
        let size = UInt64(data.count)
        let contentHash = fnv1aHash(data)

        let imports = extractImports(from: content, language: lang)
        let symbols = extractSymbols(
            from: content, lines: lines, filePath: relativePath, language: lang)

        return IndexedFile(
            relativePath: relativePath,
            absolutePath: absolutePath,
            language: lang,
            symbols: symbols,
            imports: imports,
            lineCount: lineCount,
            size: size,
            indexedAt: .now,
            contentHash: contentHash
        )
    }

    /// Estrae solo l'outline di un file (simboli top-level + nidificati 1 livello)
    public static func fileOutline(absolutePath: String, relativePath: String) -> String {
        guard let indexed = indexFile(absolutePath: absolutePath, relativePath: relativePath) else {
            return "(unable to parse)"
        }
        return indexed.outline
    }

    // MARK: - Import Extraction

    static func extractImports(from content: String, language: FileLanguage) -> [String] {
        switch language {
        case .swift:
            return matchAll(pattern: #"^\s*import\s+(\w+)"#, in: content, group: 1)
        case .python:
            let direct = matchAll(pattern: #"^\s*import\s+([\w.]+)"#, in: content, group: 1)
            let from = matchAll(pattern: #"^\s*from\s+([\w.]+)\s+import"#, in: content, group: 1)
            return direct + from
        case .javascript, .javascriptReact, .typescript, .typescriptReact:
            let es6 = matchAll(
                pattern: #"^\s*import\s+.*?from\s+['"]([\w@/.\-]+)['"]"#, in: content, group: 1)
            let require = matchAll(
                pattern: #"require\(\s*['"]([\w@/.\-]+)['"]\s*\)"#, in: content, group: 1)
            return es6 + require
        case .go:
            // Single imports: import "fmt"
            let single = matchAll(pattern: #"^\s*import\s+"([\w/.\-]+)""#, in: content, group: 1)
            // Block imports: import ( "fmt" )
            let block = matchAll(pattern: #""\s*([\w/.\-]+)\s*""#, in: content, group: 1)
            return Array(Set(single + block))
        case .rust:
            return matchAll(pattern: #"^\s*use\s+([\w:]+)"#, in: content, group: 1)
        case .java, .kotlin:
            return matchAll(pattern: #"^\s*import\s+([\w.*]+)\s*;?"#, in: content, group: 1)
        case .ruby:
            let req = matchAll(
                pattern: #"^\s*require\s+['"]([\w/.\-]+)['"]"#, in: content, group: 1)
            let reqR = matchAll(
                pattern: #"^\s*require_relative\s+['"]([\w/.\-]+)['"]"#, in: content, group: 1)
            return req + reqR
        case .php:
            let use = matchAll(pattern: #"^\s*use\s+([\w\\]+)"#, in: content, group: 1)
            let req = matchAll(
                pattern: #"(?:require|include)(?:_once)?\s+['"]([\w/.\-]+)['"]"#, in: content,
                group: 1)
            return use + req
        case .csharp:
            return matchAll(pattern: #"^\s*using\s+([\w.]+)\s*;"#, in: content, group: 1)
        case .dart:
            return matchAll(pattern: #"^\s*import\s+['"]([\w:./\-]+)['"]"#, in: content, group: 1)
        case .elixir:
            let imp = matchAll(
                pattern: #"^\s*(?:import|alias|use|require)\s+([\w.]+)"#, in: content, group: 1)
            return imp
        case .scala:
            return matchAll(pattern: #"^\s*import\s+([\w._{}]+)"#, in: content, group: 1)
        case .haskell:
            return matchAll(
                pattern: #"^\s*import\s+(?:qualified\s+)?([\w.]+)"#, in: content, group: 1)
        case .zig:
            return matchAll(pattern: #"@import\(\s*"([\w./\-]+)"\s*\)"#, in: content, group: 1)
        default:
            return []
        }
    }

    // MARK: - Symbol Extraction (dispatch)

    static func extractSymbols(
        from content: String,
        lines: [String],
        filePath: String,
        language: FileLanguage
    ) -> [IndexedSymbol] {
        switch language {
        case .swift:
            return extractSwiftSymbols(from: content, lines: lines, filePath: filePath)
        case .python:
            return extractPythonSymbols(from: content, lines: lines, filePath: filePath)
        case .javascript, .javascriptReact:
            return extractJavaScriptSymbols(
                from: content, lines: lines, filePath: filePath, language: language)
        case .typescript, .typescriptReact:
            return extractTypeScriptSymbols(
                from: content, lines: lines, filePath: filePath, language: language)
        case .go:
            return extractGoSymbols(from: content, lines: lines, filePath: filePath)
        case .rust:
            return extractRustSymbols(from: content, lines: lines, filePath: filePath)
        case .java:
            return extractJavaSymbols(from: content, lines: lines, filePath: filePath)
        case .kotlin:
            return extractKotlinSymbols(from: content, lines: lines, filePath: filePath)
        case .ruby:
            return extractRubySymbols(from: content, lines: lines, filePath: filePath)
        case .php:
            return extractPHPSymbols(from: content, lines: lines, filePath: filePath)
        case .csharp:
            return extractCSharpSymbols(from: content, lines: lines, filePath: filePath)
        case .c, .cpp, .objectiveC, .objectiveCPP, .header:
            return extractCFamilySymbols(
                from: content, lines: lines, filePath: filePath, language: language)
        default:
            return []
        }
    }

    // MARK: - Swift

    private static func extractSwiftSymbols(
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

    private static func extractPythonSymbols(
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

    private static func extractJavaScriptSymbols(
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

    private static func extractTypeScriptSymbols(
        from content: String,
        lines: [String],
        filePath: String,
        language: FileLanguage
    ) -> [IndexedSymbol] {
        return extractJSTSSymbols(
            from: content, lines: lines, filePath: filePath, language: language, isTypeScript: true)
    }

    /// Shared JS/TS extractor
    private static func extractJSTSSymbols(
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

    // MARK: - Go

    private static func extractGoSymbols(
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

    // MARK: - Rust

    private static func extractRustSymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let structPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?struct\s+(\w+)"#
        let enumPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?enum\s+(\w+)"#
        let traitPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?trait\s+(\w+)"#
        let implPattern = #"^\s*impl(?:<[^>]+>)?\s+(?:(\w+)\s+for\s+)?(\w+)"#
        let funcPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(\w+)"#
        let constPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?(?:const|static)\s+(\w+)"#
        let typePattern = #"^\s*(?:pub(?:\(crate\))?\s+)?type\s+(\w+)"#
        let modPattern = #"^\s*(?:pub(?:\(crate\))?\s+)?mod\s+(\w+)"#

        var currentImpl: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
                || trimmed.hasPrefix("*")
            {
                continue
            }

            let isPub = trimmed.hasPrefix("pub")

            // Struct
            if let groups = matchGroupsFull(pattern: structPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .struct, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
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
                        signature: trimmed.prefix(200).description, language: .rust
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
                        endLine: endLine + 1, accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
                continue
            }

            // Impl block
            if let groups = matchGroupsFull(pattern: implPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                currentImpl = name
                let traitName = groups[safe: 1]
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                var inherits: [String] = []
                if let t = traitName, !t.isEmpty { inherits.append(t) }
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .extension, filePath: filePath, line: lineIndex + 1,
                        endLine: endLine + 1, accessLevel: .public,
                        signature: trimmed.prefix(200).description,
                        inherits: inherits, language: .rust
                    ))
                continue
            }

            // Function
            if let groups = matchGroupsFull(pattern: funcPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                let endLine = findBlockEnd(lines: lines, startLine: lineIndex)
                let isTest =
                    name.hasPrefix("test_")
                    || (lineIndex > 0 && lines[lineIndex - 1].contains("#[test]"))
                symbols.append(
                    IndexedSymbol(
                        name: name,
                        kind: isTest ? .test : (currentImpl != nil ? .method : .function),
                        filePath: filePath, line: lineIndex + 1, endLine: endLine + 1,
                        accessLevel: isPub ? .public : .private,
                        qualifiedName: currentImpl.map { "\($0).\(name)" },
                        containerName: currentImpl,
                        signature: trimmed.prefix(300).description,
                        documentation: extractDocComment(lines: lines, beforeLine: lineIndex),
                        language: .rust
                    ))
                continue
            }

            // Const/Static
            if let groups = matchGroupsFull(pattern: constPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .constant, filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
                continue
            }

            // Type alias
            if let groups = matchGroupsFull(pattern: typePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .typeAlias, filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
                continue
            }

            // Module
            if let groups = matchGroupsFull(pattern: modPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .module, filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPub ? .public : .private,
                        signature: trimmed.prefix(200).description, language: .rust
                    ))
            }
        }

        return symbols
    }

    // MARK: - Java

    private static func extractJavaSymbols(
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

    // MARK: - Kotlin

    private static func extractKotlinSymbols(
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

    // MARK: - Ruby

    private static func extractRubySymbols(
        from content: String,
        lines: [String],
        filePath: String
    ) -> [IndexedSymbol] {
        var symbols: [IndexedSymbol] = []

        let classPattern = #"^\s*class\s+(\w+)(?:\s*<\s*(\w+))?"#
        let modulePattern = #"^\s*module\s+(\w+)"#
        let defPattern = #"^\s*def\s+(self\.)?(\w+[?!=]?)"#
        let attrPattern = #"^\s*attr_(?:accessor|reader|writer)\s+:(\w+)"#
        let constPattern = #"^\s*(\w+)\s*=\s*"#

        var currentClass: String?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Class
            if let groups = matchGroupsFull(pattern: classPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                currentClass = name
                let parent = groups[safe: 2]
                var inherits: [String] = []
                if let p = parent, !p.isEmpty { inherits.append(p) }
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .class, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        inherits: inherits, language: .ruby
                    ))
                continue
            }

            // Module
            if let groups = matchGroupsFull(pattern: modulePattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .module, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: .ruby
                    ))
                continue
            }

            // Def
            if let groups = matchGroupsFull(pattern: defPattern, in: line),
                let name = groups[safe: 2], !name.isEmpty
            {
                let isSelf = groups[safe: 1] != nil && !(groups[safe: 1]!.isEmpty)
                let isPriv =
                    lineIndex > 0
                    && lines[lineIndex - 1].trimmingCharacters(in: .whitespaces) == "private"
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: currentClass != nil ? .method : .function,
                        filePath: filePath, line: lineIndex + 1,
                        accessLevel: isPriv ? .private : .public,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(300).description,
                        isStatic: isSelf, language: .ruby
                    ))
                continue
            }

            // Attr
            if let groups = matchGroupsFull(pattern: attrPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .property, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public,
                        qualifiedName: currentClass.map { "\($0).\(name)" },
                        containerName: currentClass,
                        signature: trimmed.prefix(200).description, language: .ruby
                    ))
                continue
            }

            // Top-level constant (UPPER_CASE = ...)
            if currentClass == nil, let groups = matchGroupsFull(pattern: constPattern, in: line),
                let name = groups[safe: 1], !name.isEmpty,
                name.first?.isUppercase == true
            {
                symbols.append(
                    IndexedSymbol(
                        name: name, kind: .constant, filePath: filePath, line: lineIndex + 1,
                        accessLevel: .public, signature: trimmed.prefix(200).description,
                        language: .ruby
                    ))
            }
        }

        return symbols
    }

    // MARK: - PHP

    private static func extractPHPSymbols(
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

    // MARK: - C#

    private static func extractCSharpSymbols(
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

    // MARK: - C / C++ / Obj-C

    private static func extractCFamilySymbols(
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

    // MARK: - Regex Helpers

    /// Returns first match of a pattern in a string
    static func firstMatch(pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return nil }
        return String(string[Range(match.range, in: string)!])
    }

    /// Returns all capture groups of first match
    static func matchGroups(pattern: String, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return [] }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: string) {
                groups.append(String(string[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    /// Returns all capture groups including group 0 (nil-safe)
    static func matchGroupsFull(pattern: String, in string: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return nil }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: string) {
                groups.append(String(string[r]))
            } else {
                groups.append("")
            }
        }
        return groups.isEmpty ? nil : groups
    }

    /// Returns all matches of group N across the string
    static func matchAll(pattern: String, in string: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        let matches = regex.matches(in: string, range: range)
        var results: [String] = []
        for match in matches {
            guard group < match.numberOfRanges else { continue }
            if let r = Range(match.range(at: group), in: string) {
                results.append(String(string[r]))
            }
        }
        return results
    }

    // MARK: - Block Finding

    /// Find the end of a brace-delimited block starting at a given line (C-style languages)
    static func findBlockEnd(lines: [String], startLine: Int) -> Int {
        var depth = 0
        var foundOpen = false
        for i in startLine..<lines.count {
            for ch in lines[i] {
                if ch == "{" {
                    depth += 1
                    foundOpen = true
                } else if ch == "}" {
                    depth -= 1
                    if foundOpen && depth == 0 {
                        return i
                    }
                }
            }
            // If we went past 2000 lines without closing, bail
            if i - startLine > 2000 { return startLine }
        }
        return startLine
    }

    /// Find the end of a Python-style indentation block
    static func findPythonBlockEnd(lines: [String], startLine: Int, startIndent: Int) -> Int {
        for i in (startLine + 1)..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            if indent <= startIndent {
                return max(startLine, i - 1)
            }
        }
        return max(startLine, lines.count - 1)
    }

    // MARK: - Doc Comments

    /// Extract doc comment (/// or /** */) immediately before a line
    static func extractDocComment(lines: [String], beforeLine: Int) -> String? {
        var docLines: [String] = []
        var i = beforeLine - 1
        while i >= 0 {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") {
                let comment = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                docLines.insert(comment, at: 0)
            } else if trimmed.hasPrefix("//") {
                let comment = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                docLines.insert(comment, at: 0)
            } else if trimmed.hasPrefix("*") || trimmed.hasPrefix("/**") || trimmed == "*/" {
                let comment =
                    trimmed
                    .replacingOccurrences(of: "/**", with: "")
                    .replacingOccurrences(of: "*/", with: "")
                    .replacingOccurrences(of: "* ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !comment.isEmpty {
                    docLines.insert(comment, at: 0)
                }
            } else {
                break
            }
            i -= 1
        }
        let result = docLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : String(result.prefix(500))
    }

    /// Extract Python docstring (triple-quoted string after def/class line)
    static func extractPythonDocstring(lines: [String], afterLine: Int) -> String? {
        let nextIdx = afterLine + 1
        guard nextIdx < lines.count else { return nil }
        let trimmed = lines[nextIdx].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\"\"\"") || trimmed.hasPrefix("'''") else { return nil }
        let quote = trimmed.hasPrefix("\"\"\"") ? "\"\"\"" : "'''"
        // Single-line docstring
        if trimmed.hasSuffix(quote) && trimmed.count > 6 {
            let inner = trimmed.dropFirst(3).dropLast(3)
            return String(inner).trimmingCharacters(in: .whitespaces)
        }
        // Multi-line docstring
        var docLines: [String] = []
        let firstContent = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        if !firstContent.isEmpty { docLines.append(firstContent) }
        for j in (nextIdx + 1)..<min(lines.count, nextIdx + 20) {
            let line = lines[j].trimmingCharacters(in: .whitespaces)
            if line.contains(quote) {
                let before = line.components(separatedBy: quote).first ?? ""
                if !before.trimmingCharacters(in: .whitespaces).isEmpty {
                    docLines.append(before.trimmingCharacters(in: .whitespaces))
                }
                break
            }
            docLines.append(line)
        }
        let result = docLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : String(result.prefix(500))
    }

    // MARK: - Swift-specific helpers

    /// Extract inheritance/conformance from Swift type declaration
    static func extractSwiftInheritance(from line: String, afterName name: String) -> [String] {
        // Look for ": SomeType, SomeProtocol" after the name
        guard
            let nameRange = line.range(of: name),
            let colonRange = line.range(
                of: ":", range: nameRange.upperBound..<line.endIndex)
        else {
            return []
        }
        let afterColon = String(line[colonRange.upperBound...])
        let beforeBrace = afterColon.components(separatedBy: "{").first ?? afterColon
        let beforeWhere = beforeBrace.components(separatedBy: "where").first ?? beforeBrace
        return
            beforeWhere
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.first?.isLetter == true }
    }

    /// Extract generic parameters (<T, U>) from a declaration line
    static func extractGenericParams(from line: String) -> [String] {
        guard let openIdx = line.firstIndex(of: "<") else { return [] }
        var depth = 0
        var end = openIdx
        for i in line[openIdx...].indices {
            if line[i] == "<" {
                depth += 1
            } else if line[i] == ">" {
                depth -= 1
                if depth == 0 {
                    end = i
                    break
                }
            }
        }
        guard end > openIdx else { return [] }
        let inner = String(line[line.index(after: openIdx)..<end])
        return inner.components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ":")
                    .first ?? ""
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Extract Swift annotations (@MainActor, @Sendable, etc.)
    static func extractAnnotations(from line: String) -> [String] {
        let pattern = #"@(\w+(?:\([^)]*\))?)"#
        return matchAll(pattern: pattern, in: line, group: 0)
    }

    // MARK: - Access Level Parsing

    static func parseAccessLevel(from groups: [String]) -> AccessLevel {
        for g in groups {
            switch g {
            case "open": return .open
            case "public": return .public
            case "internal": return .internal
            case "fileprivate": return .fileprivate
            case "private": return .private
            default: continue
            }
        }
        return .internal
    }

    static func parseJavaAccess(_ raw: String?) -> AccessLevel {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return .internal
        }
        switch raw {
        case "public": return .public
        case "protected": return .fileprivate
        case "private": return .private
        default: return .internal
        }
    }

    static func parseCSharpAccess(_ raw: String?) -> AccessLevel {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return .internal
        }
        switch raw {
        case "public": return .public
        case "protected": return .fileprivate
        case "private": return .private
        case "internal": return .internal
        default: return .internal
        }
    }

    // MARK: - Hashing

    /// FNV-1a hash for fast content change detection
    static func fnv1aHash(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
