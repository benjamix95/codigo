import XCTest
@testable import CoderIDE

@MainActor
final class TaskActivityPanelInstantGrepSnapshotTests: XCTestCase {
    func testInstantGrepSnapshotUsesDeduplicatedCardsAndPanelLimit() {
        let store = TaskActivityStore()

        store.addInstantGrep(makeResult(query: "auth flow", scope: "Sources, Tests", count: 1, preview: "old-hit"))
        store.addInstantGrep(makeResult(query: "q2", scope: "Sources", count: 2, preview: "q2-hit"))
        store.addInstantGrep(makeResult(query: "q3", scope: "Sources", count: 3, preview: "q3-hit"))
        store.addInstantGrep(makeResult(query: "q4", scope: "Sources", count: 4, preview: "q4-hit"))
        store.addInstantGrep(makeResult(query: "q5", scope: "Sources", count: 5, preview: "q5-hit"))
        store.addInstantGrep(makeResult(query: " AUTH FLOW ", scope: "tests,sources", count: 7, preview: "fresh-hit"))

        let snapshot = InstantGrepCardsView.snapshotCards(from: store.instantGreps)
        XCTAssertEqual(snapshot.count, 4, "La UI deve mostrare massimo 4 card")
        XCTAssertEqual(snapshot.map(\.query), [" AUTH FLOW ", "q5", "q4", "q3"])
        XCTAssertEqual(snapshot.first?.scope, "tests,sources")
        XCTAssertEqual(snapshot.first?.matchesCount, 7)
        XCTAssertEqual(snapshot.first?.visibleMatches, ["Auth.swift:12 fresh-hit"])

        let serialized = serialize(snapshot)
        XCTAssertEqual(
            serialized,
            """
            1.  AUTH FLOW  | tests,sources | 7 | Auth.swift:12 fresh-hit
            2. q5 | Sources | 5 | Auth.swift:12 q5-hit
            3. q4 | Sources | 4 | Auth.swift:12 q4-hit
            4. q3 | Sources | 3 | Auth.swift:12 q3-hit
            """
        )
    }

    private func makeResult(
        query: String,
        scope: String,
        count: Int,
        preview: String
    ) -> InstantGrepResult {
        InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: count,
            matches: [InstantGrepMatch(file: "Sources/Auth.swift", line: 12, preview: preview)],
            createdAt: Date()
        )
    }

    private func serialize(_ snapshot: [InstantGrepCardSnapshot]) -> String {
        snapshot.enumerated().map { index, card in
            let matches = card.visibleMatches.joined(separator: " || ")
            return "\(index + 1). \(card.query) | \(card.scope) | \(card.matchesCount) | \(matches)"
        }.joined(separator: "\n")
    }
}
