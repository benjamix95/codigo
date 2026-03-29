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
            "audit_security_secrets", "audit_security_dependencies", "audit_security_patterns",
            "audit_security_dataflow", "audit_security_authz", "audit_security_crypto",
            "audit_security_deserialization", "audit_security_surface", "audit_security_supply_chain",
            "audit_bug_diff_risks", "audit_bug_test_gaps", "audit_bug_hotspots",
            "audit_bug_nil_crash_paths", "audit_bug_state_machine", "audit_bug_concurrency",
            "audit_bug_error_handling", "audit_bug_api_contracts", "audit_bug_test_impact",
            "audit_bug_dependency_drift", "audit_bug_diff_semantics",
            "audit_perf_bottlenecks", "audit_perf_memory", "audit_perf_ui_responsiveness",
            "audit_perf_startup", "audit_perf_hot_paths", "audit_perf_correlate", "audit_perf_trending",
            "audit_run_profile", "audit_correlate_findings", "audit_verify_bundle", "audit_explain_finding",
            "benchmark_indexing", "benchmark_review_pipeline", "benchmark_semantic_search",
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

    func testCatalogIncludesNativeMacOSAutomationTools() throws {
        func entry(_ name: String) -> ToolSchemaEntry? {
            ToolSchemaCatalog.entries.first(where: { $0.name == name })
        }

        let focus = try XCTUnwrap(entry("macos_focus_app"))
        XCTAssertNotNil(focus.properties["app_name"])
        XCTAssertNotNil(focus.properties["bundle_id"])
        XCTAssertTrue(focus.required.isEmpty)

        let screenshot = try XCTUnwrap(entry("macos_capture_screenshot"))
        XCTAssertNotNil(screenshot.properties["target"])
        XCTAssertNotNil(screenshot.properties["app_name"])
        XCTAssertNotNil(screenshot.properties["bundle_id"])

        let applescript = try XCTUnwrap(entry("macos_run_applescript"))
        XCTAssertTrue(applescript.required.contains("script"))
        XCTAssertNotNil(applescript.properties["timeout_ms"])

        let click = try XCTUnwrap(entry("macos_click"))
        XCTAssertEqual(Set(click.required), Set(["x", "y"]))

        let pressKey = try XCTUnwrap(entry("macos_press_key"))
        XCTAssertEqual(pressKey.required, ["key"])
        XCTAssertNotNil(pressKey.properties["modifiers"])

        let typeText = try XCTUnwrap(entry("macos_type_text"))
        XCTAssertEqual(typeText.required, ["text"])

        let uiElements = try XCTUnwrap(entry("macos_list_ui_elements"))
        XCTAssertNotNil(uiElements.properties["scope"])
        XCTAssertNotNil(uiElements.properties["limit"])
    }

    func testDebugCleanSchemaMentionsVariablesType() throws {
        let debugClean = try XCTUnwrap(ToolSchemaCatalog.entries.first(where: { $0.name == "debug_clean" }))
        let typeDescription = (debugClean.properties["type"]?["description"] as? String) ?? ""
        XCTAssertTrue(typeDescription.contains("variables"))
    }

    func testRunProfileSchemaMentionsPerformanceProfiles() throws {
        let runProfile = try XCTUnwrap(ToolSchemaCatalog.entries.first(where: { $0.name == "audit_run_profile" }))
        let profileDescription = (runProfile.properties["profile"]?["description"] as? String) ?? ""

        XCTAssertTrue(profileDescription.contains("performance_deep"))
        XCTAssertTrue(profileDescription.contains("performance_extended"))
        XCTAssertTrue(profileDescription.contains("performance_full"))
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
            "subagent_bugHunter",
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
        XCTAssertTrue(names.contains("subagent_bugHunter"))
        XCTAssertTrue(names.contains("subagent_testWriter"))
        XCTAssertTrue(names.contains("subagent_securityAuditor"))
    }
}
