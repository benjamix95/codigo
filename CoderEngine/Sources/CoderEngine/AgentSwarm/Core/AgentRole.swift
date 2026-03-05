import Foundation

/// Ruoli specializzati negli agenti della pipeline e dello swarm (§6.13).
public enum AgentRole: String, CaseIterable, Codable, Sendable, Equatable {
    case planner
    case explorer
    case coder
    case debugger
    case reviewer
    case docWriter
    case securityAuditor
    case testWriter

    /// Nome visualizzato per la UI.
    public var displayName: String {
        switch self {
        case .planner: "Planner"
        case .explorer: "Explorer"
        case .coder: "Coder"
        case .debugger: "Debugger"
        case .reviewer: "Reviewer"
        case .docWriter: "DocWriter"
        case .securityAuditor: "SecurityAuditor"
        case .testWriter: "TestWriter"
        }
    }

    /// Ruoli read-only non possono mutare il repository (§6.13).
    public var isReadOnly: Bool {
        switch self {
        case .planner, .explorer, .reviewer, .securityAuditor: true
        case .coder, .debugger, .testWriter, .docWriter: false
        }
    }
}

public actor SubagentProviderHealthRuntime {
    public static let shared = SubagentProviderHealthRuntime()

    private var checker = SubagentProviderHealthRuntime.makeChecker()
    private var registeredProviderIDs: Set<String> = []

    func hydratedMatrix(
        from matrix: ProviderCapabilityMatrix
    ) async -> ProviderCapabilityMatrix {
        await ensureRegistered(from: matrix)
        return await checker.applyHealthStates(to: matrix)
    }

    func recordExecution(
        providerID: String,
        success: Bool
    ) async {
        await ensureRegistered(providerID: providerID)
        await checker.recordExecutionResult(
            providerId: providerID,
            success: success
        )
    }

    func overrideHealthStatusForTests(
        providerID: String,
        status: ProviderHealthStatus
    ) async {
        await ensureRegistered(
            entry: ProviderCapabilityEntry(providerId: providerID, healthStatus: status)
        )
        await checker.registerProvider(
            ProviderCapabilityEntry(providerId: providerID, healthStatus: status)
        )
    }

    func resetForTests() async {
        checker = Self.makeChecker()
        registeredProviderIDs = []
    }

    private func ensureRegistered(
        from matrix: ProviderCapabilityMatrix
    ) async {
        for provider in matrix.providers {
            await ensureRegistered(entry: provider)
        }
    }

    private func ensureRegistered(providerID: String) async {
        await ensureRegistered(entry: ProviderCapabilityEntry(providerId: providerID))
    }

    private func ensureRegistered(entry: ProviderCapabilityEntry) async {
        guard !registeredProviderIDs.contains(entry.providerId) else { return }
        await checker.registerProvider(entry)
        registeredProviderIDs.insert(entry.providerId)
    }

    private static func makeChecker() -> ProviderHealthChecker {
        ProviderHealthChecker(probeDelegate: NoopHealthProbeDelegate())
    }
}

private struct NoopHealthProbeDelegate: HealthProbeDelegate {
    func probe(
        providerId: String,
        timeoutMs _: Int
    ) async -> HealthProbeResult {
        HealthProbeResult(providerId: providerId, success: true)
    }
}
