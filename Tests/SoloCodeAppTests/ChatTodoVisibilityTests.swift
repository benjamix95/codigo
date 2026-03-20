import XCTest
@testable import CoderIDE

final class ChatTodoVisibilityTests: XCTestCase {
    func testLiveTodoCardRemainsVisibleDuringPipelineProgress() {
        XCTAssertTrue(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: false,
                hasLiveSwarmCards: false,
                hasPipelineProgress: true
            )
        )
    }

    func testLiveTodoCardIsHiddenWhenSwarmAlreadyOwnsProgressUI() {
        XCTAssertFalse(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: true,
                hasLiveSwarmCards: false,
                hasPipelineProgress: false
            )
        )
        XCTAssertFalse(
            shouldShowLiveTodoCardInChat(
                hasSwarmSteps: false,
                hasLiveSwarmCards: true,
                hasPipelineProgress: false
            )
        )
    }

    func testTodoCardPrefersAssistantMessageWithTraceOverNewerAssistantStub() {
        let tracedAssistantId = UUID()
        let newerAssistantId = UUID()

        let resolved = resolveTodoCardAssistantMessageId(
            messages: [
                ChatMessage(id: tracedAssistantId, role: .assistant, content: "Main reply"),
                ChatMessage(id: newerAssistantId, role: .assistant, content: ""),
            ],
            activeAssistantMessageId: nil,
            latestAssistantMessageIdWithTrace: tracedAssistantId,
            pipelineAssistantMessageId: newerAssistantId,
            latestVisibleAssistantMessageId: newerAssistantId
        )

        XCTAssertEqual(resolved, tracedAssistantId)
    }

    func testTodoCardPrefersActiveAssistantMessageWhenPresent() {
        let activeAssistantId = UUID()
        let tracedAssistantId = UUID()

        let resolved = resolveTodoCardAssistantMessageId(
            messages: [
                ChatMessage(id: tracedAssistantId, role: .assistant, content: "Older reply"),
                ChatMessage(id: activeAssistantId, role: .assistant, content: ""),
            ],
            activeAssistantMessageId: activeAssistantId,
            latestAssistantMessageIdWithTrace: tracedAssistantId,
            pipelineAssistantMessageId: tracedAssistantId,
            latestVisibleAssistantMessageId: tracedAssistantId
        )

        XCTAssertEqual(resolved, activeAssistantId)
    }

    func testTodoCardFallsBackToLatestVisibleAssistantWhenPipelineTargetIsMissing() {
        let olderAssistantId = UUID()
        let latestAssistantId = UUID()

        let resolved = resolveTodoCardAssistantMessageId(
            messages: [
                ChatMessage(id: olderAssistantId, role: .assistant, content: "Older reply"),
                ChatMessage(id: latestAssistantId, role: .assistant, content: "Latest reply"),
            ],
            activeAssistantMessageId: nil,
            latestAssistantMessageIdWithTrace: nil,
            pipelineAssistantMessageId: nil,
            latestVisibleAssistantMessageId: latestAssistantId
        )

        XCTAssertEqual(resolved, latestAssistantId)
    }
}
