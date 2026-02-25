import XCTest
@testable import CoderIDE

@MainActor
final class PlanBuildIntegrationFlowTests: XCTestCase {
    func testEndToEndModelResponseToBuildStartPrompt() {
        let modelResponse = """
        ## Option 1: Refactor parser
        ## Todo
        - [ ] Extract parser helper
        - [ ] Update parser tests

        ## Option 2: Harden build pipeline
        ## Todo
        - [ ] Add plan/build integration test
        - [ ] Run swift test
        """

        let classification = PlanOutputClassifier.classify(
            fullText: modelResponse,
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(classification.nextPhase, .proposalReady)

        guard case .awaitingChoice(_, let options) = classification.planningState else {
            return XCTFail("expected planningState: awaitingChoice")
        }
        XCTAssertEqual(options.count, 2)

        let chosen = options[1].fullText
        XCTAssertTrue(canStartPlanBuild(isLoading: false, phase: classification.nextPhase))
        XCTAssertTrue(canExecutePlanBuild(phase: classification.nextPhase, choice: chosen))

        let extractedTodos = PlanOptionsParser.extractTodosFromOptionText(chosen)
        XCTAssertEqual(extractedTodos, [
            "Add plan/build integration test",
            "Run swift test",
        ])

        let result = buildPlanExecutionPrompt(
            workflowInstructions: "WF",
            executionPlanBase: "**Plan:**\n\(chosen)",
            planTodos: extractedTodos,
            canonicalTodos: []
        )
        XCTAssertFalse(result.isResume)
        XCTAssertTrue(result.prompt.contains("MANDATORY TODOs"))
        XCTAssertTrue(result.prompt.contains("1. [ ] Add plan/build integration test"))
        XCTAssertTrue(result.prompt.contains("2. [ ] Run swift test"))
        XCTAssertFalse(result.prompt.contains("Already completed todos"))
    }

    func testResumeFlowReusesCanonicalTodosAndBuildsResumePrompt() {
        let store = TodoStore()
        let planTodos = [
            "Create full-path integration test",
            "Run swift test"
        ]
        store.upsertCanonicalPlanTodos(planTodos)
        let initialCanonicalByTitle = Dictionary(
            uniqueKeysWithValues: store.todos
                .filter(\.isPlanCanonical)
                .map { ($0.title, $0.id) }
        )

        store.upsertFromAgent(
            id: nil,
            title: "Create full-path integration test",
            status: .done,
            priority: .high,
            notes: "completed",
            linkedFiles: []
        )
        store.upsertCanonicalPlanTodos(planTodos)

        let canonicalAfter = store.todos.filter(\.isPlanCanonical)
        let afterByTitle = Dictionary(uniqueKeysWithValues: canonicalAfter.map { ($0.title, $0.id) })
        XCTAssertEqual(initialCanonicalByTitle, afterByTitle)
        XCTAssertTrue(isPlanResumeBuild(canonicalTodos: canonicalAfter))

        let result = buildPlanExecutionPrompt(
            workflowInstructions: "WF",
            executionPlanBase: "**Plan:**\nSelected option",
            planTodos: planTodos,
            canonicalTodos: canonicalAfter
        )
        XCTAssertTrue(result.isResume)
        XCTAssertTrue(result.prompt.contains("**IMPLEMENTATION RESUME**"))
        XCTAssertTrue(result.prompt.contains("- [x] Create full-path integration test"))
        XCTAssertTrue(result.prompt.contains("- [ ] Run swift test"))
    }

    func testExecutionPromptDoesNotCreateRedundantTodoListDuringResume() {
        let now = Date()
        let canonicalTodos = [
            TodoItem(
                title: "Completed task",
                status: .done,
                source: .agent,
                createdAt: now.addingTimeInterval(-100),
                updatedAt: now.addingTimeInterval(-50),
                isPlanCanonical: true
            ),
            TodoItem(
                title: "Open task",
                status: .pending,
                source: .agent,
                createdAt: now.addingTimeInterval(-40),
                updatedAt: now.addingTimeInterval(-20),
                isPlanCanonical: true
            ),
        ]

        let result = buildPlanExecutionPrompt(
            workflowInstructions: "WF",
            executionPlanBase: "BASE",
            planTodos: ["Completed task", "Open task"],
            canonicalTodos: canonicalTodos
        )

        XCTAssertTrue(result.isResume)
        XCTAssertFalse(result.prompt.contains("MANDATORY TODOs"))
        XCTAssertTrue(result.prompt.contains("**Already completed todos:**"))
        XCTAssertTrue(result.prompt.contains("**Remaining todos:**"))
    }
}
