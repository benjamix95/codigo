import XCTest
import CoderEngine

final class ExecutionControllerScopeIsolationTests: XCTestCase {
    func testTerminateWithDifferentScopeDoesNotResetRunState() {
        let controller = ExecutionController()
        controller.beginScope(.review)
        XCTAssertEqual(controller.runState, .running)

        controller.terminate(scope: .agent)

        XCTAssertEqual(controller.runState, .running)
        XCTAssertEqual(controller.activeScope, .review)
    }
}
