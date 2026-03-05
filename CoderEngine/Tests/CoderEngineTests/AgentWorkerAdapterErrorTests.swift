import XCTest
@testable import CoderEngine

final class AgentWorkerAdapterErrorTests: XCTestCase {
    func testStreamErrorUsesReadableLocalizedDescription() {
        let error = AgentWorkerError.streamError("Subagent backend non disponibile")

        XCTAssertEqual(
            error.localizedDescription,
            "Subagent backend non disponibile"
        )
    }

    func testTimeoutUsesReadableLocalizedDescription() {
        let error = AgentWorkerError.timeout(
            taskId: "task_123",
            elapsedMs: 5_000
        )

        XCTAssertEqual(
            error.localizedDescription,
            "Timeout del worker pipeline per task_123 dopo 5000ms."
        )
    }
}
