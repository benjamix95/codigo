import AppKit
import XCTest
@testable import CoderIDE

extension PlanShortcutAndCommandTests {
                phase: .idle,
                activeBuildPlanConversationId: nil,
                activeBuildAgentConversationId: nil
            )
        )

        XCTAssertTrue(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: true,
                streamConversationId: activeBuildAgentConversationId,
                hasActivePlanContext: false,
                phase: .building,
                activeBuildPlanConversationId: activeBuildPlanConversationId,
                activeBuildAgentConversationId: activeBuildAgentConversationId
            )
        )

        XCTAssertTrue(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: false,
                streamConversationId: activeBuildAgentConversationId,
                hasActivePlanContext: false,
                phase: .building,
                activeBuildPlanConversationId: activeBuildPlanConversationId,
                activeBuildAgentConversationId: activeBuildAgentConversationId
            )
        )

        XCTAssertFalse(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: true,
                streamConversationId: streamConversationId,
                hasActivePlanContext: false,
                phase: .building,
                activeBuildPlanConversationId: activeBuildPlanConversationId,
                activeBuildAgentConversationId: activeBuildAgentConversationId
            )
        )
    }

    func testShouldClearPlanCanonicalTodosOnNewTurnPolicy() {
        XCTAssertTrue(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .idle,
                hasActivePlanBuildTask: false
            )
        )
        XCTAssertFalse(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .building,
                hasActivePlanBuildTask: false
            )
        )
        XCTAssertFalse(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .idle,
                hasActivePlanBuildTask: true
            )
        )
    }

    func testPreflightFailureResetPolicyAffectsOnlyInProgressPlanDiscoveryPhases() {
        XCTAssertTrue(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: true,
                phase: .analyzing
            )
        )
        XCTAssertTrue(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: true,
                phase: .questioning
            )
        )
        XCTAssertTrue(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: true,
                phase: .generating
            )
        )
        XCTAssertFalse(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: true,
                phase: .readyToBuild
            )
        )
        XCTAssertFalse(
            shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: false,
                phase: .analyzing
            )
        )
    }

    func testPlanToggleDeactivationPolicyBlocksOnlyInProgressPhases() {
        XCTAssertFalse(shouldAllowPlanToggleDeactivation(phase: .analyzing))
        XCTAssertFalse(shouldAllowPlanToggleDeactivation(phase: .questioning))
        XCTAssertFalse(shouldAllowPlanToggleDeactivation(phase: .generating))
        XCTAssertFalse(shouldAllowPlanToggleDeactivation(phase: .building))
        XCTAssertTrue(shouldAllowPlanToggleDeactivation(phase: .idle))
        XCTAssertTrue(shouldAllowPlanToggleDeactivation(phase: .proposalReady))
        XCTAssertTrue(shouldAllowPlanToggleDeactivation(phase: .readyToBuild))
    }

    func testPanelCloseDisablesToggleOnlyWhenNoActivePlanContext() {
        XCTAssertTrue(
            shouldDisablePlanToggleWhenPanelCloses(
                phase: .idle,
                planningState: .idle,
                coderMode: .agent
            )
        )
        XCTAssertFalse(
            shouldDisablePlanToggleWhenPanelCloses(
                phase: .building,
                planningState: .idle,
                coderMode: .agent
            )
        )
        XCTAssertFalse(
            shouldDisablePlanToggleWhenPanelCloses(
                phase: .idle,
                planningState: .awaitingClarification(questions: "## Questions\n1. X?"),
                coderMode: .agent
            )
        )
        XCTAssertFalse(
            shouldDisablePlanToggleWhenPanelCloses(
                phase: .idle,
                planningState: .idle,
                coderMode: .plan
            )
        )
    }

    func testShouldHidePlanMarkdownInChatRequiresPanelRouting() {
        XCTAssertFalse(
            shouldHidePlanMarkdownInChat(
                shouldRoutePlanStreamToPanel: false,
                coderMode: .agent,
                shouldRunPlanInline: false,
                fullLooksLikePlanPayload: true,
                shouldHidePlanMarkdownForBuild: false,
                hasActivePlanContext: false
            )
        )
    }

    func testShouldHidePlanMarkdownInChatWhenRoutedAndPlanSignalsPresent() {
        XCTAssertTrue(
            shouldHidePlanMarkdownInChat(
                shouldRoutePlanStreamToPanel: true,
                coderMode: .agent,
                shouldRunPlanInline: false,
                fullLooksLikePlanPayload: true,
                shouldHidePlanMarkdownForBuild: false,
                hasActivePlanContext: false
            )
        )
    }

    func testResolvePlanStepTargetConversationIdPrefersEventConversation() {
        let eventConversationId = UUID()
        let buildConversationId = UUID()
        let activeTaskConversationId = UUID()
        XCTAssertEqual(
            resolvePlanStepTargetConversationId(
                eventConversationId: eventConversationId,
                activeBuildPlanConversationId: buildConversationId,
                activeTaskConversationId: activeTaskConversationId
            ),
            eventConversationId
        )
    }

    func testResolvePlanStepTargetConversationIdFallsBackToBuildThenActiveTask() {
        let buildConversationId = UUID()
        let activeTaskConversationId = UUID()
        XCTAssertEqual(
            resolvePlanStepTargetConversationId(
                eventConversationId: nil,
                activeBuildPlanConversationId: buildConversationId,
                activeTaskConversationId: activeTaskConversationId
            ),
            buildConversationId
        )
        XCTAssertEqual(
            resolvePlanStepTargetConversationId(
                eventConversationId: nil,
                activeBuildPlanConversationId: nil,
                activeTaskConversationId: activeTaskConversationId
            ),
            activeTaskConversationId
        )
    }

    func testShouldResetTaskActivityStoreBeforeStartingTurnOnlyWithoutOtherActiveTasks() {
        let targetConversationId = UUID()
        XCTAssertTrue(
            shouldResetTaskActivityStoreBeforeStartingTurn(
                activeTaskConversationIds: Set([targetConversationId]),
                targetConversationId: targetConversationId
            )
        )
        XCTAssertFalse(
            shouldResetTaskActivityStoreBeforeStartingTurn(
                activeTaskConversationIds: Set([targetConversationId, UUID()]),
                targetConversationId: targetConversationId
            )
        )
    }
}
