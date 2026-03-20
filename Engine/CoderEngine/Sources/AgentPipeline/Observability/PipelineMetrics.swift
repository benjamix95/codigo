import Foundation

// MARK: - MetricKey

/// Le 32 metriche obbligatorie della pipeline (§18).
public enum MetricKey: String, Codable, Sendable, Equatable, CaseIterable {
    case jobDurationMs = "job_duration_ms"
    case phaseDurationMs = "phase_duration_ms"
    case taskRetryCount = "task_retry_count"
    case lockWaitMs = "lock_wait_ms"
    case patchRejectRate = "patch_reject_rate"
    case reviewRoundCount = "review_round_count"
    case testFailureRate = "test_failure_rate"
    case providerLatencyMs = "provider_latency_ms"
    case providerErrorRate = "provider_error_rate"
    case tokensInOut = "tokens_in_out"
    case contextSizeTokens = "context_size_tokens"
    case patchSizeLines = "patch_size_lines"
    case agentHallucinationRate = "agent_hallucination_rate"
    case editDistancePerPatch = "edit_distance_per_patch"
    case workerUtilizationPercent = "worker_utilization_percent"
    case backpressureEventCount = "backpressure_event_count"
    case circuitBreakerTripCount = "circuit_breaker_trip_count"
    case rollbackCount = "rollback_count"
    case rollbackSuccessRate = "rollback_success_rate"
    case errorBudgetRemainingPercent = "error_budget_remaining_percent"
    case providerHealthStatus = "provider_health_status"
    case contextCompressionRatio = "context_compression_ratio"
    case contextTokensPreCompression = "context_tokens_pre_compression"
    case swarmUtilizationPercent = "swarm_utilization_percent"
    case swarmBudgetExhaustionCount = "swarm_budget_exhaustion_count"
    case contextCacheHitRate = "context_cache_hit_rate"
    case contextCacheEvictionCount = "context_cache_eviction_count"
    case contextCacheSize = "context_cache_size"
    case semanticDiffBreakingChangesCount = "semantic_diff_breaking_changes_count"
    case swarmAdaptiveMultiplierAvg = "swarm_adaptive_multiplier_avg"
    case swarmAdaptiveScaleUpCount = "swarm_adaptive_scale_up_count"
    case swarmAdaptiveScaleDownCount = "swarm_adaptive_scale_down_count"
}

// MARK: - MetricSample

/// Singolo campione metrica con timestamp e label opzionali.
public struct MetricSample: Sendable, Equatable {
    public let key: MetricKey
    public let value: Double
    public let timestamp: Date
    public let jobId: String?
    public let taskId: String?
    public let labels: [String: String]

    public init(
        key: MetricKey,
        value: Double,
        timestamp: Date = Date(),
        jobId: String? = nil,
        taskId: String? = nil,
        labels: [String: String] = [:]
    ) {
        self.key = key
        self.value = value
        self.timestamp = timestamp
        self.jobId = jobId
        self.taskId = taskId
        self.labels = labels
    }
}

// MARK: - SLODefinition

/// Definizione SLO con soglia e direzione (§18).
public struct SLODefinition: Sendable, Equatable {
    public let key: MetricKey
    public let threshold: Double
    public let isUpperBound: Bool

    public init(key: MetricKey, threshold: Double, isUpperBound: Bool) {
        self.key = key
        self.threshold = threshold
        self.isUpperBound = isUpperBound
    }

    public func isMet(by value: Double) -> Bool {
        isUpperBound ? value <= threshold : value >= threshold
    }
}

// MARK: - SLOViolation

public struct SLOViolation: Sendable, Equatable {
    public let slo: SLODefinition
    public let actualValue: Double
    public let timestamp: Date

    public init(slo: SLODefinition, actualValue: Double, timestamp: Date = Date()) {
        self.slo = slo
        self.actualValue = actualValue
        self.timestamp = timestamp
    }
}

// MARK: - PipelineMetrics

/// Raccoglitore di metriche obbligatorie della pipeline (§18).
///
/// - 32 metriche obbligatorie
/// - SLO check con soglie configurabili
/// - Snapshot per job/task
public actor PipelineMetrics {

    private var samples: [MetricSample] = []
    private var sloDefinitions: [SLODefinition] = []

    public init(sloDefinitions: [SLODefinition] = PipelineMetrics.defaultSLOs) {
        self.sloDefinitions = sloDefinitions
    }

    // MARK: - Record

    public func record(_ sample: MetricSample) {
        samples.append(sample)
    }

    public func record(
        key: MetricKey,
        value: Double,
        jobId: String? = nil,
        taskId: String? = nil,
        labels: [String: String] = [:]
    ) {
        let sample = MetricSample(
            key: key,
            value: value,
            jobId: jobId,
            taskId: taskId,
            labels: labels
        )
        samples.append(sample)
    }

    // MARK: - Query

    public func allSamples() -> [MetricSample] {
        samples
    }

    public func samples(forKey key: MetricKey) -> [MetricSample] {
        samples.filter { $0.key == key }
    }

    public func samples(
        forJob jobId: String,
        key: MetricKey? = nil
    ) -> [MetricSample] {
        samples.filter { s in
            s.jobId == jobId && (key == nil || s.key == key)
        }
    }

    public func latestValue(forKey key: MetricKey) -> Double? {
        samples.last(where: { $0.key == key })?.value
    }

    public func average(forKey key: MetricKey) -> Double? {
        let matching = samples.filter { $0.key == key }
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0.0) { $0 + $1.value } / Double(matching.count)
    }

    public func count() -> Int {
        samples.count
    }

    // MARK: - SLO Check

    public func checkSLOs() -> [SLOViolation] {
        var violations: [SLOViolation] = []
        for slo in sloDefinitions {
            guard let avg = average(forKey: slo.key) else { continue }
            if !slo.isMet(by: avg) {
                violations.append(SLOViolation(
                    slo: slo,
                    actualValue: avg
                ))
            }
        }
        return violations
    }

    // MARK: - Snapshot

    /// Restituisce l'ultimo valore per ogni chiave, oppure nil.
    public func snapshot() -> [MetricKey: Double] {
        var result: [MetricKey: Double] = [:]
        for sample in samples {
            result[sample.key] = sample.value
        }
        return result
    }

    // MARK: - Lifecycle

    public func reset() {
        samples.removeAll()
    }

    // MARK: - Default SLOs (§18)

    public static let defaultSLOs: [SLODefinition] = [
        SLODefinition(
            key: .rollbackSuccessRate,
            threshold: 100.0,
            isUpperBound: false
        ),
        SLODefinition(
            key: .circuitBreakerTripCount,
            threshold: 5.0,
            isUpperBound: true
        ),
    ]
}
