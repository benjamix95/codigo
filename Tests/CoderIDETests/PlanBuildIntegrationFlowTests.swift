import XCTest
@testable import CoderIDE

@MainActor
final class PlanBuildIntegrationFlowTests: XCTestCase {
    func testEndToEndModelResponseToBuildStartPrompt() {
        let modelResponse = """
        ## Opzione 1: Refactor parser
        ## Todo
        - [ ] Estrarre helper parser
        - [ ] Aggiornare test parser

        ## Opzione 2: Hardening build pipeline
        ## Todo
        - [ ] Aggiungere test integrazione plan/build
        - [ ] Eseguire swift test
        """

        let classification = PlanOutputClassifier.classify(
            fullText: modelResponse,
            current: .discovery,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(classification.nextPhase, .proposalReady)

        guard case .awaitingChoice(_, let options) = classification.planningState else {
            return XCTFail("planningState atteso: awaitingChoice")
        }
        XCTAssertEqual(options.count, 2)

        let chosen = options[1].fullText
        XCTAssertTrue(canStartPlanBuild(isLoading: false, phase: classification.nextPhase))
        XCTAssertTrue(canExecutePlanBuild(phase: classification.nextPhase, choice: chosen))

        let extractedTodos = PlanOptionsParser.extractTodosFromOptionText(chosen)
        XCTAssertEqual(extractedTodos, [
            "Aggiungere test integrazione plan/build",
            "Eseguire swift test",
        ])

        let result = buildPlanExecutionPrompt(
            workflowInstructions: "WF",
            executionPlanBase: "**Piano:**\n\(chosen)",
            planTodos: extractedTodos,
            canonicalTodos: []
        )
        XCTAssertFalse(result.isResume)
        XCTAssertTrue(result.prompt.contains("Todo da completare (in ordine):"))
        XCTAssertTrue(result.prompt.contains("1. Aggiungere test integrazione plan/build"))
        XCTAssertTrue(result.prompt.contains("2. Eseguire swift test"))
        XCTAssertFalse(result.prompt.contains("Todo già completati"))
    }

    func testResumeFlowReusesCanonicalTodosAndBuildsResumePrompt() {
        let store = TodoStore()
        let planTodos = [
            "Creare test integrazione percorso completo",
            "Eseguire swift test"
        ]
        store.upsertCanonicalPlanTodos(planTodos)
        let initialCanonicalByTitle = Dictionary(
            uniqueKeysWithValues: store.todos
                .filter(\.isPlanCanonical)
                .map { ($0.title, $0.id) }
        )

        store.upsertFromAgent(
            id: nil,
            title: "Creare test integrazione percorso completo",
            status: .done,
            priority: .high,
            notes: "completato",
            linkedFiles: []
        )
        store.upsertCanonicalPlanTodos(planTodos)

        let canonicalAfter = store.todos.filter(\.isPlanCanonical)
        let afterByTitle = Dictionary(uniqueKeysWithValues: canonicalAfter.map { ($0.title, $0.id) })
        XCTAssertEqual(initialCanonicalByTitle, afterByTitle)
        XCTAssertTrue(isPlanResumeBuild(canonicalTodos: canonicalAfter))

        let result = buildPlanExecutionPrompt(
            workflowInstructions: "WF",
            executionPlanBase: "**Piano:**\nOpzione scelta",
            planTodos: planTodos,
            canonicalTodos: canonicalAfter
        )
        XCTAssertTrue(result.isResume)
        XCTAssertTrue(result.prompt.contains("**RIPRESA IMPLEMENTAZIONE**"))
        XCTAssertTrue(result.prompt.contains("- [x] Creare test integrazione percorso completo"))
        XCTAssertTrue(result.prompt.contains("- [ ] Eseguire swift test"))
    }

    func testExecutionPromptDoesNotCreateRedundantTodoListDuringResume() {
        let now = Date()
        let canonicalTodos = [
            TodoItem(
                title: "Task completato",
                status: .done,
                source: .agent,
                createdAt: now.addingTimeInterval(-100),
                updatedAt: now.addingTimeInterval(-50),
                isPlanCanonical: true
            ),
            TodoItem(
                title: "Task aperto",
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
            planTodos: ["Task completato", "Task aperto"],
            canonicalTodos: canonicalTodos
        )

        XCTAssertTrue(result.isResume)
        XCTAssertFalse(result.prompt.contains("Todo da completare (in ordine):"))
        XCTAssertTrue(result.prompt.contains("**Todo già completati:**"))
        XCTAssertTrue(result.prompt.contains("**Todo da completare:**"))
    }
}
