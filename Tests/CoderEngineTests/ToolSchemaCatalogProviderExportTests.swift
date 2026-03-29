import XCTest
@testable import CoderEngine

final class ToolSchemaCatalogProviderExportTests: XCTestCase {
    private let runtimePreferredIDEStateToolNames: Set<String> = [
        "policy_ack",
        "activate_debug_mode",
        "activate_plan_mode",
        "debug_set_phase",
        "debug_request_user",
        "debug_resolve",
        "show_task_panel",
        "show_swarm_panel",
    ]

    func testProviderExportsAllPreferredCanonicalNamesWhenNativeRegistryIsWarm() throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let canonical = CoderIDECanonicalToolRegistry.shared.allRecords.filter {
            CoderIDECanonicalToolRegistry.shared.isUsable(
                CoderIDECanonicalToolRegistry.shared.availability(for: $0, on: .providers)
            )
        }
        let descriptors = canonical.map { record in
            MCPToolDescriptor(
                name: record.mcpName,
                description: record.description,
                schema: #"{"type":"object","properties":{}}"#,
                serverId: "coderide-server",
                serverName: "coderide"
            )
        }

        XCTAssertTrue(registry.mergeRegister(tools: descriptors))

        let openAI = Set(ToolSchemaCatalog.openAIFunctionTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any] else { return nil }
            return function["name"] as? String
        })
        let anthropic = Set(ToolSchemaCatalog.anthropicTools.compactMap { $0["name"] as? String })

        for record in canonical {
            let expectedName = runtimePreferredIDEStateToolNames.contains(record.runtimeName)
                ? record.runtimeName
                : record.mcpName
            XCTAssertTrue(openAI.contains(expectedName), "OpenAI exports should contain preferred canonical name \(expectedName)")
            XCTAssertTrue(anthropic.contains(expectedName), "Anthropic exports should contain preferred canonical name \(expectedName)")
        }
    }

    func testProviderExportsPreferCoderideMCPAliasForWorkspaceTools() throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let descriptor = MCPToolDescriptor(
            name: "coderide_read",
            description: "read file via coderide",
            schema: #"{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}"#,
            serverId: "coderide-server",
            serverName: "coderide"
        )

        XCTAssertTrue(registry.register(tools: [descriptor]))

        let openAI = Set(ToolSchemaCatalog.openAIFunctionTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any] else { return nil }
            return function["name"] as? String
        })
        let anthropic = Set(ToolSchemaCatalog.anthropicTools.compactMap { $0["name"] as? String })

        XCTAssertTrue(openAI.contains("coderide_read"))
        XCTAssertFalse(openAI.contains("read"))
        XCTAssertTrue(anthropic.contains("coderide_read"))
        XCTAssertFalse(anthropic.contains("read"))
    }

    func testProviderExportsKeepRuntimeIDEStateToolsEvenWhenMCPAliasExists() throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let descriptor = MCPToolDescriptor(
            name: "coderide_policy_ack",
            description: "policy ack via coderide",
            schema: #"{\"type\":\"object\",\"properties\":{\"hash\":{\"type\":\"string\"}},\"required\":[\"hash\"]}"#,
            serverId: "coderide-server",
            serverName: "coderide"
        )

        XCTAssertTrue(registry.register(tools: [descriptor]))

        let openAI = Set(ToolSchemaCatalog.openAIFunctionTools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any] else { return nil }
            return function["name"] as? String
        })
        let anthropic = Set(ToolSchemaCatalog.anthropicTools.compactMap { $0["name"] as? String })

        XCTAssertTrue(openAI.contains("policy_ack"))
        XCTAssertFalse(openAI.contains("coderide_policy_ack"))
        XCTAssertTrue(anthropic.contains("policy_ack"))
        XCTAssertFalse(anthropic.contains("coderide_policy_ack"))
    }
}
