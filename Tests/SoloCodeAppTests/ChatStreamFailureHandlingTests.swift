import Foundation
import XCTest
@testable import CoderIDE

final class ChatStreamFailureHandlingTests: XCTestCase {
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
