import XCTest
@testable import CoderIDE

final class SwarmDelegationPolicyEvaluatorTests: XCTestCase {
    private let evaluator = SwarmDelegationPolicyEvaluator()

    func testNoDelegateWhenModeIsNotAgent() {
        let result = evaluator.evaluate(
            userPrompt: "Risolvi questo bug",
            suggestedTask: "coder: correggi bug",
            isAutoDelegateEnabled: true,
            mode: .plan
        )

        XCTAssertEqual(result.decision, .noDelegate)
    }

    func testNoDelegateWhenAutoDelegateDisabled() {
        let result = evaluator.evaluate(
            userPrompt: "Implementa questa feature",
            suggestedTask: "planner + coder + reviewer",
            isAutoDelegateEnabled: false,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .noDelegate)
    }

    func testAutoDelegateForExplicitSwarmRequest() {
        let result = evaluator.evaluate(
            userPrompt: "Usa swarm e parallelizza questo lavoro",
            suggestedTask: "qualsiasi task",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .autoDelegate)
    }

    func testAutoDelegateForMultiRoleTask() {
        let result = evaluator.evaluate(
            userPrompt: "Implementa la feature",
            suggestedTask:
                "Coinvolgi coder per implementazione, reviewer per review tecnica e testWriter per test articolati",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .autoDelegate)
    }

    func testNoDelegateForSimpleSingleGoalTask() {
        let result = evaluator.evaluate(
            userPrompt: "Rinomina una variabile in un file",
            suggestedTask: "Aggiorna il nome della variabile in Sources/A.swift",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .noDelegate)
    }

    func testNoDelegateForAmbiguousTaskWithoutParallelism() {
        let result = evaluator.evaluate(
            userPrompt: "Migliora questo pezzo di codice",
            suggestedTask: "Fai una piccola pulizia e sistema stile",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .noDelegate)
    }
}
