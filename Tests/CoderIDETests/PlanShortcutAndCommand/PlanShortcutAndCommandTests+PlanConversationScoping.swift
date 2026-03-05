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

    func testResolveTodoClearTargetConversationIdPrefersExplicitEventConversation() {
        let eventConversationId = UUID()
        let buildPlanConversationId = UUID()
        let buildAgentConversationId = UUID()

        XCTAssertEqual(
            resolveTodoClearTargetConversationId(
                eventConversationId: eventConversationId,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId,
                activeTaskConversationId: UUID(),
                selectedConversationId: UUID()
            ),
            eventConversationId
        )
    }

    func testResolveTodoClearTargetConversationIdMapsBuildAgentConversationToBuildPlanConversation() {
        let buildPlanConversationId = UUID()
        let buildAgentConversationId = UUID()

        XCTAssertEqual(
            resolveTodoClearTargetConversationId(
                eventConversationId: buildAgentConversationId,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: buildAgentConversationId,
                activeTaskConversationId: UUID(),
                selectedConversationId: UUID()
            ),
            buildPlanConversationId
        )
    }

    func testResolveTodoClearTargetConversationIdFallsBackByPriorityWhenEventConversationMissing() {
        let buildPlanConversationId = UUID()
        let activeTaskConversationId = UUID()
        let selectedConversationId = UUID()

        XCTAssertEqual(
            resolveTodoClearTargetConversationId(
                eventConversationId: nil,
                activeBuildPlanConversationId: buildPlanConversationId,
                activeBuildAgentConversationId: UUID(),
                activeTaskConversationId: activeTaskConversationId,
                selectedConversationId: selectedConversationId
            ),
            buildPlanConversationId
        )

        XCTAssertEqual(
            resolveTodoClearTargetConversationId(
                eventConversationId: nil,
                activeBuildPlanConversationId: nil,
                activeBuildAgentConversationId: UUID(),
                activeTaskConversationId: activeTaskConversationId,
                selectedConversationId: selectedConversationId
            ),
            activeTaskConversationId
        )

        XCTAssertEqual(
            resolveTodoClearTargetConversationId(
                eventConversationId: nil,
                activeBuildPlanConversationId: nil,
                activeBuildAgentConversationId: nil,
                activeTaskConversationId: nil,
                selectedConversationId: selectedConversationId
            ),
            selectedConversationId
        )
    }
}
