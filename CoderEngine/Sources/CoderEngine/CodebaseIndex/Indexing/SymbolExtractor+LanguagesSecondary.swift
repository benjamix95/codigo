import Foundation

extension SymbolExtractor {
    // MARK: - Go

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

    // MARK: - Rust

    static func extractRustSymbols(
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

    // MARK: - Ruby

    static func extractRubySymbols(
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

    static func extractPHPSymbols(
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
