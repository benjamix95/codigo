import XCTest
@testable import CoderEngine

final class ProcessSupervisorTests: XCTestCase {
    func testRunCollectingSyncCapturesStdoutAndStderr() throws {
        let result = try ProcessSupervisor.runCollectingSync(
            executable: "/bin/sh",
            arguments: ["-lc", "printf 'out'; printf 'err' >&2"]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.stdout, "out")
        XCTAssertEqual(result.stderr, "err")
        XCTAssertFalse(result.metrics.timedOut)
        XCTAssertGreaterThanOrEqual(result.metrics.durationMs, 0)
    }

    func testRunCollectingSyncTerminatesOnTimeout() {
        XCTAssertThrowsError(
            try ProcessSupervisor.runCollectingSync(
                executable: "/bin/sh",
                arguments: ["-lc", "sleep 5"],
                timeout: 0.1
            )
        ) { error in
            guard case ProcessSupervisorError.timedOut = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRunCollectingAsyncCapturesMetrics() async throws {
        let result = try await ProcessSupervisor.runCollecting(
            executable: "/bin/sh",
            arguments: ["-lc", "printf fast-path"]
        )

        XCTAssertEqual(result.stdout, "fast-path")
        XCTAssertGreaterThanOrEqual(result.metrics.stdoutBytes, 1)
        XCTAssertGreaterThanOrEqual(result.metrics.durationMs, 0)
    }
}
