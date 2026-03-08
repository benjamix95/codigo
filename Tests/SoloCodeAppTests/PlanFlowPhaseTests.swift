import XCTest
@testable import CoderIDE

final class PlanFlowPhaseTests: XCTestCase {
    func testBuildBlockedWhenPhaseNotReady() {
        XCTAssertFalse(canExecutePlanBuild(phase: .analyzing, choice: "Option 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .questioning, choice: "Option 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .generating, choice: "Option 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .building, choice: "Option 1"))
    }

    func testPhaseTransitionsAnalyzingToQuestioning() {
        let text = """
        ## Questions
        1. Which module should be modified?
        A) Parser
        B) UI

        2. Are there compatibility constraints?
        A) Yes
        B) No
        """
        let phase = nextPlanFlowPhaseForOutput(
            fullText: text,
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(phase, .questioning)
    }

    func testPhaseTransitionsProposalToReadyToBuildViaGating() {
        XCTAssertFalse(canExecutePlanBuild(phase: .idle, choice: "## Option 1: A"))
        XCTAssertTrue(canExecutePlanBuild(phase: .idle, choice: "## Option 1: A", allowIdleRebuild: true))
        XCTAssertTrue(canExecutePlanBuild(phase: .proposalReady, choice: "## Option 1: A"))
        XCTAssertTrue(canExecutePlanBuild(phase: .readyToBuild, choice: "## Option 1: A"))
    }

    func testCanStartPlanBuildBlocksConcurrentExecution() {
        XCTAssertFalse(canStartPlanBuild(isLoading: true, phase: .proposalReady))
        XCTAssertFalse(canStartPlanBuild(isLoading: false, phase: .building))
        XCTAssertTrue(canStartPlanBuild(isLoading: false, phase: .proposalReady))
    }

    func testPhaseStaysAnalyzingOnGenericTextWithoutTodoCompliantOptions() {
        let phase = nextPlanFlowPhaseForOutput(
            fullText: "Analysis complete, but more information is required.",
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(phase, .analyzing)
    }

    func testPanelBuildEnabledInIdleWhenChoiceExists() {
        XCTAssertFalse(isPlanBuildEnabled(phase: .idle, hasBuildChoice: true))
        XCTAssertTrue(isPlanBuildEnabled(phase: .idle, hasBuildChoice: true, allowIdleRebuild: true))
    }

    func testPanelBuildDisabledWhenProviderIsNotExecutionCapable() {
        XCTAssertFalse(
            isPlanBuildEnabled(
                phase: .readyToBuild,
                hasBuildChoice: true,
                allowIdleRebuild: false,
                providerExecutionCapable: false
            )
        )
    }

    func testPanelBuildDisabledInIdleWhenNoChoiceExists() {
        XCTAssertFalse(isPlanBuildEnabled(phase: .idle, hasBuildChoice: false))
    }

    // MARK: - Classification skips building phase

    func testClassifierDoesNotReclassifyDuringBuildingPhase() {
        // Build output that accidentally matches option patterns should NOT
        // change the phase away from .building.
        let buildOutput = """
        ## Option 1: Refactor
        ## Todo
        - [ ] Step 1
        """
        let classification = PlanOutputClassifier.classify(
            fullText: buildOutput,
            current: .building,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertFalse(classification.hasStrictOptions)
        XCTAssertEqual(classification.nextPhase, .building)
        XCTAssertNil(classification.planningState)
    }

    func testBuildPhaseExcludedFromNormalizationClassification() {
        // normalizeBuildFinalResponse strips plan echoes from build output
        let echoed = """
        ## Option 1: Refactor
        ## Todo
        - [ ] Step 1
        ## Summary
        Build completed successfully.
        """
        let normalized = normalizeBuildFinalResponse(echoed)
        // The normalized text should strip the plan-echo sections
        XCTAssertFalse(normalized.contains("## Option 1"))
    }

    func testPlanBuildDisabledReasonForNonExecutableProvider() {
        let reason = planBuildDisabledReason(
            phase: .readyToBuild,
            hasBuildChoice: true,
            providerExecutionCapable: false
        )
        XCTAssertEqual(reason, "Auth required")
    }

    func testHasPlanContextIncludesAllActivePhases() {
        for phase: PlanFlowPhase in [.analyzing, .questioning, .generating, .proposalReady, .readyToBuild, .building] {
            XCTAssertTrue(
                hasPlanContext(phase: phase, planningState: .idle, hasPlanBoard: false, hasSelectedHistoryEntry: false),
                "Phase \(phase) should have plan context"
            )
        }
    }

    func testAllowIdleRebuildFromMainBuildActionOnlyWhenIdleAndChoiceExists() {
        XCTAssertTrue(
            shouldAllowIdleRebuildFromMainBuildAction(
                phase: .idle,
                hasBuildChoice: true
            )
        )
        XCTAssertFalse(
            shouldAllowIdleRebuildFromMainBuildAction(
                phase: .readyToBuild,
                hasBuildChoice: true
            )
        )
        XCTAssertFalse(
            shouldAllowIdleRebuildFromMainBuildAction(
                phase: .idle,
                hasBuildChoice: false
            )
        )
    }

    func testConversationSwitchResetsOnlyActivePlanPhases() {
        let targetConversationId = UUID()
        let otherConversationId = UUID()

        XCTAssertTrue(
            shouldResetPlanFlowAfterConversationSwitch(
                targetConversationId: targetConversationId,
                currentConversationId: otherConversationId,
                phase: .analyzing
            )
        )
        XCTAssertTrue(
            shouldResetPlanFlowAfterConversationSwitch(
                targetConversationId: targetConversationId,
                currentConversationId: otherConversationId,
                phase: .questioning
            )
        )
        XCTAssertTrue(
            shouldResetPlanFlowAfterConversationSwitch(
                targetConversationId: targetConversationId,
                currentConversationId: otherConversationId,
                phase: .generating
            )
        )
        XCTAssertFalse(
            shouldResetPlanFlowAfterConversationSwitch(
                targetConversationId: targetConversationId,
                currentConversationId: otherConversationId,
                phase: .proposalReady
            )
        )
    }
}
