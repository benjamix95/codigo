import XCTest
@testable import CoderEngine

final class ToolSchemaCatalogProviderExportTests: XCTestCase {
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
