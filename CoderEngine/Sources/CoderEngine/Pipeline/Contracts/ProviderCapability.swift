import Foundation

// MARK: - HealthCheckConfig

/// Configurazione health check per i provider (§6.5).
public struct HealthCheckConfig: Codable, Sendable, Equatable {
    public var probeTimeoutMs: Int
    public var unhealthyThreshold: Int
    public var healthyThreshold: Int
    public var autoFallbackOnUnhealthy: Bool

    public init(
        probeTimeoutMs: Int = 5_000,
        unhealthyThreshold: Int = 3,
        healthyThreshold: Int = 1,
        autoFallbackOnUnhealthy: Bool = true
    ) {
        self.probeTimeoutMs = probeTimeoutMs
        self.unhealthyThreshold = unhealthyThreshold
        self.healthyThreshold = healthyThreshold
        self.autoFallbackOnUnhealthy = autoFallbackOnUnhealthy
    }

    enum CodingKeys: String, CodingKey {
        case probeTimeoutMs = "probe_timeout_ms"
        case unhealthyThreshold = "unhealthy_threshold"
        case healthyThreshold = "healthy_threshold"
        case autoFallbackOnUnhealthy = "auto_fallback_on_unhealthy"
    }
}

// MARK: - ProviderCapabilityEntry

/// Singolo provider con le sue capability (§6.5).
public struct ProviderCapabilityEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { providerId }

    public var providerId: String
    public var supportsReadonlySubagent: Bool
    public var supportsWriteSubagent: Bool
    public var supportsWorkspaceSandbox: Bool
    public var supportsNativeTools: Bool
    public var healthStatus: ProviderHealthStatus
    public var lastHealthCheck: Date?
    public var healthCheckIntervalMs: Int
    public var errorRateLastHour: Double

    public init(
        providerId: String,
        supportsReadonlySubagent: Bool = true,
        supportsWriteSubagent: Bool = false,
        supportsWorkspaceSandbox: Bool = false,
        supportsNativeTools: Bool = true,
        healthStatus: ProviderHealthStatus = .healthy,
        lastHealthCheck: Date? = nil,
        healthCheckIntervalMs: Int = 60_000,
        errorRateLastHour: Double = 0
    ) {
        self.providerId = providerId
        self.supportsReadonlySubagent = supportsReadonlySubagent
        self.supportsWriteSubagent = supportsWriteSubagent
        self.supportsWorkspaceSandbox = supportsWorkspaceSandbox
        self.supportsNativeTools = supportsNativeTools
        self.healthStatus = healthStatus
        self.lastHealthCheck = lastHealthCheck
        self.healthCheckIntervalMs = healthCheckIntervalMs
        self.errorRateLastHour = errorRateLastHour
    }

    enum CodingKeys: String, CodingKey {
        case providerId = "id"
        case supportsReadonlySubagent = "supports_readonly_subagent"
        case supportsWriteSubagent = "supports_write_subagent"
        case supportsWorkspaceSandbox = "supports_workspace_sandbox"
        case supportsNativeTools = "supports_native_tools"
        case healthStatus = "health_status"
        case lastHealthCheck = "last_health_check"
        case healthCheckIntervalMs = "health_check_interval_ms"
        case errorRateLastHour = "error_rate_last_hour"
    }
}

// MARK: - ProviderCapabilityMatrix

/// Matrice completa capability di tutti i provider (§6.5).
public struct ProviderCapabilityMatrix: Codable, Sendable, Equatable {
    public var providers: [ProviderCapabilityEntry]
    public var healthCheckConfig: HealthCheckConfig

    public init(
        providers: [ProviderCapabilityEntry] = [],
        healthCheckConfig: HealthCheckConfig = HealthCheckConfig()
    ) {
        self.providers = providers
        self.healthCheckConfig = healthCheckConfig
    }

    enum CodingKeys: String, CodingKey {
        case providers
        case healthCheckConfig = "health_check_config"
    }

    /// Trova un provider per ID.
    public func provider(byId id: String) -> ProviderCapabilityEntry? {
        providers.first { $0.providerId == id }
    }

    /// Provider sani e disponibili.
    public var healthyProviders: [ProviderCapabilityEntry] {
        providers.filter { $0.healthStatus != .unhealthy }
    }
}

extension ProviderCapabilityMatrix: PipelineValidatable {
    public func validate() throws {
        let c = "ProviderCapabilityMatrix"
        try PipelineValidationHelpers.requireNonEmptyArray(
            providers, field: "providers", contract: c
        )
        let ids = providers.map(\.providerId)
        if Set(ids).count != ids.count {
            throw PipelineValidationError.constraintViolation(
                field: "providers", contract: c,
                reason: "Duplicate provider IDs detected"
            )
        }
    }
}
