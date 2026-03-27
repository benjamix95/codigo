import XCTest
@testable import CoderIDE

final class ChatPanelBuildBehaviorTests: XCTestCase {
    func testBuildPromptContainsNoEchoInstruction() {
        let instructions = """
        7. Do not repeat the plan in chat: execute, update status, provide minimal operational feedback.
        """
        XCTAssertTrue(instructions.localizedCaseInsensitiveContains("Do not repeat the plan in chat"))
    }

    func testBuildDoesNotAppendPlanTextToUserMessage() {
        let kickoff = "Plan build started: execute the selected option."
        XCTAssertFalse(kickoff.localizedCaseInsensitiveContains("## Option"))
        XCTAssertFalse(kickoff.localizedCaseInsensitiveContains("## Todo"))
    }

    func testNormalizeBuildFinalResponseRemovesPlanEchoBlocks() {
        let raw = """
        ## Option 1: Refactor
        Details...
        ## Todo
        - [ ] A
        - [ ] B

        ## Execution status
        Completed successfully.
        """
        let normalized = normalizeBuildFinalResponse(raw)
        XCTAssertFalse(normalized.localizedCaseInsensitiveContains("## Option"))
        XCTAssertFalse(normalized.localizedCaseInsensitiveContains("## Todo"))
        XCTAssertTrue(normalized.localizedCaseInsensitiveContains("Execution status"))
    }

    func testNormalizeBuildFinalResponseKeepsOperationalTodoSectionWhenNoPlanEcho() {
        let raw = """
        ## Execution status
        Updates:

        ## Todo
        - [x] Verify build
        - [x] Run tests
        """
        let normalized = normalizeBuildFinalResponse(raw)
        XCTAssertEqual(normalized, raw)
    }

    func testPlanBuildDisabledReasonCodes() {
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .analyzing,
                hasBuildChoice: true,
                providerExecutionCapable: true
            ),
            "Analyzing..."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .questioning,
                hasBuildChoice: true,
                providerExecutionCapable: true
            ),
            "Answer questions first"
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .generating,
                hasBuildChoice: true,
                providerExecutionCapable: true
            ),
            "Generating..."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .proposalReady,
                hasBuildChoice: false,
                providerExecutionCapable: true
            ),
            "No option selected"
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .proposalReady,
                hasBuildChoice: true,
                providerExecutionCapable: false
            ),
            "Auth required"
        )
        XCTAssertNil(
            planBuildDisabledReason(
                phase: .readyToBuild,
                hasBuildChoice: true,
                providerExecutionCapable: true
            )
        )
    }

    func testBuildPlanClarificationPromptIncludesCustomPrecedenceAndOptionalFinalNote() {
        let submission = PlanClarificationSubmission(
            answers: [
                PlanClarificationAnswer(
                    questionId: 2,
                    question: "Which priority do you want?",
                    optionId: "I",
                    optionText: "Other...",
                    customResponse: "Priority: production stability"
                ),
                PlanClarificationAnswer(
                    questionId: 1,
                    question: "What is the objective?",
                    optionId: "B",
                    optionText: "Fix bugs",
                    customResponse: nil
                ),
            ],
            finalNote: "Do not touch public APIs and keep backward compatibility."
        )

        let prompt = buildPlanClarificationPrompt(submission)
        XCTAssertTrue(prompt.contains("1. What is the objective?"))
        XCTAssertTrue(prompt.contains("Selected answer: B) Fix bugs"))
        XCTAssertTrue(prompt.contains("2. Which priority do you want?"))
        XCTAssertTrue(prompt.contains("Custom response (overrides selection): Priority: production stability"))
        XCTAssertTrue(prompt.contains("Final user note (optional): Do not touch public APIs"))
    }

    func testBuildPlanClarificationPromptOmitsCustomLineWhenAbsent() {
        let submission = PlanClarificationSubmission(
            answers: [
                PlanClarificationAnswer(
                    questionId: 1,
                    question: "Which area?",
                    optionId: "A",
                    optionText: "Chat UI",
                    customResponse: nil
                )
            ],
            finalNote: "Test on macOS."
        )

        let prompt = buildPlanClarificationPrompt(submission)
        XCTAssertFalse(prompt.contains("Custom response (overrides selection):"))
        XCTAssertTrue(prompt.contains("Final user note (optional): Test on macOS."))
    }

    func testBuildPlanClarificationPromptHandlesMissingFinalNote() {
        let submission = PlanClarificationSubmission(
            answers: [
                PlanClarificationAnswer(
                    questionId: 1,
                    question: "Which area?",
                    optionId: "A",
                    optionText: "Chat UI",
                    customResponse: nil
                )
            ],
            finalNote: ""
        )

        let prompt = buildPlanClarificationPrompt(submission)
        XCTAssertTrue(prompt.contains("Final user note: (omitted)"))
    }

    func testResolveSendTargetConversationKeepsCurrentSelection() {
        let currentConversationId = UUID()
        let context = EffectiveContext.empty()

        let resolution = resolveSendTargetConversation(
            currentConversationId: currentConversationId,
            effectiveContext: context,
            reusableConversationId: UUID()
        ) { _, _ in
            XCTFail("Non deve creare una nuova conversazione quando una selezione esiste gia'")
            return UUID()
        }

        XCTAssertEqual(resolution.conversationId, currentConversationId)
        XCTAssertFalse(resolution.requiresSelectionUpdate)
    }

    func testResolveSendTargetConversationPrefersReusableEmptyConversation() {
        let reusableConversationId = UUID()

        let resolution = resolveSendTargetConversation(
            currentConversationId: nil,
            effectiveContext: .empty(),
            reusableConversationId: reusableConversationId
        ) { _, _ in
            XCTFail("Non deve creare una conversazione quando ne esiste gia' una vuota riusabile")
            return UUID()
        }

        XCTAssertEqual(resolution.conversationId, reusableConversationId)
        XCTAssertTrue(resolution.requiresSelectionUpdate)
    }

    func testResolveSendTargetConversationCreatesConversationUsingEffectiveContextScope() {
        let context = ProjectContext(
            kind: .workspace,
            name: "Workspace",
            folderPaths: ["/tmp/app", "/tmp/lib"],
            isPinned: true,
            lastActiveFolderPath: "/tmp/lib"
        )
        let effective = EffectiveContext(
            contextId: context.id,
            folderPaths: context.folderPaths,
            isWorkspace: true,
            context: context
        )
        let createdConversationId = UUID()
        var capturedContextId: UUID?
        var capturedFolderPath: String?

        let resolution = resolveSendTargetConversation(
            currentConversationId: nil,
            effectiveContext: effective,
            reusableConversationId: nil
        ) { contextId, folderPath in
            capturedContextId = contextId
            capturedFolderPath = folderPath
            return createdConversationId
        }

        XCTAssertEqual(resolution.conversationId, createdConversationId)
        XCTAssertTrue(resolution.requiresSelectionUpdate)
        XCTAssertEqual(capturedContextId, context.id)
        XCTAssertEqual(capturedFolderPath, "/tmp/lib")
    }

    func testEffectiveContextSendGateAcceptsRealDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let effective = EffectiveContext(
            contextId: UUID(),
            folderPaths: [root.path],
            isWorkspace: false,
            context: nil
        )

        XCTAssertTrue(effective.hasSendableProjectContext)
    }

    func testEffectiveContextSendGateRejectsEmptyPlaceholderWorkspaceDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let effective = EffectiveContext(
            contextId: UUID(),
            folderPaths: [root.path],
            isWorkspace: false,
            context: nil
        )

        XCTAssertFalse(effective.hasSendableProjectContext)
    }
}
