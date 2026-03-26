import Foundation
import XCTest
@testable import CoderIDE

final class ChatStreamFailureHandlingTests: XCTestCase {
    func testInlinePolicyAckHashesExtractOrderedUniqueHashes() {
        let content = """
        [CODERIDE:policy_ack|hash=abc123]
        Analisi in corso.
        [CODERIDE:policy_ack|hash=abc123]
        [CODERIDE:policy_ack|hash=def456|status=ok]
        """

        XCTAssertEqual(inlinePolicyAckHashes(in: content), ["abc123", "def456"])
    }

    func testInlinePolicyAckHashesIgnoreMalformedMarkers() {
        let content = """
        [CODERIDE:policy_ack]
        [CODERIDE:policy_ack|hash=]
        [CODERIDE:policy_ack|title=missing]
        """

        XCTAssertTrue(inlinePolicyAckHashes(in: content).isEmpty)
    }

    func testPolicyAckDispositionTreatsMissingStatusAsIgnored() {
        XCTAssertEqual(policyAckDisposition(status: nil), .ignored)
        XCTAssertEqual(policyAckDisposition(status: ""), .ignored)
    }

    func testPolicyAckDispositionTreatsAcknowledgedAndInvalidStatusesExplicitly() {
        XCTAssertEqual(policyAckDisposition(status: "acknowledged"), .acknowledged)
        XCTAssertEqual(policyAckDisposition(status: "invalid"), .invalid)
    }

    func testInlinePolicyAckHashesForStreamingUpdateCombinesPartialDeltaMarkers() {
        let existingContent = "[CODERIDE:policy_ack|ha"
        let incomingContent = "sh=abc123]\nTodo"

        XCTAssertEqual(
            inlinePolicyAckHashesForStreamingUpdate(
                existingContent: existingContent,
                incomingContent: incomingContent,
                isReplacement: false
            ),
            ["abc123"]
        )
    }

    func testCoderideDisplayLineFilterRemovesPolicyErrorAndCoderideLines() {
        let content = """
        A
        [Policy error] Emit before starting real execution.
        B
        Thinking · [CODERIDE:policy_ack|hash=ab
        """
        let out = CoderideDisplayLineFilter.stripDisplayLinesWithCoderideToolPrefix(content)
        XCTAssertTrue(out.contains("A"))
        XCTAssertTrue(out.contains("B"))
        XCTAssertNil(out.range(of: "policy error", options: .caseInsensitive))
        XCTAssertFalse(out.contains("CODERIDE"))
    }

    func testInlineTodoWritePayloadsForStreamingUpdateExtractsNewlyClosedMarker() {
        let payloads = inlineTodoWritePayloadsForStreamingUpdate(
            existingContent: "[CODERIDE:todo_write|title=Run",
            incomingContent: " tests|status=in_progress]",
            isReplacement: false
        )

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?["title"], "Run tests")
        XCTAssertEqual(payloads.first?["status"], "in_progress")
    }

    func testPipelineSwarmPayloadCarriesStableSwarmMetadata() {
        let payload = pipelineSwarmPayload(
            taskId: "task_chat_0",
            agentName: "Explorer",
            status: "started"
        )

        XCTAssertEqual(payload["swarm_id"], "task_chat_0")
        XCTAssertEqual(payload["group_id"], "swarm-task_chat_0")
        XCTAssertEqual(payload["agent_name"], "Explorer")
        XCTAssertEqual(payload["status"], "started")
    }

    func testShouldPreservePartialAssistantContentForProviderErrors() {
        let error = ConversationFlowCoordinator.StreamExecutionError.providerError("boom")

        XCTAssertTrue(shouldPreservePartialAssistantContent(after: error))
    }

    func testShouldNotPreservePartialAssistantContentForGenericErrors() {
        let error = NSError(domain: "Test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "generic",
        ])

        XCTAssertFalse(shouldPreservePartialAssistantContent(after: error))
    }

    func testShouldDiscardPendingStreamSnapshotWhenConversationMatches() {
        let conversationId = UUID()

        XCTAssertTrue(
            shouldDiscardPendingStreamSnapshot(
                targetConversationId: conversationId,
                pendingConversationId: conversationId
            )
        )
    }

    func testShouldKeepPendingStreamSnapshotForOtherConversation() {
        XCTAssertFalse(
            shouldDiscardPendingStreamSnapshot(
                targetConversationId: UUID(),
                pendingConversationId: UUID()
            )
        )
    }

    @MainActor
    func testPromotedAssistantUpdateContentUsesIncomingWhenCurrentIsEmpty() {
        XCTAssertEqual(
            promotedAssistantUpdateContent(
                currentVisibleText: "",
                incomingRawOutput: "Sto leggendo i file rilevanti."
            ),
            "Sto leggendo i file rilevanti."
        )
    }

    @MainActor
    func testPromotedAssistantUpdateContentIgnoresStaleSubset() {
        XCTAssertNil(
            promotedAssistantUpdateContent(
                currentVisibleText: "Sto leggendo i file rilevanti e preparo la risposta.",
                incomingRawOutput: "Sto leggendo i file rilevanti."
            )
        )
    }

    @MainActor
    func testPromotedAssistantUpdateContentPromotesExtendedUpdate() {
        XCTAssertEqual(
            promotedAssistantUpdateContent(
                currentVisibleText: "Sto leggendo i file rilevanti.",
                incomingRawOutput: "Sto leggendo i file rilevanti e preparo la risposta."
            ),
            "Sto leggendo i file rilevanti e preparo la risposta."
        )
    }

    func testPolicyAckPayloadFromDirectPolicyAckEventPassesThrough() {
        let payload = policyAckPayloadFromEvent(
            type: "policy_ack",
            payload: ["hash": "abc123", "detail": "ok"]
        )

        XCTAssertEqual(payload?["hash"], "abc123")
        XCTAssertEqual(payload?["detail"], "ok")
    }

    func testPolicyAckPayloadFromMCPPolicyAckToolCallExtractsHash() {
        let payload = policyAckPayloadFromEvent(
            type: "mcp_tool_call",
            payload: [
                "mcp_tool": "coderide_policy_ack",
                "hash": "abc123",
            ]
        )

        XCTAssertEqual(payload?["hash"], "abc123")
    }

    func testPolicyAckPayloadFromNonPolicyMCPToolCallReturnsNil() {
        XCTAssertNil(
            policyAckPayloadFromEvent(
                type: "mcp_tool_call",
                payload: [
                    "mcp_tool": "coderide_read",
                    "hash": "abc123",
                ]
            )
        )
    }

    func testShouldRouteStreamingTextToReasoningBeforeOperationalActivity() {
        // Agent mode routes text to reasoning (for Codex-like providers)
        XCTAssertTrue(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: false
            )
        )
        // Agent mode still routes to reasoning even after operational activity
        // (only Claude CLI is exempt because it has separate thinking blocks)
        XCTAssertTrue(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: true
            )
        )
        // IDE mode never routes to reasoning
        XCTAssertFalse(
            shouldRouteStreamingTextToReasoning(
                coderMode: .ide,
                hasOperationalActivityInTurn: false
            )
        )
        // Claude CLI never routes text to reasoning (has separate thinking blocks)
        XCTAssertFalse(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: false,
                providerId: "claude-cli"
            )
        )
    }
}
