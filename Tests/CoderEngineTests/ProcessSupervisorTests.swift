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
}
