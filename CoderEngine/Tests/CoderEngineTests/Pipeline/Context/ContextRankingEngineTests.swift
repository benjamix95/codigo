import XCTest
@testable import CoderEngine

final class ContextRankingEngineTests: XCTestCase {

    private func makeItem(
        id: String = "item1",
        semantic: Double = 0.5,
        callGraph: Double = 0.5,
        dependency: Double = 0.5,
        recency: Double = 0.5,
        tokens: Int = 100
    ) -> ContextItem {
        ContextItem(
            id: id, filePath: "src/\(id).swift",
            semanticScore: semantic,
            callGraphScore: callGraph,
            dependencyScore: dependency,
            recencyScore: recency,
            tokenCount: tokens
        )
    }

    // MARK: - Score Calculation

    func testScore_feature_correctWeighting() {
        let engine = ContextRankingEngine()
        let item = makeItem(
            semantic: 1.0, callGraph: 0.0,
            dependency: 0.0, recency: 0.0
        )
        let score = engine.score(item: item, taskType: .feature)
        XCTAssertEqual(score, 0.40, accuracy: 0.001)
    }

    func testScore_bugfix_callGraphDominant() {
        let engine = ContextRankingEngine()
        let item = makeItem(
            semantic: 0.0, callGraph: 1.0,
            dependency: 0.0, recency: 0.0
        )
        let score = engine.score(item: item, taskType: .bugfix)
        XCTAssertEqual(score, 0.40, accuracy: 0.001)
    }

    func testScore_allOnes_equalsOne() {
        let engine = ContextRankingEngine()
        let item = makeItem(
            semantic: 1.0, callGraph: 1.0,
            dependency: 1.0, recency: 1.0
        )
        let score = engine.score(item: item, taskType: .feature)
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testScore_allZeros_equalsZero() {
        let engine = ContextRankingEngine()
        let item = makeItem(
            semantic: 0, callGraph: 0,
            dependency: 0, recency: 0
        )
        let score = engine.score(item: item, taskType: .feature)
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    // MARK: - Ranking

    func testRank_ordersDescending() {
        let engine = ContextRankingEngine()
        let items = [
            makeItem(id: "low", semantic: 0.1),
            makeItem(id: "high", semantic: 0.9),
            makeItem(id: "mid", semantic: 0.5),
        ]
        let ranked = engine.rank(items: items, taskType: .feature)
        XCTAssertEqual(ranked.first?.item.id, "high")
        XCTAssertEqual(ranked.last?.item.id, "low")
    }

    func testRank_emptyInput_emptyOutput() {
        let engine = ContextRankingEngine()
        let ranked = engine.rank(items: [], taskType: .docs)
        XCTAssertTrue(ranked.isEmpty)
    }

    // MARK: - Select Top

    func testSelectTop_limitsCount() {
        let engine = ContextRankingEngine()
        let items = (0..<10).map {
            makeItem(id: "i\($0)", semantic: Double($0) / 10.0)
        }
        let top3 = engine.selectTop(
            from: items, taskType: .feature, limit: 3
        )
        XCTAssertEqual(top3.count, 3)
    }

    func testSelectTop_minScore_filters() {
        let engine = ContextRankingEngine()
        let items = [
            makeItem(id: "low", semantic: 0.0, callGraph: 0.0,
                     dependency: 0.0, recency: 0.0),
            makeItem(id: "high", semantic: 1.0, callGraph: 1.0,
                     dependency: 1.0, recency: 1.0),
        ]
        let top = engine.selectTop(
            from: items, taskType: .feature,
            limit: 10, minScore: 0.5
        )
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top.first?.item.id, "high")
    }

    // MARK: - Select Within Budget

    func testSelectWithinBudget_respectsTokenLimit() {
        let engine = ContextRankingEngine()
        let items = [
            makeItem(id: "a", semantic: 0.9, tokens: 500),
            makeItem(id: "b", semantic: 0.8, tokens: 400),
            makeItem(id: "c", semantic: 0.7, tokens: 300),
        ]
        let selected = engine.selectWithinBudget(
            from: items, taskType: .feature, tokenBudget: 800
        )
        let totalTokens = selected.reduce(0) { $0 + $1.item.tokenCount }
        XCTAssertLessThanOrEqual(totalTokens, 800)
        XCTAssertGreaterThanOrEqual(selected.count, 1)
    }

    func testSelectWithinBudget_zeroBudget_empty() {
        let engine = ContextRankingEngine()
        let items = [makeItem(tokens: 100)]
        let selected = engine.selectWithinBudget(
            from: items, taskType: .feature, tokenBudget: 0
        )
        XCTAssertTrue(selected.isEmpty)
    }

    // MARK: - Custom Weight Profile

    func testCustomWeightProfile_appliesCorrectly() {
        var profile = ContextWeightProfile()
        profile.setWeights(
            ContextWeights(
                semantic: 1.0, callGraph: 0.0,
                dependency: 0.0, recency: 0.0
            ),
            for: .feature
        )
        let engine = ContextRankingEngine(weightProfile: profile)
        let item = makeItem(
            semantic: 0.8, callGraph: 1.0,
            dependency: 1.0, recency: 1.0
        )
        let score = engine.score(item: item, taskType: .feature)
        XCTAssertEqual(score, 0.8, accuracy: 0.001)
    }
}
