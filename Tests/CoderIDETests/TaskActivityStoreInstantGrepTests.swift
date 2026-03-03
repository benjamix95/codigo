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

    private func makeResult(query: String, scope: String, count: Int = 1) -> InstantGrepResult {
        InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: count,
            matches: [InstantGrepMatch(file: "Sources/Auth.swift", line: 12, preview: "auth")],
            createdAt: Date()
        )
    }
}
