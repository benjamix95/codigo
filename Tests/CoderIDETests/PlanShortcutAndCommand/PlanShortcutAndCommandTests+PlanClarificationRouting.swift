import XCTest
@testable import CoderIDE

extension PlanShortcutAndCommandTests {
    func testClarificationQuestionsMarkdownFromSnapshotAcceptsStructuredQuestionnaire() {
        let snapshot = """
        ## Questions
        1. Target platform? (select all that apply)
        A) iOS
        B) macOS
        """
        let restored = clarificationQuestionsMarkdownFromSnapshot(snapshot)
        XCTAssertNotNil(restored)
        XCTAssertEqual(
            PlanOptionsParser.parseClarificationQuestionnaire(from: restored ?? "")?.questions.count,
            1
        )
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

    func testClarificationQuestionsMarkdownForRestoreSkipsBuildScopedConversation() {
        let snapshot = """
        ## Questions
        1. Target platform? (select all that apply)
        A) iOS
        B) macOS
        """
        let restored = clarificationQuestionsMarkdownForRestore(
            snapshot,
            isBuildScopedConversation: true
        )
        XCTAssertNil(restored)
    }

    func testClarificationQuestionsMarkdownFromSnapshotAcceptsClarificationsNeededHeader() {
        let snapshot = """
        ## Clarifications Needed
        1. Quale area e' bloccante?
        A) Todo sync
        B) Routing panel/chat
        """
        let restored = clarificationQuestionsMarkdownFromSnapshot(snapshot)
        XCTAssertNotNil(restored)
        XCTAssertEqual(
            PlanOptionsParser.parseClarificationQuestionnaire(from: restored ?? "")?.questions.count,
            1
        )
    }

    func testPlanQuestionToolEpochDefaultsToZeroWhenConversationHasNoEvents() {
        XCTAssertEqual(planQuestionToolEpoch(for: UUID()), 0)
    }

    func testIncrementPlanQuestionToolEpochIsScopedPerConversation() {
        let firstConversationId = UUID()
        let secondConversationId = UUID()
        var globalEpoch = 0

        XCTAssertEqual(
            incrementPlanQuestionToolEpoch(
                for: firstConversationId,
                globalEpoch: &globalEpoch
            ),
            1
        )
        XCTAssertEqual(
            incrementPlanQuestionToolEpoch(
                for: secondConversationId,
                globalEpoch: &globalEpoch
            ),
            1
        )
        XCTAssertEqual(
            incrementPlanQuestionToolEpoch(
                for: firstConversationId,
                globalEpoch: &globalEpoch
            ),
            2
        )
        XCTAssertEqual(planQuestionToolEpoch(for: firstConversationId), 2)
        XCTAssertEqual(planQuestionToolEpoch(for: secondConversationId), 1)
        XCTAssertEqual(globalEpoch, 3)
    }

    func testResolveClarificationIdentitySeedUsesScopedConversationEpoch() {
        let targetConversationId = UUID()
        let otherConversationId = UUID()
        var globalEpoch = 0

        _ = incrementPlanQuestionToolEpoch(for: targetConversationId, globalEpoch: &globalEpoch)
        _ = incrementPlanQuestionToolEpoch(for: otherConversationId, globalEpoch: &globalEpoch)
        _ = incrementPlanQuestionToolEpoch(for: otherConversationId, globalEpoch: &globalEpoch)
        _ = incrementPlanQuestionToolEpoch(for: otherConversationId, globalEpoch: &globalEpoch)

        let seed = resolveClarificationIdentitySeed(
            planClarificationCycles: 0,
            planConversationId: targetConversationId,
            globalEpoch: globalEpoch
        )

        XCTAssertEqual(seed, 1)
        XCTAssertEqual(globalEpoch, 4)
    }

    func testClarificationsNeededSectionSupportsHeaderVariants() {
        let markdown = """
        Intro line
        ### clarificaTions needed
        1. Quale provider vuoi usare?
        A) OpenAI
        B) Claude
        """
        let section = clarificationsNeededSection(from: markdown)
        XCTAssertNotNil(section)
        XCTAssertTrue(section?.hasPrefix("### clarificaTions needed") == true)
    }

    func testClarificationsNeededSectionReturnsNilWhenHeadingMissing() {
        let markdown = """
        ## Plan
        Refactor parser e poi aggiungi test.
        """
        XCTAssertNil(clarificationsNeededSection(from: markdown))
    }
}
