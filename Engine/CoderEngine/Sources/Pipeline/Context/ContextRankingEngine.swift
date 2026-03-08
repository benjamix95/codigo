import Foundation

// MARK: - ContextItem

/// Singolo elemento di contesto candidato per il ranking.
public struct ContextItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let filePath: String
    public let symbolName: String?
    public let semanticScore: Double
    public let callGraphScore: Double
    public let dependencyScore: Double
    public let recencyScore: Double
    public let tokenCount: Int

    public init(
        id: String,
        filePath: String,
        symbolName: String? = nil,
        semanticScore: Double = 0,
        callGraphScore: Double = 0,
        dependencyScore: Double = 0,
        recencyScore: Double = 0,
        tokenCount: Int = 0
    ) {
        self.id = id
        self.filePath = filePath
        self.symbolName = symbolName
        self.semanticScore = semanticScore
        self.callGraphScore = callGraphScore
        self.dependencyScore = dependencyScore
        self.recencyScore = recencyScore
        self.tokenCount = tokenCount
    }
}

// MARK: - RankedContextItem

/// Elemento di contesto con il suo score calcolato.
public struct RankedContextItem: Sendable, Equatable {
    public let item: ContextItem
    public let score: Double

    public init(item: ContextItem, score: Double) {
        self.item = item
        self.score = score
    }
}

// MARK: - ContextRankingEngine

/// Motore di ranking del contesto con pesi adattivi per task_type (§8.3).
///
/// Formula:
/// ```
/// context_score = semantic_score * W_semantic
///               + call_graph_score * W_call_graph
///               + dependency_score * W_dependency
///               + recency_score * W_recency
/// ```
public struct ContextRankingEngine: Sendable {

    public let weightProfile: ContextWeightProfile

    public init(weightProfile: ContextWeightProfile = ContextWeightProfile()) {
        self.weightProfile = weightProfile
    }

    // MARK: - Scoring

    /// Calcola lo score di un singolo item in base al task_type.
    public func score(
        item: ContextItem,
        taskType: TaskType
    ) -> Double {
        let w = weightProfile.weights(for: taskType)
        return item.semanticScore * w.semantic
            + item.callGraphScore * w.callGraph
            + item.dependencyScore * w.dependency
            + item.recencyScore * w.recency
    }

    // MARK: - Ranking

    /// Ordina gli item per score decrescente.
    public func rank(
        items: [ContextItem],
        taskType: TaskType
    ) -> [RankedContextItem] {
        items
            .map { RankedContextItem(
                item: $0,
                score: score(item: $0, taskType: taskType)
            )}
            .sorted { $0.score > $1.score }
    }

    /// Seleziona i top-N item per score, con filtro opzionale di threshold.
    public func selectTop(
        from items: [ContextItem],
        taskType: TaskType,
        limit: Int = 20,
        minScore: Double = 0
    ) -> [RankedContextItem] {
        let ranked = rank(items: items, taskType: taskType)
        return Array(
            ranked
                .filter { $0.score >= minScore }
                .prefix(limit)
        )
    }

    /// Seleziona item fino a un budget massimo di token.
    public func selectWithinBudget(
        from items: [ContextItem],
        taskType: TaskType,
        tokenBudget: Int
    ) -> [RankedContextItem] {
        let ranked = rank(items: items, taskType: taskType)
        var remaining = tokenBudget
        var selected: [RankedContextItem] = []
        for r in ranked {
            if r.item.tokenCount <= remaining {
                selected.append(r)
                remaining -= r.item.tokenCount
            }
            if remaining <= 0 { break }
        }
        return selected
    }
}
