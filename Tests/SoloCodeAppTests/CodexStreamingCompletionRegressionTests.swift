import XCTest
@testable import CoderIDE

final class CodexStreamingCompletionRegressionTests: XCTestCase {
    func testFinalActionsVisibleForCompletedStatusWhenStreamingFlagIsStale() {
        XCTAssertTrue(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: makeConversation(
                    status: "completed",
                    completedAt: Date(timeIntervalSince1970: 12)
                ),
                isLoadingForCurrentConversation: false
            )
        )
    }

    func testFinalActionsVisibleForFailedStatusWhenStreamingFlagIsStale() {
        XCTAssertTrue(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: makeConversation(
                    status: "failed",
                    completedAt: Date(timeIntervalSince1970: 12)
                ),
                isLoadingForCurrentConversation: false
            )
        )
    }

    func testFinalActionsVisibleForCancelledStatusWhenStreamingFlagIsStale() {
        XCTAssertTrue(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: makeConversation(
                    status: "cancelled",
                    completedAt: Date(timeIntervalSince1970: 12)
                ),
                isLoadingForCurrentConversation: false
            )
        )
    }

    func testFinalActionsStayHiddenForTrulyStreamingAssistantWithoutTerminalMetadata() {
        XCTAssertFalse(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: makeConversation(status: "streaming", completedAt: nil),
                isLoadingForCurrentConversation: false
            )
        )
    }

    func testToolTraceTurnOutcomeMapsCoordinatorTerminalStates() {
        XCTAssertEqual(toolTraceTurnOutcome(for: .idle), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .streaming), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .completed), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .error), .failed)
        XCTAssertEqual(toolTraceTurnOutcome(for: .interrupted), .aborted)
    }

    func testToolTraceTurnOutcomeMapsPipelineCompletionStates() {
        XCTAssertEqual(
            toolTraceTurnOutcome(pipelineSuccess: true, pipelineWasCancelled: false),
            .success
        )
        XCTAssertEqual(
            toolTraceTurnOutcome(pipelineSuccess: false, pipelineWasCancelled: true),
            .aborted
        )
        XCTAssertEqual(
            toolTraceTurnOutcome(pipelineSuccess: false, pipelineWasCancelled: false),
            .failed
        )
    }

    func testCodexReasoningPresentationModeStaysSuppressedForCodexAliases() {
        let providerIds = ["codex-cli", "codex", "codex-preview", "enterprise-codex"]

        for providerId in providerIds {
            XCTAssertEqual(
                ChatReasoningPresentationPolicy.mode(
                    providerId: providerId,
                    separateCodexThinkingMessagesEnabled: false
                ),
                .suppressed
            )
        }
    }

    func testSuppressedReasoningUsesFallbackProviderIdWhenMessageMetadataIsMissing() {
        XCTAssertTrue(
            ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
                messageProviderId: nil,
                fallbackTurnProviderId: "codex-cli"
            )
        )
        XCTAssertFalse(
            ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
                messageProviderId: nil,
                fallbackTurnProviderId: "claude-cli"
            )
        )
    }

    private func makeConversation(status: String, completedAt: Date?) -> Conversation {
        Conversation(
            title: "Thread",
            messages: [
                ChatMessage(
                    role: .assistant,
                    content: "Final answer",
                    turnMetadata: ChatTurnMetadata(
                        turnId: "turn-1",
                        providerId: "codex-cli",
                        sequence: 1,
                        status: status,
                        startedAt: Date(timeIntervalSince1970: 10),
                        completedAt: completedAt,
                        updatedAt: Date(timeIntervalSince1970: 12),
                        isStreaming: false
                    ),
                    isStreaming: true
                ),
            ]
        )
    }
}
