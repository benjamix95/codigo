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
}
