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
}
