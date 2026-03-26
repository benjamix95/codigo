import XCTest
@testable import CoderEngine

final class PipelineJobFactoryPlanBuildTests: XCTestCase {
    func testFromPlanBuildSequentialDependenciesByDefault() {
        let todos = [
            PlanTodoItem(title: "Step A"),
            PlanTodoItem(title: "Step B"),
        ]
        let (_, tasks) = PipelineJobFactory.fromPlanBuild(
            todos: todos,
            workspace: "/tmp/ws",
            providerId: "codex-cli"
        )
        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks[0].dependsOn.isEmpty)
        XCTAssertEqual(tasks[1].dependsOn, [tasks[0].taskId])
    }

    func testFromPlanBuildParallelStepsNoCrossDependencies() {
        let todos = [
            PlanTodoItem(title: "Step A"),
            PlanTodoItem(title: "Step B"),
        ]
        let (_, tasks) = PipelineJobFactory.fromPlanBuild(
            todos: todos,
            workspace: "/tmp/ws",
            providerId: "codex-cli",
            sequentialPlanSteps: false
        )
        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks[0].dependsOn.isEmpty)
        XCTAssertTrue(tasks[1].dependsOn.isEmpty)
    }
}
