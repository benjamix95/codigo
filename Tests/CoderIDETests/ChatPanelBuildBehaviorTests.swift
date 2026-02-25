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
            "Codebase analysis in progress: wait for completion."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .questioning,
                hasBuildChoice: true,
                providerExecutionCapable: true
            ),
            "Clarifications required: answer the questions before Build."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .generating,
                hasBuildChoice: true,
                providerExecutionCapable: true
            ),
            "Plan generation in progress: wait for completion."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .proposalReady,
                hasBuildChoice: false,
                providerExecutionCapable: true
            ),
            "No executable option available."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .proposalReady,
                hasBuildChoice: true,
                providerExecutionCapable: false
            ),
            "Provider not ready: select an authenticated execution-capable provider."
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
}
