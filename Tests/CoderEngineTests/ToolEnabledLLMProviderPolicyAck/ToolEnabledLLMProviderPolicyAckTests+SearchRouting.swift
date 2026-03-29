import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
    func testQueryOnlyNaturalLanguageDefaultsToSemanticSearch() {
        let provider = ToolEnabledLLMProvider(base: TextOnlyProvider(), maxToolRounds: 1)

        let inferred = provider.inferredToolName(from: [
            "query": "where is authentication handled",
        ])

        XCTAssertEqual(inferred, "semantic_search")
    }

    func testScopedNaturalLanguageQueryStillUsesSemanticSearch() {
        let provider = ToolEnabledLLMProvider(base: TextOnlyProvider(), maxToolRounds: 1)

        let inferred = provider.inferredToolName(from: [
            "query": "error handling flow",
            "pathScope": "Engine/CoderEngine/Sources",
        ])

        XCTAssertEqual(inferred, "semantic_search")
    }

    func testScopedExactPatternKeepsGrepRouting() {
        let provider = ToolEnabledLLMProvider(base: TextOnlyProvider(), maxToolRounds: 1)

        let inferred = provider.inferredToolName(from: [
            "query": "AuthManager",
            "pathScope": "Engine/CoderEngine/Sources",
            "fileType": "swift",
        ])

        XCTAssertEqual(inferred, "grep")
    }

    func testWebSearchPayloadKeepsWebRoutingWhenExplicitHintsExist() {
        let provider = ToolEnabledLLMProvider(base: TextOnlyProvider(), maxToolRounds: 1)

        let inferred = provider.inferredToolName(from: [
            "query": "latest Swift release notes",
            "explanation": "Need web results",
        ])

        XCTAssertEqual(inferred, "web_search")
    }

    func testNaturalLanguageGrepSuggestionIsForcedToSemanticSearch() {
        let provider = ToolEnabledLLMProvider(base: TextOnlyProvider(), maxToolRounds: 1)
        let marker = CoderIDEMarker(kind: "tool_call", payload: [
            "id": "sem-force-1",
            "name": "grep",
            "query": "where is authentication handled",
            "pathScope": "Engine/CoderEngine/Sources",
        ])

        let enforced = provider.enforcedWorkspaceSearchMarker(marker: marker, toolName: "grep")

        XCTAssertEqual(enforced.toolName, "semantic_search")
        XCTAssertEqual(enforced.marker.payload["tool"], "semantic_search")
    }

    func testNaturalLanguageMCPGrepSuggestionIsForcedToSemanticMCPTool() {
        let provider = ToolEnabledLLMProvider(base: TextOnlyProvider(), maxToolRounds: 1)
        let marker = CoderIDEMarker(kind: "tool_call", payload: [
            "id": "sem-force-2",
            "name": "mcp_call",
            "mcp_tool": "coderide_grep",
            "tool": "coderide_grep",
            "query": "where is authentication handled",
            "pathScope": "Engine/CoderEngine/Sources",
        ])

        let enforced = provider.enforcedWorkspaceSearchMarker(marker: marker, toolName: "mcp_call")

        XCTAssertEqual(enforced.toolName, "mcp_call")
        XCTAssertEqual(enforced.marker.payload["mcp_tool"], "coderide_semantic_search")
        XCTAssertEqual(enforced.marker.payload["tool"], "coderide_semantic_search")
    }
}
