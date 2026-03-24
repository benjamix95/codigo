import XCTest
@testable import CoderEngine

final class RequestDeduplicatorTests: XCTestCase {

    // MARK: - Basic Deduplication

    func testDeduplicated_returnsSameResultForConcurrentCalls() async throws {
        let dedup = RequestDeduplicator<String, Int>()
        var executionCount = 0
        let lock = NSLock()

        async let result1 = dedup.deduplicated(key: "k") {
            lock.withLock { executionCount += 1 }
            try await Task.sleep(nanoseconds: 50_000_000)
            return 42
        }
        async let result2 = dedup.deduplicated(key: "k") {
            lock.withLock { executionCount += 1 }
            try await Task.sleep(nanoseconds: 50_000_000)
            return 99
        }

        let (r1, r2) = try await (result1, result2)
        XCTAssertEqual(r1, 42)
        XCTAssertEqual(r2, 42)
        XCTAssertEqual(executionCount, 1, "Work should execute only once for same key")
    }

    func testDeduplicated_differentKeysRunIndependently() async throws {
        let dedup = RequestDeduplicator<String, String>()

        async let a = dedup.deduplicated(key: "a") { "alpha" }
        async let b = dedup.deduplicated(key: "b") { "beta" }

        let (resultA, resultB) = try await (a, b)
        XCTAssertEqual(resultA, "alpha")
        XCTAssertEqual(resultB, "beta")
    }

    func testDeduplicated_sameKeyAfterCompletion_executesAgain() async throws {
        let dedup = RequestDeduplicator<String, Int>()
        var counter = 0
        let lock = NSLock()

        _ = try await dedup.deduplicated(key: "k") {
            lock.withLock { counter += 1 }
            return counter
        }
        _ = try await dedup.deduplicated(key: "k") {
            lock.withLock { counter += 1 }
            return counter
        }

        XCTAssertEqual(counter, 2, "After first completes, second should run fresh")
    }

    // MARK: - Error Propagation

    func testDeduplicated_propagatesError() async {
        let dedup = RequestDeduplicator<String, Int>()

        do {
            _ = try await dedup.deduplicated(key: "err") {
                throw URLError(.badServerResponse)
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testDeduplicated_cleansUpAfterError_allowsRetry() async throws {
        let dedup = RequestDeduplicator<String, Int>()

        // Prima chiamata: errore
        _ = try? await dedup.deduplicated(key: "k") {
            throw URLError(.timedOut)
        }

        // Seconda chiamata: successo (entry non rimasta bloccata)
        let result = try await dedup.deduplicated(key: "k") { 42 }
        XCTAssertEqual(result, 42)
    }

    // MARK: - Invalidation

    func testInvalidate_removesInFlightTask() async throws {
        let dedup = RequestDeduplicator<String, Int>()

        let count = await dedup.inFlightCount
        XCTAssertEqual(count, 0)

        await dedup.invalidate(key: "nonexistent")
        let countAfter = await dedup.inFlightCount
        XCTAssertEqual(countAfter, 0)
    }
}
