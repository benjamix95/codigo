import XCTest
@testable import CoderEngine

final class ToolSchemaCatalogTests: XCTestCase {
    func testOpenAIAndAnthropicExposeSameToolNames() {
        let openAI = Set(ToolSchemaCatalog.openAIFunctionTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any] else { return nil }
            return function["name"] as? String
        })
        let anthropic = Set(ToolSchemaCatalog.anthropicTools.compactMap { tool -> String? in
            tool["name"] as? String
        })

        XCTAssertEqual(openAI, anthropic)
    }

    func testCatalogIncludesRequiredRuntimeTools() {
        let names = Set(ToolSchemaCatalog.entries.map(\.name))
        let required: Set<String> = [
            "semantic_search", "read_lints", "debug_context",
            "codebase_search", "find_symbol", "list_symbols", "find_references",
            "index_status", "reindex",
            "parallel_apply", "regex_replace", "rename_symbol", "find_and_replace_all", "undo_edit",
            "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean",
            "mcp", "mcp_call", "web_search", "web_fetch"
        ]

        let missing = required.subtracting(names)
        XCTAssertTrue(missing.isEmpty, "Missing tools in catalog: \(missing.sorted())")
    }

    func testSchemasExposeMCPAliases() throws {
        func entry(_ name: String) -> ToolSchemaEntry? {
            ToolSchemaCatalog.entries.first(where: { $0.name == name })
        }

        let grep = try XCTUnwrap(entry("grep"))
        XCTAssertNotNil(grep.properties["pattern"])
        XCTAssertNotNil(grep.properties["path"])
        XCTAssertFalse(grep.required.contains("query"))

        let readRange = try XCTUnwrap(entry("read_range"))
        XCTAssertNotNil(readRange.properties["start_line"])
        XCTAssertNotNil(readRange.properties["end_line"])
        XCTAssertEqual(readRange.required, ["path"])

        let findSymbol = try XCTUnwrap(entry("find_symbol"))
        XCTAssertNotNil(findSymbol.properties["name"])
        XCTAssertFalse(findSymbol.required.contains("query"))

        let findReferences = try XCTUnwrap(entry("find_references"))
        XCTAssertNotNil(findReferences.properties["name"])
        XCTAssertFalse(findReferences.required.contains("query"))

        let findFiles = try XCTUnwrap(entry("find_files"))
        XCTAssertNotNil(findFiles.properties["pattern"])
        XCTAssertNotNil(findFiles.properties["path"])
        XCTAssertNotNil(findFiles.properties["filePattern"])
        XCTAssertFalse(findFiles.required.contains("query"))

        let codebaseSearch = try XCTUnwrap(entry("codebase_search"))
        XCTAssertNotNil(codebaseSearch.properties["path"])
    }
}
