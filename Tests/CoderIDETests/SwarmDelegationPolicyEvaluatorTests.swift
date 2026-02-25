import XCTest
@testable import CoderIDE

final class SwarmDelegationPolicyEvaluatorTests: XCTestCase {
    private let evaluator = SwarmDelegationPolicyEvaluator()

    func testNoDelegateWhenModeIsNotAgent() {
        let result = evaluator.evaluate(
            userPrompt: "Fix this bug",
            suggestedTask: "coder: fix bug",
            isAutoDelegateEnabled: true,
            mode: .plan
        )

        XCTAssertEqual(result.decision, .noDelegate)
    }

    func testNoDelegateWhenAutoDelegateDisabled() {
        let result = evaluator.evaluate(
            userPrompt: "Implement this feature",
            suggestedTask: "planner + coder + reviewer",
            isAutoDelegateEnabled: false,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .noDelegate)
    }

    func testAutoDelegateForExplicitSwarmRequest() {
        let result = evaluator.evaluate(
            userPrompt: "Use swarm and parallelize this work",
            suggestedTask: "any task",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .autoDelegate)
    }

    func testAutoDelegateForExplicitSwamAliasRequest() {
        let result = evaluator.evaluate(
            userPrompt: "Use swam and parallelize this work",
            suggestedTask: "any task",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .autoDelegate)
    }

    func testAutoDelegateForMultiRoleTask() {
        let result = evaluator.evaluate(
            userPrompt: "Implement the feature",
            suggestedTask:
                "Involve coder for implementation, reviewer for technical review, and test writer for advanced testing",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .autoDelegate)
    }

    func testNoDelegateForSimpleSingleGoalTask() {
        let result = evaluator.evaluate(
            userPrompt: "Rename one variable in a file",
            suggestedTask: "Update the variable name in Sources/A.swift",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .noDelegate)
    }

    func testNoDelegateForAmbiguousTaskWithoutParallelism() {
        let result = evaluator.evaluate(
            userPrompt: "Improve this code section",
            suggestedTask: "Do a small cleanup and style fixes",
            isAutoDelegateEnabled: true,
            mode: .agent
        )

        XCTAssertEqual(result.decision, .noDelegate)
    }
}
