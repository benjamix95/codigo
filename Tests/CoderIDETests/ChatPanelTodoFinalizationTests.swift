import XCTest
@testable import CoderIDE

final class ChatPanelTodoFinalizationTests: XCTestCase {
    func testAutoTodoFinalStatusIsDoneOnlyOnSuccess() {
        XCTAssertEqual(autoTodoFinalStatus(for: .success), .done)
        XCTAssertEqual(autoTodoFinalStatus(for: .failed), .blocked)
        XCTAssertEqual(autoTodoFinalStatus(for: .aborted), .blocked)
    }

    func testToolTraceTurnOutcomeMapsFlowCoordinatorState() {
        XCTAssertEqual(toolTraceTurnOutcome(for: .idle), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .streaming), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .delegatedSwarm), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .followUp), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .completed), .success)
        XCTAssertEqual(toolTraceTurnOutcome(for: .error), .failed)
        XCTAssertEqual(toolTraceTurnOutcome(for: .interrupted), .aborted)
    }
}
