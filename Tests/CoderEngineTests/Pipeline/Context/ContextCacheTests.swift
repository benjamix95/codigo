import XCTest
@testable import CoderEngine

final class ContextCacheTests: XCTestCase {

    private func makeBundle(tokens: Int = 100) -> ContextBundle {
        ContextBundle(items: [], totalTokens: tokens)
    }

    // MARK: - Basic Operations

    func testPutAndGet() async {
        let cache = ContextCache()
        await cache.put("k1", bundle: makeBundle())
        let result = await cache.get("k1")
        XCTAssertNotNil(result)
    }

    func testGet_miss_returnsNil() async {
        let cache = ContextCache()
        let result = await cache.get("nonexistent")
        XCTAssertNil(result)
    }

    func testGet_updatesHitCount() async {
        let cache = ContextCache()
        await cache.put("k1", bundle: makeBundle())
        _ = await cache.get("k1")
        _ = await cache.get("k1")
        let rate = await cache.hitRate()
        XCTAssertGreaterThan(rate, 0)
    }

    // MARK: - LRU Eviction

    func testLRU_evictsOldest_whenFull() async {
        let config = ContextCacheConfig(maxEntries: 2)
        let cache = ContextCache(config: config)
        await cache.put("k1", bundle: makeBundle())
        await cache.put("k2", bundle: makeBundle())
        await cache.put("k3", bundle: makeBundle())
        let size = await cache.size()
        XCTAssertEqual(size, 2)
        let k1 = await cache.get("k1")
        XCTAssertNil(k1, "k1 should have been evicted")
    }

    func testLRU_preservesRecentlyAccessed() async {
        let config = ContextCacheConfig(maxEntries: 2)
        let cache = ContextCache(config: config)
        await cache.put("k1", bundle: makeBundle())
        await cache.put("k2", bundle: makeBundle())
        _ = await cache.get("k1")
        await cache.put("k3", bundle: makeBundle())
        let k1 = await cache.get("k1")
        XCTAssertNotNil(k1, "k1 was recently accessed, should survive")
    }

    // MARK: - TTL Expiration

    func testGet_ttlExpired_returnsNil() async throws {
        let config = ContextCacheConfig(ttlMs: 50)
        let cache = ContextCache(config: config)
        await cache.put("k1", bundle: makeBundle())
        try await Task.sleep(nanoseconds: 80_000_000)
        let result = await cache.get("k1")
        XCTAssertNil(result)
    }

    // MARK: - Invalidation

    func testInvalidate_removesEntry() async {
        let cache = ContextCache()
        await cache.put("k1", bundle: makeBundle())
        await cache.invalidate("k1")
        let result = await cache.get("k1")
        XCTAssertNil(result)
    }

    func testInvalidateAsPoisoning_removesEntry() async {
        let cache = ContextCache()
        await cache.put("k1", bundle: makeBundle())
        await cache.invalidateAsPoisoning("k1")
        let result = await cache.get("k1")
        XCTAssertNil(result)
    }

    // MARK: - Periodic Cleanup

    func testPeriodicCleanup_emptyCache_doesNotCrash() async {
        let cache = ContextCache()
        await cache.periodicCleanup()
        let size = await cache.size()
        XCTAssertEqual(size, 0)
    }

    func testPeriodicCleanup_removesTTLExpired() async throws {
        let config = ContextCacheConfig(ttlMs: 50)
        let cache = ContextCache(config: config)
        await cache.put("k1", bundle: makeBundle())
        try await Task.sleep(nanoseconds: 80_000_000)
        await cache.periodicCleanup()
        let size = await cache.size()
        XCTAssertEqual(size, 0)
    }

    // MARK: - Metrics

    func testHitRate_computesCorrectly() async {
        let cache = ContextCache()
        await cache.put("k1", bundle: makeBundle())
        _ = await cache.get("k1")
        _ = await cache.get("k1")
        _ = await cache.get("miss")
        let rate = await cache.hitRate()
        XCTAssertEqual(rate, 2.0 / 3.0, accuracy: 0.01)
    }

    func testHitRate_zeroWhenEmpty() async {
        let cache = ContextCache()
        let rate = await cache.hitRate()
        XCTAssertEqual(rate, 0)
    }

    func testEvictionCount_increments() async {
        let config = ContextCacheConfig(maxEntries: 1)
        let cache = ContextCache(config: config)
        await cache.put("k1", bundle: makeBundle())
        await cache.put("k2", bundle: makeBundle())
        let evictions = await cache.evictionCount()
        XCTAssertEqual(evictions, 1)
    }

    // MARK: - Task Signature

    func testTaskSignature_deterministicForSameInput() {
        let sig1 = ContextCache.taskSignature(
            fileScope: ["a.swift", "b.swift"],
            symbolScope: ["Foo"],
            taskType: .feature,
            commitSha: "abc123"
        )
        let sig2 = ContextCache.taskSignature(
            fileScope: ["b.swift", "a.swift"],
            symbolScope: ["Foo"],
            taskType: .feature,
            commitSha: "abc123"
        )
        XCTAssertEqual(sig1, sig2, "Order should not matter")
    }

    func testTaskSignature_differentForDifferentInput() {
        let sig1 = ContextCache.taskSignature(
            fileScope: ["a.swift"],
            symbolScope: ["Foo"],
            taskType: .feature,
            commitSha: "abc"
        )
        let sig2 = ContextCache.taskSignature(
            fileScope: ["a.swift"],
            symbolScope: ["Foo"],
            taskType: .bugfix,
            commitSha: "abc"
        )
        XCTAssertNotEqual(sig1, sig2)
    }

    // MARK: - Reset

    func testReset_clearsAll() async {
        let cache = ContextCache()
        await cache.put("k1", bundle: makeBundle())
        await cache.reset()
        let size = await cache.size()
        XCTAssertEqual(size, 0)
    }
}
