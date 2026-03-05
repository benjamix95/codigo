import AppKit
import XCTest
@testable import CoderIDE

extension PlanShortcutAndCommandTests {
    func testRoutePlanStreamOnlyForPlanContextOrActiveBuildConversations() {
        let streamConversationId = UUID()
        let activeBuildPlanConversationId = UUID()
        let activeBuildAgentConversationId = UUID()

        XCTAssertTrue(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: true,
                streamConversationId: streamConversationId,
                hasActivePlanContext: true,
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
                hasActivePlanBuildTask: false,
                hasResumablePlanState: false
            )
        )
        XCTAssertFalse(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .building,
                hasActivePlanBuildTask: false,
                hasResumablePlanState: false
            )
        )
        XCTAssertFalse(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .idle,
                hasActivePlanBuildTask: true,
                hasResumablePlanState: false
            )
        )
        XCTAssertFalse(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .idle,
                hasActivePlanBuildTask: false,
                hasResumablePlanState: true
            )
        )
        XCTAssertFalse(
            shouldClearPlanCanonicalTodosOnNewTurn(
                phase: .readyToBuild,
                hasActivePlanBuildTask: false,
                hasResumablePlanState: false
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

    func testClarificationQuestionsMarkdownFromSnapshotAcceptsStructuredQuestionnaire() {
        let snapshot = """
        ## Questions
        1. Target platform? (select all that apply)
        A) iOS
        B) macOS
        """
        let restored = clarificationQuestionsMarkdownFromSnapshot(snapshot)
        XCTAssertNotNil(restored)
        XCTAssertEqual(PlanOptionsParser.parseClarificationQuestionnaire(from: restored ?? "")?.questions.count, 1)
    }

    func testClarificationQuestionsMarkdownFromSnapshotRejectsGenericPlanContent() {
        let snapshot = """
        ## Plan
        Refactor parser and add tests.
        """
        XCTAssertNil(clarificationQuestionsMarkdownFromSnapshot(snapshot))
    }

    func testNormalizedPlanStreamingSnapshotTrimsAndTruncatesFromTail() {
        let prefix = String(repeating: "x", count: 60)
        let suffix = String(repeating: "y", count: 80)
        let normalized = normalizedPlanStreamingSnapshot("\n  \(prefix)\(suffix)  \n", maxLength: 80)
        XCTAssertEqual(normalized.count, 80)
        XCTAssertTrue(normalized.allSatisfy { $0 == "y" })
    }
}
