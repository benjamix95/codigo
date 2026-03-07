import XCTest
@testable import CoderEngine

final class ExecutionControllerTerminationTests: XCTestCase {
    func testEndScopeTransitionsToIdleWhenNoRunningProcess() {
        let controller = ExecutionController()

        controller.beginScope(.review)
        XCTAssertEqual(controller.activeScope, .review)
        XCTAssertEqual(controller.runState, .running)

        controller.endScope(.review)
        XCTAssertNil(controller.activeScope)
        XCTAssertEqual(controller.runState, .idle)
    }

    func testTerminateScopeKeepsStoppingStateUntilClearCurrentProcess() throws {
        let controller = ExecutionController()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 5"]
        try process.run()

        controller.beginScope(.agent)
        controller.setCurrentProcess(process)
        XCTAssertEqual(controller.runState, .running)

        controller.terminate(scope: .agent)
        XCTAssertEqual(controller.runState, .stopping)

        process.waitUntilExit()
        controller.clearCurrentProcess()
        XCTAssertEqual(controller.runState, .idle)
    }

    func testClearCurrentProcessRestoresPreviouslyTrackedProcess() {
        let controller = ExecutionController()
        let parentProcess = Process()
        let nestedProcess = Process()

        controller.beginScope(.agent)
        controller.setCurrentProcess(parentProcess)
        controller.beginScope(.review)
        controller.setCurrentProcess(nestedProcess)

        controller.clearCurrentProcess(nestedProcess)

        XCTAssertEqual(controller.activeScope, .review)
        XCTAssertEqual(controller.runState, .running)

        controller.clearCurrentProcess(parentProcess)
        XCTAssertNil(controller.activeScope)
        XCTAssertEqual(controller.runState, .idle)
    }

}
