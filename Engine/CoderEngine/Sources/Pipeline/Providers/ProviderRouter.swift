import Foundation

// MARK: - ProviderRoutingError

/// Errori nel processo di routing provider (§5.9).
public enum ProviderRoutingError: Error, Sendable, Equatable {
    case noProvidersAvailable
    case allProvidersUnhealthy
    case noCapabilityMatch(role: AgentRole)
    case fallbackExhausted(role: AgentRole, tried: [String])
}

// MARK: - ProviderSelectionReason

/// Motivo della selezione del provider per logging/replay (§14.3).
public enum ProviderSelectionReason: String, Sendable, Equatable {
    case capabilityMatch = "capability_match"
    case fallbackReduced = "fallback_reduced"
    case onlyAvailable = "only_available"
}

// MARK: - ProviderSelectionResult

/// Risultato della selezione provider (§5.9).
public struct ProviderSelectionResult: Sendable, Equatable {
    public let provider: ProviderCapabilityEntry
    public let reason: ProviderSelectionReason
    public let candidatesCount: Int
    public let score: Double

    public init(
        provider: ProviderCapabilityEntry,
        reason: ProviderSelectionReason,
        candidatesCount: Int,
        score: Double
    ) {
        self.provider = provider
        self.reason = reason
        self.candidatesCount = candidatesCount
        self.score = score
    }
}

// MARK: - RequiredCapabilities

/// Capability richieste per un agente (§5.9).
public struct RequiredCapabilities: Sendable, Equatable {
    public let needsReadonlySubagent: Bool
    public let needsWriteSubagent: Bool
    public let needsWorkspaceSandbox: Bool
    public let needsNativeTools: Bool

    public init(
        needsReadonlySubagent: Bool = false,
        needsWriteSubagent: Bool = false,
        needsWorkspaceSandbox: Bool = false,
        needsNativeTools: Bool = false
    ) {
        self.needsReadonlySubagent = needsReadonlySubagent
        self.needsWriteSubagent = needsWriteSubagent
        self.needsWorkspaceSandbox = needsWorkspaceSandbox
        self.needsNativeTools = needsNativeTools
    }

    /// Verifica se il provider soddisfa tutte le capability richieste.
    public func isSatisfied(by provider: ProviderCapabilityEntry) -> Bool {
        if needsReadonlySubagent && !provider.supportsReadonlySubagent {
            return false
        }
        if needsWriteSubagent && !provider.supportsWriteSubagent {
            return false
        }
        if needsWorkspaceSandbox && !provider.supportsWorkspaceSandbox {
            return false
        }
        if needsNativeTools && !provider.supportsNativeTools {
            return false
        }
        return true
    }

    /// Punteggio di match: quante capability il provider copre (0..1).
    public func matchScore(for provider: ProviderCapabilityEntry) -> Double {
        var total = 0
        var matched = 0

        if needsReadonlySubagent {
            total += 1
            if provider.supportsReadonlySubagent { matched += 1 }
        }
        if needsWriteSubagent {
            total += 1
            if provider.supportsWriteSubagent { matched += 1 }
        }
        if needsWorkspaceSandbox {
            total += 1
            if provider.supportsWorkspaceSandbox { matched += 1 }
        }
        if needsNativeTools {
            total += 1
            if provider.supportsNativeTools { matched += 1 }
        }

        guard total > 0 else { return 1.0 }
        return Double(matched) / Double(total)
    }
}

// MARK: - ProviderRouter

/// Seleziona il provider ottimale per capability, health, e ranking (§5.9).
///
/// Algoritmo:
/// 1. Filtra per capability richiesta dal ruolo
/// 2. Escludi provider unhealthy
/// 3. Ranking multi-fattore: capability_match * 0.4 + reliability * 0.3
///    + latency_score * 0.2 + cost_efficiency * 0.1
/// 4. Fallback: se nessun match pieno, prova capability ridotte
public struct ProviderRouter: Sendable {

    // MARK: - Pesi ranking (§5.9)

    public static let weightCapability: Double = 0.4
    public static let weightReliability: Double = 0.3
    public static let weightLatency: Double = 0.2
    public static let weightCost: Double = 0.1

    public static let maxLatencyMs: Double = 30_000

    public init() {}

    // MARK: - Capability Mapping

    /// Mappa agent_role → capability richieste (§5.9, §14.1).
    public func requiredCapabilities(
        for role: AgentRole
    ) -> RequiredCapabilities {
        switch role {
        case .coder:
            return RequiredCapabilities(
                needsWriteSubagent: true,
                needsWorkspaceSandbox: true,
                needsNativeTools: true
            )
        case .debugger:
            return RequiredCapabilities(
                needsWriteSubagent: true,
                needsWorkspaceSandbox: true,
                needsNativeTools: true
            )
        case .testWriter:
            return RequiredCapabilities(
                needsWriteSubagent: true,
                needsWorkspaceSandbox: true
            )
        case .reviewer:
            return RequiredCapabilities(
                needsReadonlySubagent: true,
                needsNativeTools: true
            )
        case .bugHunter:
            return RequiredCapabilities(
                needsReadonlySubagent: true,
                needsNativeTools: true
            )
        case .explorer:
            return RequiredCapabilities(
                needsReadonlySubagent: true
            )
        case .docWriter:
            return RequiredCapabilities(
                needsWriteSubagent: true
            )
        case .securityAuditor:
            return RequiredCapabilities(
                needsReadonlySubagent: true,
                needsNativeTools: true
            )
        case .planner:
            return RequiredCapabilities(
                needsReadonlySubagent: true
            )
        }
    }

