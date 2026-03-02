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
        indexFileWithContent(absolutePath: absolutePath, relativePath: relativePath, language: language)?.file
    }

    /// Indicizza un file e restituisce anche il contenuto letto, per evitare doppio I/O
    /// quando il contenuto serve anche alla semantic indexing phase.
    public static func indexFileWithContent(
        absolutePath: String,
        relativePath: String,
        language: FileLanguage? = nil
    ) -> (file: IndexedFile, content: String)? {
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

        let indexed = IndexedFile(
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
        return (indexed, content)
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
}
