import XCTest
@testable import CoderEngine

final class AgentNameAssignerTests: XCTestCase {

    // MARK: - Basic Naming

    func testBasicNaming() async {
        let assigner = AgentNameAssigner()
        let task = TaskNode(
            taskId: "T1",
            title: "Refactor parser lock handling",
            taskLabel: "RefactorParserLock"
        )

        let name = await assigner.assign(task: task, role: .explorer)
        XCTAssertEqual(name, "RefactorParserLock-explorer")
    }

    func testMultipleRolesForSameTask() async {
        let assigner = AgentNameAssigner()
        let task = TaskNode(
            taskId: "T1",
            title: "Fix auth token",
            taskLabel: "FixAuthToken"
        )

        let explorer = await assigner.assign(task: task, role: .explorer)
        let coder = await assigner.assign(task: task, role: .coder)
        let reviewer = await assigner.assign(task: task, role: .reviewer)

        XCTAssertEqual(explorer, "FixAuthToken-explorer")
        XCTAssertEqual(coder, "FixAuthToken-coder")
        XCTAssertEqual(reviewer, "FixAuthToken-reviewer")
    }

    func testMultipleSameRoleGetsIndex() async {
        let assigner = AgentNameAssigner()
        let task = TaskNode(
            taskId: "T1",
            title: "Big feature",
            taskLabel: "BigFeature"
        )

        let e1 = await assigner.assign(task: task, role: .explorer)
        let e2 = await assigner.assign(task: task, role: .explorer)
        let e3 = await assigner.assign(task: task, role: .explorer)

        XCTAssertEqual(e1, "BigFeature-explorer")
        XCTAssertEqual(e2, "BigFeature-explorer-2")
        XCTAssertEqual(e3, "BigFeature-explorer-3")
    }

    // MARK: - Label Derivation

    func testDeriveLabelFromTitle() async {
        let assigner = AgentNameAssigner()
        let task = TaskNode(
            taskId: "T2",
            title: "Add payment webhook endpoint"
        )

        let name = await assigner.assign(task: task, role: .coder)
        XCTAssertTrue(name.hasPrefix("AddPaymentWebhookEndpoint-"))
    }

    func testDeriveLabelTruncation() {
        let label = AgentNameAssigner.deriveLabel(
            from: "This is a very long title that should be truncated properly for the pipeline"
        )
        XCTAssertLessThanOrEqual(label.count, 30)
    }

    // MARK: - Query

    func testIsAssigned() async {
        let assigner = AgentNameAssigner()
        let task = TaskNode(taskId: "T1", title: "Test", taskLabel: "Test")

        _ = await assigner.assign(task: task, role: .explorer)
        let check = await assigner.isAssigned("Test-explorer")
        XCTAssertTrue(check)
        let check2 = await assigner.isAssigned("Test-coder")
        XCTAssertFalse(check2)
    }

    func testCountForRole() async {
        let assigner = AgentNameAssigner()
        let task = TaskNode(taskId: "T1", title: "Test", taskLabel: "Test")

        _ = await assigner.assign(task: task, role: .explorer)
        _ = await assigner.assign(task: task, role: .explorer)

        let count = await assigner.countForRole(.explorer, taskId: "T1")
        XCTAssertEqual(count, 2)
    }

    // MARK: - Reset

    func testReset() async {
        let assigner = AgentNameAssigner()
        let task = TaskNode(taskId: "T1", title: "Test", taskLabel: "Test")
        _ = await assigner.assign(task: task, role: .explorer)

        await assigner.reset()
        let names = await assigner.allAssignedNames
        XCTAssertTrue(names.isEmpty)
    }
}