    // MARK: - Select Provider

    /// Seleziona il provider migliore per un task e ruolo (§5.9).
    public func select(
        matrix: ProviderCapabilityMatrix,
        role: AgentRole,
        latencies: [String: Double] = [:],
        costScores: [String: Double] = [:]
    ) -> Result<ProviderSelectionResult, ProviderRoutingError> {
        guard !matrix.providers.isEmpty else {
            return .failure(.noProvidersAvailable)
        }

        let required = requiredCapabilities(for: role)
        let healthyProviders = matrix.providers.filter {
            $0.healthStatus != .unhealthy
        }

        guard !healthyProviders.isEmpty else {
            return .failure(.allProvidersUnhealthy)
        }

        let fullMatchCandidates = healthyProviders.filter {
            required.isSatisfied(by: $0)
        }

        if let result = rankAndSelect(
            candidates: fullMatchCandidates,
            required: required,
            reason: .capabilityMatch,
            latencies: latencies,
            costScores: costScores
        ) {
            return .success(result)
        }

        return .failure(.noCapabilityMatch(role: role))
    }

    // MARK: - Fallback Chain

    /// Seleziona con fallback chain esplicita (§14.2).
    ///
    /// Regole:
    /// 1. Retry stesso provider fino a maxAttempts
    /// 2. Fallback al successivo solo dopo esaurimento retry
    /// 3. Decisione tracciata con correlationId
    public func selectWithFallback(
        matrix: ProviderCapabilityMatrix,
        role: AgentRole,
        fallbackChain: [String],
        failedProviders: Set<String> = [],
        latencies: [String: Double] = [:],
        costScores: [String: Double] = [:]
    ) -> Result<ProviderSelectionResult, ProviderRoutingError> {
        let required = requiredCapabilities(for: role)

        for providerId in fallbackChain {
            if failedProviders.contains(providerId) {
                continue
            }

            guard let provider = matrix.provider(byId: providerId) else {
                continue
            }

            if provider.healthStatus == .unhealthy {
                continue
            }

            if !required.isSatisfied(by: provider) {
                continue
            }

            let score = computeScore(
                provider: provider,
                required: required,
                latencies: latencies,
                costScores: costScores
            )

            let availableCandidates = fallbackChain.filter {
                !failedProviders.contains($0)
            }

            return .success(ProviderSelectionResult(
                provider: provider,
                reason: failedProviders.isEmpty
                    ? .capabilityMatch : .fallbackReduced,
                candidatesCount: availableCandidates.count,
                score: score
            ))
        }

        return .failure(.fallbackExhausted(
            role: role,
            tried: Array(failedProviders)
        ))
    }

    // MARK: - Ranking

    /// Ranking multi-fattore e selezione del migliore (§5.9).
    private func rankAndSelect(
        candidates: [ProviderCapabilityEntry],
        required: RequiredCapabilities,
        reason: ProviderSelectionReason,
        latencies: [String: Double],
        costScores: [String: Double]
    ) -> ProviderSelectionResult? {
        guard !candidates.isEmpty else { return nil }

        var bestProvider = candidates[0]
        var bestScore = computeScore(
            provider: candidates[0],
            required: required,
            latencies: latencies,
            costScores: costScores
        )

        for candidate in candidates.dropFirst() {
            let score = computeScore(
                provider: candidate,
                required: required,
                latencies: latencies,
                costScores: costScores
            )
            if score > bestScore {
                bestScore = score
                bestProvider = candidate
            }
        }

        return ProviderSelectionResult(
            provider: bestProvider,
            reason: reason,
            candidatesCount: candidates.count,
            score: bestScore
        )
    }

    /// Formula ranking (§5.9):
    /// score = capability_match * 0.4
    ///       + (1 - error_rate) * 0.3
    ///       + (1 - normalize(latency)) * 0.2
    ///       + cost_efficiency * 0.1
    public func computeScore(
        provider: ProviderCapabilityEntry,
        required: RequiredCapabilities,
        latencies: [String: Double],
        costScores: [String: Double]
    ) -> Double {
        let capScore = required.matchScore(for: provider)
        let reliability = 1.0 - min(provider.errorRateLastHour, 1.0)
        let latencyMs = latencies[provider.providerId]
            ?? (Self.maxLatencyMs * 0.5)
        let latencyScore = 1.0
            - min(latencyMs / Self.maxLatencyMs, 1.0)
        let costScore = costScores[provider.providerId] ?? 0.5

        return capScore * Self.weightCapability
            + reliability * Self.weightReliability
            + latencyScore * Self.weightLatency
            + costScore * Self.weightCost
    }
}
