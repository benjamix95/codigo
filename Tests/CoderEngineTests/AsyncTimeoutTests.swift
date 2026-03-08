import XCTest
@testable import CoderEngine

final class AsyncTimeoutTests: XCTestCase {
    func testRunReturnsValueWhenOperationCompletesInTime() async throws {
        let value = try await AsyncTimeout.run(
            seconds: 1,
            operationName: "quick-op"
        ) {
            "done"
        }

        XCTAssertEqual(value, "done")
    }

    func testRunThrowsTimeoutErrorWhenOperationRunsTooLong() async {
        do {
            _ = try await AsyncTimeout.run(
                seconds: 1,
                operationName: "slow-op"
            ) {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "late"
            }
            XCTFail("Expected timeout error")
        } catch let error as AsyncTimeoutError {
            XCTAssertEqual(error, AsyncTimeoutError(operationName: "slow-op", seconds: 1))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
