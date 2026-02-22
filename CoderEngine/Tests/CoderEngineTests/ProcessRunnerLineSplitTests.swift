import XCTest
@testable import CoderEngine

final class ProcessRunnerLineSplitTests: XCTestCase {
    func testRunCollectingSplitsCarriageReturnsAndLineFeeds() async throws {
        let result = try await ProcessRunner.runCollecting(
            executable: "/usr/bin/printf",
            arguments: ["alpha\rbeta\r\ngamma\n"]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.output, ["alpha", "beta", "gamma"])
    }

    func testRunSplitsCarriageReturnsAndLineFeeds() async throws {
        let stream = try await ProcessRunner.run(
            executable: "/usr/bin/printf",
            arguments: ["one\rtwo\r\nthree\n"]
        )

        var lines: [String] = []
        for try await line in stream {
            lines.append(line)
        }

        XCTAssertEqual(lines, ["one", "two", "three"])
    }

    func testRunTreatsSigtermAsCancellation() async throws {
        let stream = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "kill -TERM $$"]
        )

        do {
            for try await _ in stream {}
            XCTFail("Expected CancellationError for SIGTERM exit")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got: \(error)")
        }
    }
}
