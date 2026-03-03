import XCTest
@testable import CoderIDE

@MainActor
final class TaskActivityStoreInstantGrepTests: XCTestCase {
    func testAddInstantGrepDeduplicatesByNormalizedQueryAndScope() {
        let store = TaskActivityStore()
        store.addInstantGrep(makeResult(query: "Auth Flow", scope: "Sources", count: 1))
        store.addInstantGrep(makeResult(query: "  auth flow  ", scope: "sources ", count: 2))

        XCTAssertEqual(store.instantGreps.count, 1)
        XCTAssertEqual(store.instantGreps.first?.matchesCount, 2)
    }

    func testAddInstantGrepKeepsDistinctScopes() {
        let store = TaskActivityStore()
        store.addInstantGrep(makeResult(query: "auth flow", scope: "Sources"))
        store.addInstantGrep(makeResult(query: "auth flow", scope: "Tests"))

        XCTAssertEqual(store.instantGreps.count, 2)
    }

    func testAddInstantGrepDeduplicatesEquivalentMultiScopes() {
        let store = TaskActivityStore()
        store.addInstantGrep(makeResult(query: "auth flow", scope: "Sources, Tests", count: 1))
        store.addInstantGrep(makeResult(query: "auth flow", scope: "tests,sources", count: 4))

        XCTAssertEqual(store.instantGreps.count, 1)
        XCTAssertEqual(store.instantGreps.first?.matchesCount, 4)
    }

    func testAddInstantGrepPrunesExpiredResultsByTTL() {
        let store = TaskActivityStore()
        store.configureInstantGrepRetention(ttlSeconds: 60)

        let now = Date()
        store.addInstantGrep(
            makeResult(
                query: "stale",
                scope: "Sources",
                count: 1,
                createdAt: now.addingTimeInterval(-120)
            )
        )
        store.addInstantGrep(
            makeResult(
                query: "fresh",
                scope: "Sources",
                count: 1,
                createdAt: now
            )
        )

        XCTAssertEqual(store.instantGreps.count, 1)
        XCTAssertEqual(store.instantGreps.first?.query, "fresh")
    }

    func testConfigureInstantGrepRetentionAppliesCustomCap() {
        let store = TaskActivityStore()
        store.configureInstantGrepRetention(maxItems: 2, ttlSeconds: 3600)

        store.addInstantGrep(makeResult(query: "q1", scope: "Sources", count: 1))
        store.addInstantGrep(makeResult(query: "q2", scope: "Sources", count: 1))
        store.addInstantGrep(makeResult(query: "q3", scope: "Sources", count: 1))

        XCTAssertEqual(store.instantGreps.count, 2)
        XCTAssertEqual(store.instantGreps.map(\.query), ["q3", "q2"])
    }

    private func makeResult(query: String, scope: String, count: Int = 1, createdAt: Date = Date()) -> InstantGrepResult {
        InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: count,
            matches: [InstantGrepMatch(file: "Sources/Auth.swift", line: 12, preview: "auth")],
            createdAt: createdAt
        )
    }
}
