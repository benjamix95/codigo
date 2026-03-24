import XCTest
@testable import CoderEngine

final class OpenAIModelsFetcherTests: XCTestCase {
    override func tearDown() {
        OpenAIModelsFetcher.invalidateCache()
        super.tearDown()
    }

    // MARK: - Cache

    func testFetchModelsReturnsCachedResultOnSecondCall() async {
        // First call populates cache (may hit network or return fallback).
        let first = await OpenAIModelsFetcher.fetchModels(apiKey: "")
        XCTAssertFalse(first.isEmpty, "Should return fallback models for empty key")

        // Second call should return the same result from cache.
        let second = await OpenAIModelsFetcher.fetchModels(apiKey: "")
        XCTAssertEqual(first, second)
    }

    func testInvalidateCacheForcesRefresh() async {
        _ = await OpenAIModelsFetcher.fetchModels(apiKey: "")
        OpenAIModelsFetcher.invalidateCache()
        // After invalidation, calling again should not crash and should return models.
        let refreshed = await OpenAIModelsFetcher.fetchModels(apiKey: "")
        XCTAssertFalse(refreshed.isEmpty)
    }

    // MARK: - Fallback

    func testEmptyApiKeyReturnsFallbackModels() async {
        let models = await OpenAIModelsFetcher.fetchModels(apiKey: "")
        XCTAssertEqual(models, OpenAIModelsFetcher.fallbackModels)
    }

    // MARK: - Thundering Herd Coalescing

    func testConcurrentFetchesCoalesceIntoSingleRequest() async {
        OpenAIModelsFetcher.invalidateCache()

        // Launch many concurrent fetches — they should all coalesce.
        let results = await withTaskGroup(of: [String].self, returning: [[String]].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await OpenAIModelsFetcher.fetchModels(apiKey: "")
                }
            }
            var collected: [[String]] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // All 10 concurrent calls should return the exact same array.
        XCTAssertEqual(results.count, 10)
        let first = results[0]
        for result in results {
            XCTAssertEqual(result, first, "All concurrent fetches should return the same coalesced result")
        }
    }
}
