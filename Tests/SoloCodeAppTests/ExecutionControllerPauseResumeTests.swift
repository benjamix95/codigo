import XCTest
import CoderEngine

final class ExecutionControllerPauseResumeTests: XCTestCase {
    func testPauseResumeWithoutProcessIsNoop() {
        let controller = ExecutionController()
        XCTAssertEqual(controller.runState, .idle)
        XCTAssertFalse(controller.swarmPauseRequested)
        XCTAssertFalse(controller.swarmStopRequested)

        controller.pause(scope: .agent)
        XCTAssertEqual(controller.runState, .idle)
        XCTAssertFalse(controller.swarmPauseRequested)
        XCTAssertFalse(controller.swarmStopRequested)

        controller.resume(scope: .agent)
        XCTAssertEqual(controller.runState, .idle)
        XCTAssertFalse(controller.swarmPauseRequested)
        XCTAssertFalse(controller.swarmStopRequested)
    }

    func testScopeLifecycleTransitionsRunState() {
        let controller = ExecutionController()
        controller.beginScope(.swarm)
        XCTAssertEqual(controller.runState, .running)

        controller.pause(scope: .swarm)
        XCTAssertEqual(controller.runState, .paused)
        XCTAssertTrue(controller.swarmPauseRequested)

        controller.resume(scope: .swarm)
        XCTAssertEqual(controller.runState, .running)

        controller.terminate(scope: .swarm)
        XCTAssertEqual(controller.runState, .idle)
        XCTAssertTrue(controller.swarmStopRequested)
    }
}
