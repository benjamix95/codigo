import Foundation

// MARK: - ContextWeights

/// Pesi individuali per il ranking del contesto (§8.3).
public struct ContextWeights: Codable, Sendable, Equatable {
    public var semantic: Double
    public var callGraph: Double
    public var dependency: Double
    public var recency: Double

    public init(
        semantic: Double,
        callGraph: Double,
        dependency: Double,
        recency: Double
    ) {
        self.semantic = semantic
        self.callGraph = callGraph
        self.dependency = dependency
        self.recency = recency
    }

    enum CodingKeys: String, CodingKey {
        case semantic = "W_semantic"
        case callGraph = "W_call_graph"
        case dependency = "W_dependency"
        case recency = "W_recency"
    }

    /// Verifica che i pesi sommino a 1.0 (±tolleranza).
    public var isNormalized: Bool {
        let sum = semantic + callGraph + dependency + recency
        return abs(sum - 1.0) < 0.001
    }

    /// Normalizza i pesi in modo che sommino a 1.0.
    public mutating func normalize() {
        let sum = semantic + callGraph + dependency + recency
        guard sum > 0 else { return }
        semantic /= sum
        callGraph /= sum
        dependency /= sum
        recency /= sum
    }
}

// MARK: - ContextWeightProfile

/// Profili peso configurabili per task_type (§8.3).
///
/// Profili di default dalla specifica:
/// | Peso         | feature | bugfix | refactor | test | docs |
/// |-------------|---------|--------|----------|------|------|
/// | W_semantic  | 0.40    | 0.20   | 0.30     | 0.25 | 0.50 |
/// | W_call_graph| 0.25    | 0.40   | 0.35     | 0.30 | 0.10 |
/// | W_dependency| 0.25    | 0.15   | 0.25     | 0.20 | 0.15 |
/// | W_recency   | 0.10    | 0.25   | 0.10     | 0.25 | 0.25 |
public struct ContextWeightProfile: Codable, Sendable, Equatable {

    public var profiles: [TaskType: ContextWeights]

    public init(profiles: [TaskType: ContextWeights]? = nil) {
        self.profiles = profiles ?? Self.defaultProfiles
    }

    /// Restituisce i pesi per un dato task_type, con fallback ai default.
    public func weights(for taskType: TaskType) -> ContextWeights {
        profiles[taskType] ?? Self.defaultProfiles[taskType]
            ?? Self.fallbackWeights
    }

    /// Override di un profilo specifico.
    public mutating func setWeights(
        _ weights: ContextWeights,
        for taskType: TaskType
    ) {
        profiles[taskType] = weights
    }

    // MARK: - Default Profiles (§8.3)

    public static let defaultProfiles: [TaskType: ContextWeights] = [
        .feature: ContextWeights(
            semantic: 0.40, callGraph: 0.25,
            dependency: 0.25, recency: 0.10
        ),
        .bugfix: ContextWeights(
            semantic: 0.20, callGraph: 0.40,
            dependency: 0.15, recency: 0.25
        ),
        .refactor: ContextWeights(
            semantic: 0.30, callGraph: 0.35,
            dependency: 0.25, recency: 0.10
        ),
        .test: ContextWeights(
            semantic: 0.25, callGraph: 0.30,
            dependency: 0.20, recency: 0.25
        ),
        .docs: ContextWeights(
            semantic: 0.50, callGraph: 0.10,
            dependency: 0.15, recency: 0.25
        ),
    ]

    static let fallbackWeights = ContextWeights(
        semantic: 0.25, callGraph: 0.25,
        dependency: 0.25, recency: 0.25
    )
}
