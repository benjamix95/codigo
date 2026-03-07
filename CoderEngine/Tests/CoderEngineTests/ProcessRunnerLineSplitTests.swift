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

    func testRunCollectingTerminatesProcessOnCancellation() async throws {
        let completion = expectation(description: "cancelled")

        let task = Task {
            try await ProcessRunner.runCollecting(
                executable: "/bin/sh",
                arguments: ["-c", "while true; do echo still-running; sleep 1; done"]
            )
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            completion.fulfill()
        } catch {
            XCTFail("Expected CancellationError, got: \(error)")
        }

        await fulfillment(of: [completion], timeout: 5.0)
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

    func testRunInfersAuthFailureMessageFromStdoutWhenStderrIsEmpty() async throws {
        let json = #"{"type":"result","is_error":true,"result":"Not logged in · Please run /login"}"#
        let stream = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s\\n' '\(json)'; exit 1"]
        )

        do {
            for try await _ in stream {}
            XCTFail("Expected ProcessRunnerError")
        } catch let error as ProcessRunner.ProcessRunnerError {
            XCTAssertEqual(error.exitCode, 1)
            XCTAssertEqual(error.message, "Not logged in · Please run /login")
            XCTAssertTrue(error.stdoutTail?.contains("Not logged in · Please run /login") == true)
        } catch {
            XCTFail("Expected ProcessRunnerError, got: \(error)")
        }
    }
}
