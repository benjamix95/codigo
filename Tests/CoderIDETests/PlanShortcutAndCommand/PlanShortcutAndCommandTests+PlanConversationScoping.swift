import AppKit
import XCTest
@testable import CoderIDE

extension PlanShortcutAndCommandTests {
    func testShouldMirrorLegacyPlanStepIntoActiveBuildPlanOnlyForBuildScopedTargets() {
        let buildPlanConversationId = UUID()
        let buildAgentConversationId = UUID()
        let otherConversationId = UUID()

        XCTAssertTrue(
            shouldMirrorLegacyPlanStepIntoActiveBuildPlan(
                targetConversationId: buildAgentConversationId,
                phase: .building,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )

        XCTAssertFalse(
            shouldMirrorLegacyPlanStepIntoActiveBuildPlan(
                targetConversationId: otherConversationId,
                phase: .building,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )

        XCTAssertFalse(
            shouldMirrorLegacyPlanStepIntoActiveBuildPlan(
                targetConversationId: buildPlanConversationId,
                phase: .building,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            )
        )
    }

    func testResolveCanonicalPlanTodoConversationIdUsesBuildPlanOnlyInsideBuildScope() {
        let buildPlanConversationId = UUID()
        let buildAgentConversationId = UUID()
        let otherConversationId = UUID()

        XCTAssertEqual(
            resolveCanonicalPlanTodoConversationId(
                targetConversationId: buildAgentConversationId,
                phase: .building,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            ),
            buildPlanConversationId
        )

        XCTAssertEqual(
            resolveCanonicalPlanTodoConversationId(
                targetConversationId: buildPlanConversationId,
                phase: .building,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            ),
            buildPlanConversationId
        )

        XCTAssertEqual(
            resolveCanonicalPlanTodoConversationId(
                targetConversationId: otherConversationId,
                phase: .building,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId
            ),
            otherConversationId
        )
    }

    func testResolveCanonicalPlanTodoConversationIdFallsBackToTargetWhenNoBuildPlanConversation() {
        let buildAgentConversationId = UUID()

        XCTAssertEqual(
            resolveCanonicalPlanTodoConversationId(
                targetConversationId: buildAgentConversationId,
                phase: .building,
                activeBuildPlanConversationId: nil,
                activeBuildAgentConversationId: buildAgentConversationId
            ),
            buildAgentConversationId
        )
    }
}
