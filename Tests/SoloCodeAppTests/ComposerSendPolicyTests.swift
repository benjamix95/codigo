import XCTest
@testable import CoderIDE

final class ComposerSendPolicyTests: XCTestCase {
    func testDispatchRouteUsesTransparentFollowUpWhileTaskIsRunning() {
        XCTAssertEqual(
            resolveComposerSendDispatchRoute(
                trimmedInput: "aggiungi anche i test",
                selectedProviderId: "codex-cli",
                isLoadingCurrentConversation: true
            ),
            .interruptAndSendFollowUp
        )
    }

    func testDispatchRouteKeepsFastToggleWhenRequested() {
        XCTAssertEqual(
            resolveComposerSendDispatchRoute(
                trimmedInput: "/fast",
                selectedProviderId: "codex-cli",
                isLoadingCurrentConversation: true
            ),
            .fastModeToggle
        )
    }

    func testDispatchRouteUsesStandardSendWhenConversationIsIdle() {
        XCTAssertEqual(
            resolveComposerSendDispatchRoute(
                trimmedInput: "procedi",
                selectedProviderId: "codex-cli",
                isLoadingCurrentConversation: false
            ),
            .standardSend
        )
    }

    func testShouldSubmitComposerDraftBlocksPlanChoicePhase() {
        XCTAssertFalse(
            shouldSubmitComposerDraft(
                hasDraftContent: true,
                planningState: .awaitingChoice(
                    planContent: "Plan",
                    options: []
                )
            )
        )
    }

    func testCanComposerDispatchMessageAllowsDraftWhileTaskControlsAreVisible() {
        XCTAssertTrue(
            canComposerDispatchMessage(
                isProjectContextAvailable: true,
                hasDraftContent: true,
                planningState: .idle
            )
        )
    }

    func testCanComposerDispatchMessageStillRequiresProjectContext() {
        XCTAssertFalse(
            canComposerDispatchMessage(
                isProjectContextAvailable: false,
                hasDraftContent: true,
                planningState: .idle
            )
        )
    }
}
