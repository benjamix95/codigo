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
            "mcp_call", "web_search", "web_fetch"
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
        XCTAssertTrue(findSymbol.required.contains("query"))

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

    func testDebugCleanSchemaMentionsVariablesType() throws {
        let debugClean = try XCTUnwrap(ToolSchemaCatalog.entries.first(where: { $0.name == "debug_clean" }))
        let typeDescription = (debugClean.properties["type"]?["description"] as? String) ?? ""
        XCTAssertTrue(typeDescription.contains("variables"))
    }

    func testNativeRegistryEnumSerializationPreservesArrayValues() throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let descriptor = MCPToolDescriptor(
            name: "enum_tool",
            description: "Enum test",
            schema: #"{"type":"object","properties":{"mode":{"type":"string","enum":["fast","safe"]}}}"#,
            serverId: "enum-server",
            serverName: "enum"
        )

        XCTAssertTrue(registry.register(tools: [descriptor]))
        let registered = try XCTUnwrap(registry.entries.first)
        let enumValues = registered.properties["mode"]?["enum"] as? [String]
        XCTAssertEqual(enumValues, ["fast", "safe"])
    }

    func testOpenAISchemaIncludesPlanAndSwarmTools() {
        let names: Set<String> = Set(
            ToolSchemaCatalog.openAIFunctionTools.compactMap { item in
                guard let function = item["function"] as? [String: Any] else { return nil }
                return function["name"] as? String
            }
        )

        let required: [String] = [
            "todo_write",
            "todo_read",
            "plan_step_update",
            "plan_create",
            "plan_read",
            "plan_step_upsert",
            "plan_step_batch_update",
            "plan_step_reorder",
            "plan_step_dependency_set",
            "plan_set_walkthrough",
            "plan_history_read",
            "plan_diff",
            "plan_request_user_input",
            "mermaid_render",
            "policy_ack",
            "activate_plan_mode",
            "activate_debug_mode",
            "show_task_panel",
            "show_swarm_panel",
            "subagent_explorer",
            "subagent_coder",
            "subagent_debugger",
            "subagent_reviewer",
            "subagent_testWriter",
            "subagent_docWriter",
            "subagent_securityAuditor",
        ]

        for tool in required {
            XCTAssertTrue(names.contains(tool), "Missing function tool: \(tool)")
        }
    }

    func testAnthropicSchemaIncludesSubagentTools() {
        let names = Set(ToolSchemaCatalog.anthropicTools.compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("subagent_explorer"))
        XCTAssertTrue(names.contains("subagent_coder"))
        XCTAssertTrue(names.contains("subagent_testWriter"))
        XCTAssertTrue(names.contains("subagent_securityAuditor"))
    }

    func testNativeRegistryResolvesNameCollisionsDeterministically() {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let schema = #"{"type":"object","properties":{}}"#
        let descriptorA = MCPToolDescriptor(
            name: "very_long_tool_name_for_collision_checks_and_stability",
            description: "A",
            schema: schema,
            serverId: "srv-a",
            serverName: "shared-server-name"
        )
        let descriptorB = MCPToolDescriptor(
            name: "very_long_tool_name_for_collision_checks_and_stability",
            description: "B",
            schema: schema,
            serverId: "srv-b",
            serverName: "shared-server-name"
        )

        let changedFirst = registry.register(tools: [descriptorB, descriptorA])
        XCTAssertTrue(changedFirst)
        let firstNames = registry.entries.map(\.name)
        XCTAssertEqual(firstNames.count, 2)
        XCTAssertEqual(Set(firstNames).count, 2, "Registry should avoid function-name collisions")

        let firstSnapshot = registry.routing
            .map { "\($0.key)=\($0.value.serverId)/\($0.value.toolName)" }
            .sorted()

        let changedSecond = registry.register(tools: [descriptorA, descriptorB])
        XCTAssertFalse(changedSecond, "Same discovered toolset should not trigger a rebuild")

        let secondSnapshot = registry.routing
            .map { "\($0.key)=\($0.value.serverId)/\($0.value.toolName)" }
            .sorted()
        XCTAssertEqual(firstSnapshot, secondSnapshot)
    }

    func testNativeRegistryRegisterEmptyClearsEntries() {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let descriptor = MCPToolDescriptor(
            name: "sample_tool",
            description: "sample",
            schema: #"{"type":"object","properties":{}}"#,
            serverId: "srv-1",
            serverName: "srv"
        )

        XCTAssertTrue(registry.register(tools: [descriptor]))
        XCTAssertTrue(registry.hasTools())

        XCTAssertTrue(registry.register(tools: []))
        XCTAssertFalse(registry.hasTools())
    }
}
