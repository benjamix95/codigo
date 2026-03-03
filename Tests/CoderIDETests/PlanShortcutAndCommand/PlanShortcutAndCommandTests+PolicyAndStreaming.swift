import AppKit
import XCTest
@testable import CoderIDE

extension PlanShortcutAndCommandTests {
    func testIsPlanBuildContextMatchesActiveBuildConversationEvenWhenPhaseIdle() {
        let buildPlanConversationId = UUID()
        let buildAgentConversationId = UUID()
        XCTAssertTrue(
            isPlanBuildContext(
                conversationId: buildPlanConversationId,
                phase: .idle,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )
        XCTAssertTrue(
            isPlanBuildContext(
                conversationId: buildAgentConversationId,
                phase: .idle,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )
        XCTAssertFalse(
            isPlanBuildContext(
                conversationId: UUID(),
                phase: .idle,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )
    }

    func testShouldEnableTaskPanelForOperationalModes() {
        XCTAssertTrue(shouldEnableTaskPanelForMode(.agent))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.debug))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.plan))
        XCTAssertTrue(shouldEnableTaskPanelForMode(.codeReviewMultiSwarm))
        XCTAssertFalse(shouldEnableTaskPanelForMode(.ide))
        XCTAssertFalse(shouldEnableTaskPanelForMode(.mcpServer))
    }

    func testShouldAutoOpenSwarmPanelForEvent_requiresConversationMatch() {
        let selectedConversationId = UUID()
        XCTAssertTrue(
            shouldAutoOpenSwarmPanelForEvent(
                eventConversationId: selectedConversationId,
                selectedConversationId: selectedConversationId
            )
        )
        XCTAssertFalse(
            shouldAutoOpenSwarmPanelForEvent(
                eventConversationId: UUID(),
                selectedConversationId: selectedConversationId
            )
        )
    }

    func testShouldAutoOpenSwarmPanelForEvent_allowsUntaggedEventForActiveConversation() {
        XCTAssertTrue(
            shouldAutoOpenSwarmPanelForEvent(
                eventConversationId: nil,
                selectedConversationId: UUID()
            )
        )
    }

    func testShouldAutoOpenSwarmPanelForEvent_blocksWhenNoSelectedConversation() {
        XCTAssertFalse(
            shouldAutoOpenSwarmPanelForEvent(
                eventConversationId: UUID(),
                selectedConversationId: nil
            )
        )
        XCTAssertFalse(
            shouldAutoOpenSwarmPanelForEvent(
                eventConversationId: nil,
                selectedConversationId: nil
            )
        )
    }

    func testResolveDebugFlowPhaseAliasSupportsLegacyPhaseNames() {
        XCTAssertEqual(resolveDebugFlowPhaseAlias("analyzing"), .describing)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("reproduce"), .reproducing)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("fix"), .fixing)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("instrument"), .instrumenting)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("verify"), .verifying)
        XCTAssertEqual(resolveDebugFlowPhaseAlias("resolve"), .resolved)
        XCTAssertNil(resolveDebugFlowPhaseAlias("unexpected_phase"))
    }

    func testShouldStartDebugSessionOnAutoActivateOnlyWhenIdleOrResolved() {
        XCTAssertTrue(shouldStartDebugSessionOnAutoActivate(currentPhase: .idle))
        XCTAssertTrue(shouldStartDebugSessionOnAutoActivate(currentPhase: .resolved))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .describing))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .reproducing))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .fixing))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .instrumenting))
        XCTAssertFalse(shouldStartDebugSessionOnAutoActivate(currentPhase: .verifying))
    }

    func testResolveShouldRunPlanInlineOneShotBehaviorForSlashPlan() {
        let firstSend = resolveShouldRunPlanInline(
            forcePlanInline: true,
            coderMode: .agent,
            planToggleEnabled: false
        )
        XCTAssertTrue(firstSend)

        let secondSend = resolveShouldRunPlanInline(
            forcePlanInline: false,
            coderMode: .agent,
            planToggleEnabled: false
        )
        XCTAssertFalse(secondSend)
    }

    func testResolveShouldRunPlanInlineRespectsManualToggle() {
        XCTAssertTrue(
            resolveShouldRunPlanInline(
                forcePlanInline: false,
                coderMode: .agent,
                planToggleEnabled: true
            )
        )
        XCTAssertFalse(
            resolveShouldRunPlanInline(
                forcePlanInline: false,
                coderMode: .plan,
                planToggleEnabled: true
            )
        )
    }

    func testNonSwarmModesShowComposerAndFooter() {
        XCTAssertFalse(shouldShowSwarmViewOnly(for: .agent))
        XCTAssertTrue(shouldShowComposer(for: .agent))
        XCTAssertTrue(shouldShowUsageFooter(for: .agent))
    }

    func testUsageFooterVisibleInEveryMode() {
        for mode in CoderMode.allCases {
            XCTAssertTrue(shouldShowUsageFooter(for: mode), "Footer usage should be visible in \\(mode.rawValue)")
        }
    }

    func testPlanContextDoesNotActivateFromGenericTaskState() {
        let currentConversationId = UUID()
        let streamConversationId = UUID()
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: false,
            hasActivePlanFlowPhase: false,
            streamConversationId: streamConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: false,
            hasPlanBoardForCurrentConversation: false,
            showPlanPanel: false,
            activeBuildPlanConversationId: nil
        )
        XCTAssertFalse(result)
    }

    func testPlanContextDoesNotActivateFromPersistedPlanBoardOnly() {
        let currentConversationId = UUID()
        let streamConversationId = currentConversationId
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: false,
            hasActivePlanFlowPhase: false,
            streamConversationId: streamConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: true,
            hasPlanBoardForCurrentConversation: true,
            showPlanPanel: false,
            activeBuildPlanConversationId: nil
        )
        XCTAssertFalse(result)
    }

    func testPlanContextDoesNotActivateFromPanelOpenOnly() {
        let currentConversationId = UUID()
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: false,
            hasActivePlanFlowPhase: false,
            streamConversationId: currentConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: true,
            hasPlanBoardForCurrentConversation: true,
            showPlanPanel: true,
            activeBuildPlanConversationId: nil
        )
        XCTAssertFalse(result)
    }

    func testPlanContextDoesNotLeakToDifferentStreamConversationWhenInlinePlanActive() {
        let currentConversationId = UUID()
        let otherConversationId = UUID()
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: true,
            hasActivePlanFlowPhase: true,
            streamConversationId: otherConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: false,
            hasPlanBoardForCurrentConversation: true,
            showPlanPanel: true,
            activeBuildPlanConversationId: nil
        )
        XCTAssertFalse(result)
    }

    func testPlanContextStillActivatesForExplicitActiveBuildConversation() {
        let currentConversationId = UUID()
        let buildConversationId = UUID()
        let result = shouldTreatConversationAsPlanContext(
            coderMode: .agent,
            hasInlinePlanSession: false,
            hasActivePlanFlowPhase: false,
            streamConversationId: buildConversationId,
            currentConversationId: currentConversationId,
            hasPlanBoardForStreamConversation: false,
            hasPlanBoardForCurrentConversation: false,
            showPlanPanel: false,
            activeBuildPlanConversationId: buildConversationId
        )
        XCTAssertTrue(result)
    }

    func testShouldMutatePlanStateOnlyForCurrentConversation() {
        let currentConversationId = UUID()
        let otherConversationId = UUID()
        XCTAssertTrue(
            shouldMutatePlanState(
                targetConversationId: currentConversationId,
                currentConversationId: currentConversationId
            )
        )
        XCTAssertFalse(
            shouldMutatePlanState(
                targetConversationId: otherConversationId,
                currentConversationId: currentConversationId
            )
        )
        XCTAssertFalse(
            shouldMutatePlanState(
                targetConversationId: otherConversationId,
                currentConversationId: nil
            )
        )
    }

    func testRoutePlanStreamOnlyForPlanContextOrActiveBuildConversations() {
        let streamConversationId = UUID()
        let activeBuildPlanConversationId = UUID()
        let activeBuildAgentConversationId = UUID()

        XCTAssertTrue(
            shouldRoutePlanStreamToPlanPanel(
                shouldRoutePlanStreamingToPanel: true,
                streamConversationId: streamConversationId,
                hasActivePlanContext: true,
}
