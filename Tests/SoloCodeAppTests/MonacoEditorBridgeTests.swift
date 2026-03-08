import XCTest
@testable import CoderIDE

final class MonacoEditorBridgeTests: XCTestCase {
    func testBase64ContentEncoding() {
        let content = "print(\"Hello, World!\")"
        let b64 = content.data(using: .utf8)?.base64EncodedString() ?? ""
        let decoded = Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(decoded, content)
    }

    func testBase64EmptyContentEncoding() {
        let content = ""
        let b64 = content.data(using: .utf8)?.base64EncodedString() ?? ""
        let decoded = Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(decoded, content)
    }

    func testBase64UnicodeContentEncoding() {
        let content = "let emoji = \"🚀🎉\" // Unicode test"
        let b64 = content.data(using: .utf8)?.base64EncodedString() ?? ""
        let decoded = Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(decoded, content)
    }

    func testBase64MultilineContentEncoding() {
        let content = """
        func hello() {
            print("world")
        }
        """
        let b64 = content.data(using: .utf8)?.base64EncodedString() ?? ""
        let decoded = Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(decoded, content)
    }

    func testSafePathEscaping() {
        let path = "/Users/test/project/it's a file.swift"
        let safePath = path.replacingOccurrences(of: "'", with: "\\'")
        XCTAssertTrue(safePath.contains("\\'"))
        XCTAssertFalse(safePath.contains("it's"))
    }

    func testFileExtensionToLanguageMapping() {
        let mappings: [(ext: String, lang: String)] = [
            ("swift", "swift"),
            ("js", "javascript"),
            ("ts", "typescript"),
            ("py", "python"),
            ("json", "json"),
            ("html", "html"),
            ("css", "css"),
            ("md", "markdown"),
            ("rs", "rust"),
            ("go", "go"),
            ("sh", "shell"),
        ]
        for mapping in mappings {
            let lang = languageFromExtension(mapping.ext)
            XCTAssertEqual(lang, mapping.lang, "Extension '\(mapping.ext)' should map to '\(mapping.lang)' but got '\(lang)'")
        }
    }

    func testUnknownExtensionFallsBackToPlaintext() {
        XCTAssertEqual(languageFromExtension("xyz"), "plaintext")
        XCTAssertEqual(languageFromExtension(""), "plaintext")
    }

    private func languageFromExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "js", "mjs", "cjs": return "javascript"
        case "jsx": return "javascript"
        case "ts", "mts", "cts": return "typescript"
        case "tsx": return "typescript"
        case "py", "pyw": return "python"
        case "json": return "json"
        case "html", "htm": return "html"
        case "css": return "css"
        case "scss": return "scss"
        case "less": return "less"
        case "md", "markdown": return "markdown"
        case "rs": return "rust"
        case "go": return "go"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "cs": return "csharp"
        case "rb": return "ruby"
        case "php": return "php"
        case "sh", "bash", "zsh": return "shell"
        case "yml", "yaml": return "yaml"
        case "xml", "plist": return "xml"
        case "sql": return "sql"
        case "r": return "r"
        case "dart": return "dart"
        case "toml": return "toml"
        case "lua": return "lua"
        case "dockerfile": return "dockerfile"
        default: return "plaintext"
        }
    }
}
