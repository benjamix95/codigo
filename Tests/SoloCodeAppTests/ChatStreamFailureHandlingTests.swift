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
