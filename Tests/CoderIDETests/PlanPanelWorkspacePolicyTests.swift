import XCTest
@testable import CoderIDE

final class PlanPanelWorkspacePolicyTests: XCTestCase {
    func testHasPlanContextFalseWhenCompletelyIdle() {
        XCTAssertFalse(
            hasPlanContext(
                phase: .idle,
                planningState: .idle,
                hasPlanBoard: false,
                hasSelectedHistoryEntry: false
            )
        )
    }

    func testHasPlanContextTrueForActivePhase() {
        XCTAssertTrue(
            hasPlanContext(
                phase: .analyzing,
                planningState: .idle,
                hasPlanBoard: false,
                hasSelectedHistoryEntry: false
            )
        )
    }

    func testHasPlanContextTrueForAwaitingClarification() {
        XCTAssertTrue(
            hasPlanContext(
                phase: .idle,
                planningState: .awaitingClarification(questions: "## Questions\n1. A?"),
                hasPlanBoard: false,
                hasSelectedHistoryEntry: false
            )
        )
    }

    func testHasPlanContextTrueForBoardOrHistorySelection() {
        XCTAssertTrue(
            hasPlanContext(
                phase: .idle,
                planningState: .idle,
                hasPlanBoard: true,
                hasSelectedHistoryEntry: false
            )
        )
        XCTAssertTrue(
            hasPlanContext(
                phase: .idle,
                planningState: .idle,
                hasPlanBoard: false,
                hasSelectedHistoryEntry: true
            )
        )
    }

    func testShouldMirrorAssistantContentFollowsPlanContext() {
        XCTAssertFalse(shouldMirrorAssistantContentInPlanWorkspace(hasPlanContext: false))
        XCTAssertTrue(shouldMirrorAssistantContentInPlanWorkspace(hasPlanContext: true))
    }

    func testHistoryEntryCompatibilityAllowsSameContextAcrossDifferentConversation() {
        let contextId = UUID()
        let currentConversationId = UUID()
        let otherConversationId = UUID()
        let entry = PlanHistoryEntry(
            conversationId: otherConversationId,
            contextId: contextId,
            contextFolderPath: nil,
            title: "Plan",
            markdown: "## Plan: A\n## Todo\n- [ ] Step",
            options: [],
            chosenPath: nil
        )

        XCTAssertTrue(
            isPlanHistoryEntryCompatibleWithCurrentContext(
                entry: entry,
                currentConversationId: currentConversationId,
                currentContextId: contextId,
                currentContextFolderPath: nil
            )
        )
    }

    func testHistoryEntryCompatibilityRejectsDifferentContext() {
        let entry = PlanHistoryEntry(
            conversationId: UUID(),
            contextId: UUID(),
            contextFolderPath: "/tmp/other",
            title: "Plan",
            markdown: "## Plan: A\n## Todo\n- [ ] Step",
            options: [],
            chosenPath: nil
        )

        XCTAssertFalse(
            isPlanHistoryEntryCompatibleWithCurrentContext(
                entry: entry,
                currentConversationId: UUID(),
                currentContextId: UUID(),
                currentContextFolderPath: "/tmp/current"
            )
        )
    }

    func testHistoryEntryThreadCompatibilityAllowsSameConversation() {
        let conversationId = UUID()
        XCTAssertTrue(
            isPlanHistoryEntryCompatibleWithCurrentThread(
                entryConversationId: conversationId,
                currentConversationId: conversationId,
                entryThreadRootConversationId: UUID(),
                currentThreadRootConversationId: UUID()
            )
        )
    }

    func testHistoryEntryThreadCompatibilityAllowsSameThreadRoot() {
        let threadRoot = UUID()
        XCTAssertTrue(
            isPlanHistoryEntryCompatibleWithCurrentThread(
                entryConversationId: UUID(),
                currentConversationId: UUID(),
                entryThreadRootConversationId: threadRoot,
                currentThreadRootConversationId: threadRoot
            )
        )
    }

    func testHistoryEntryThreadCompatibilityRejectsDifferentThreadRoots() {
        XCTAssertFalse(
            isPlanHistoryEntryCompatibleWithCurrentThread(
                entryConversationId: UUID(),
                currentConversationId: UUID(),
                entryThreadRootConversationId: UUID(),
                currentThreadRootConversationId: UUID()
            )
        )
    }

    func testMakePlanFileNamePrefersPlanTitleOverConversationTitle() {
        let fileName = makePlanFileName(
            preferredPlanTitle: "Implementare Sync Offline v2",
            fallbackConversationTitle: "Chat Generica"
        )

        XCTAssertEqual(fileName, "implementare_sync_offline_v2.plan.md")
    }

    func testMakePlanFileNameFallsBackToConversationTitleWhenPlanTitleMissing() {
        let fileName = makePlanFileName(
            preferredPlanTitle: "   ",
            fallbackConversationTitle: "Refactor Auth Flow"
        )

        XCTAssertEqual(fileName, "refactor_auth_flow.plan.md")
    }

    func testMakePlanFileNameFallsBackToDefaultWhenTitlesMissing() {
        let fileName = makePlanFileName(
            preferredPlanTitle: nil,
            fallbackConversationTitle: "  "
        )

        XCTAssertEqual(fileName, "plan.plan.md")
    }

    func testPlanRenderSnapshotCacheKeyChangesWhenMiddleContentChanges() {
        let prefix = String(repeating: "A", count: 220)
        let suffix = String(repeating: "Z", count: 220)
        let middleA = String(repeating: "1", count: 120)
        let middleB = String(repeating: "2", count: 120)
        let contentA = prefix + middleA + suffix
        let contentB = prefix + middleB + suffix

        XCTAssertEqual(contentA.count, contentB.count)
        XCTAssertEqual(contentA.prefix(200), contentB.prefix(200))
        XCTAssertEqual(contentA.suffix(200), contentB.suffix(200))

        let keyA = makePlanRenderSnapshotCacheKey(content: contentA, canonicalTodos: [])
        let keyB = makePlanRenderSnapshotCacheKey(content: contentB, canonicalTodos: [])
        XCTAssertNotEqual(keyA, keyB)
    }

    func testPlanRenderSnapshotCacheKeyIncludesCanonicalTodoStatusFingerprint() {
        let todoId = UUID()
        let baseTodo = TodoItem(
            id: todoId,
            title: "Implement parser",
            status: .pending,
            priority: .medium,
            source: .agent,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            notes: "",
            linkedFiles: [],
            isPlanCanonical: true
        )
        let completedTodo = TodoItem(
            id: todoId,
            title: "Implement parser",
            status: .done,
            priority: .medium,
            source: .agent,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            notes: "",
            linkedFiles: [],
            isPlanCanonical: true
        )
        let content = "## Plan\n- Stable content"
        let keyPending = makePlanRenderSnapshotCacheKey(content: content, canonicalTodos: [baseTodo])
        let keyDone = makePlanRenderSnapshotCacheKey(content: content, canonicalTodos: [completedTodo])
        XCTAssertNotEqual(keyPending, keyDone)
    }
}
