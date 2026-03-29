import Foundation
import XCTest
@testable import CoderIDE

@MainActor
final class CodexStreamingContentRegressionTests: XCTestCase {
    func testCodexIntermediateTurnsBucketIsPreservedOnlyForExplicitIntermediateGroup() {
        XCTAssertEqual(
            mainChatInlineReasoningGroupId(
                providerId: "codex-cli",
                payload: ["group_id": "codex-intermediate-turns"]
            ),
            "codex-intermediate-turns"
        )
    }

    func testCodexArbitraryReasoningGroupCollapsesBackToSingleReasoningStream() {
        XCTAssertEqual(
            mainChatInlineReasoningGroupId(
                providerId: "codex-cli",
                payload: ["group_id": "codex-thinking-42"]
            ),
            "reasoning-stream"
        )
    }

    func testPromotedAssistantUpdateContentStripsCoderideMarkersBeforePromotion() {
        let promoted = promotedAssistantUpdateContent(
            currentVisibleText: "",
            incomingRawOutput: "[CODERIDE:policy_ack|hash=abc123]\n\nSto leggendo i file rilevanti."
        )

        XCTAssertEqual(promoted, "Sto leggendo i file rilevanti.")
    }

    func testPromotedAssistantUpdateContentIgnoresEquivalentLooseBoundarySubset() {
        let promoted = promotedAssistantUpdateContent(
            currentVisibleText: "Sto leggendo i file rilevanti.",
            incomingRawOutput: "Sto leggendo i file rilevanti"
        )

        XCTAssertNil(promoted)
    }

    func testPromotedAssistantUpdateContentPromotesSupersetUpdate() {
        let promoted = promotedAssistantUpdateContent(
            currentVisibleText: "Sto leggendo i file rilevanti.",
            incomingRawOutput: "Sto leggendo i file rilevanti e preparo la risposta."
        )

        XCTAssertEqual(promoted, "Sto leggendo i file rilevanti e preparo la risposta.")
    }

    func testFinalAssistantContentExcludingReasoningDropsExactDuplicate() {
        XCTAssertEqual(
            finalAssistantContentExcludingReasoning(
                fullText: "Planning next move",
                reasoningText: "Planning next move"
            ),
            ""
        )
    }

    func testFinalAssistantContentExcludingReasoningReturnsTailAfterReasoningPrefix() {
        XCTAssertEqual(
            finalAssistantContentExcludingReasoning(
                fullText: "Planning next move\n\nFinal answer",
                reasoningText: "Planning next move"
            ),
            "Final answer"
        )
    }

    func testFinalAssistantContentExcludingReasoningKeepsUnrelatedAnswer() {
        XCTAssertEqual(
            finalAssistantContentExcludingReasoning(
                fullText: "Final answer",
                reasoningText: "Planning next move"
            ),
            "Final answer"
        )
    }

    func testReasoningMergeKeepsExistingWhenIncomingIsContainedSubset() {
        let merged = ChatStreamReasoningTextMerge.merge(
            existing: "Analizzo il file e poi preparo la patch.",
            incoming: "Analizzo il file"
        )

        XCTAssertEqual(merged, "Analizzo il file e poi preparo la patch.")
    }

    func testReasoningMergeUsesOverlapAcrossAdjacentChunks() {
        let merged = ChatStreamReasoningTextMerge.merge(
            existing: "alpha-beta",
            incoming: "beta-gamma"
        )

        XCTAssertEqual(merged, "alpha-beta-gamma")
    }

    func testShouldPreservePartialAssistantContentForProviderError() {
        let error = ConversationFlowCoordinator.StreamExecutionError.providerError("boom")
        XCTAssertTrue(shouldPreservePartialAssistantContent(after: error))
    }

    func testPendingStreamSnapshotPolicyRejectsNilConversationTarget() {
        XCTAssertTrue(
            shouldDiscardPendingStreamSnapshot(
                targetConversationId: nil,
                pendingConversationId: UUID()
            )
        )
    }
}
