import Foundation

/// Specialized roles for inline subagent execution.
/// Each role maps to a `subagent_<role>` tool the main agent can call during streaming.
public enum SubagentRole: String, CaseIterable, Codable, Sendable {
    case explorer
    case coder
    case debugger
    case reviewer
    case bugHunter
    case testWriter
    case docWriter
    case securityAuditor

    /// Tool name registered in the system prompt (e.g. `subagent_explorer`).
    public var toolName: String { "subagent_\(rawValue)" }

    /// Human-readable name for UI.
    public var displayName: String {
        switch self {
        case .explorer:        return "Explorer"
        case .coder:           return "Coder"
        case .debugger:        return "Debugger"
        case .reviewer:        return "Reviewer"
        case .bugHunter:       return "BugHunter"
        case .testWriter:      return "TestWriter"
        case .docWriter:       return "DocWriter"
        case .securityAuditor: return "SecurityAuditor"
        }
    }

    /// Whether this subagent can use file-editing tools.
    /// Read-only roles can search/read/analyze but never edit.
    public var canEditFiles: Bool {
        switch self {
        case .explorer, .reviewer, .bugHunter, .securityAuditor:
            return false
        default: return true
        }
    }

    /// Maximum tool execution rounds for this subagent.
    /// Read-only analysis roles get lower budgets than write-capable roles.
    public var maxToolRounds: Int {
        switch self {
        case .explorer:
            return 40
        case .reviewer, .bugHunter, .securityAuditor:
            return 50
        case .testWriter:
            return 100
        case .coder, .debugger, .docWriter:
            return 80
        }
    }

    /// Resolve a `SubagentRole` from a tool name like `subagent_explorer`.
    public static func fromToolName(_ name: String) -> SubagentRole? {
        var normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()

        let wrapperPrefixes = [
            "functions.mcp__coderide__coderide_",
            "mcp__coderide__coderide_",
            "coderide_",
        ]
        for prefix in wrapperPrefixes where normalized.hasPrefix(prefix) {
            normalized = String(normalized.dropFirst(prefix.count))
            break
        }

        guard normalized.hasPrefix("subagent_") else { return nil }
        let suffix = String(normalized.dropFirst("subagent_".count))

        // Accept canonical names plus legacy/normalized aliases so tool calls from
        // different providers (camelCase, snake_case, lowercase) all resolve.
        switch suffix {
        case "explorer":
            return .explorer
        case "coder":
            return .coder
        case "debugger":
            return .debugger
        case "reviewer":
            return .reviewer
        case "bughunter", "bug_hunter", "bugfinder", "bug_finder":
            return .bugHunter
        case "testwriter", "test_writer", "tester":
            return .testWriter
        case "docwriter", "doc_writer":
            return .docWriter
        case "securityauditor", "security_auditor":
            return .securityAuditor
        default:
            return nil
        }
    }

    /// All tool names for registering in the system prompt.
    public static var allToolNames: [String] {
        allCases.map(\.toolName)
    }
}

public struct SubagentBackendSelection: Sendable, Equatable {
    public let providerID: String
    public let cliPath: String
    public let timeoutSeconds: TimeInterval

    public init(
        providerID: String,
        cliPath: String,
        timeoutSeconds: TimeInterval
    ) {
        self.providerID = providerID
        self.cliPath = cliPath
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum SubagentBackendResolver {
    public static func selectBackend(for role: SubagentRole) async -> SubagentBackendSelection? {
        await selectBackend(for: role, discoveredCLIs: discoverAvailableCLIs())
    }

    static func selectBackend(
        for role: SubagentRole,
        discoveredCLIs: [String: String]
    ) async -> SubagentBackendSelection? {
        guard let routing = await buildRoutingContext(for: role, discoveredCLIs: discoveredCLIs) else {
            return nil
        }
        return selectBackend(
            for: role,
            compatibleCLIs: routing.compatibleCLIs,
            matrix: routing.matrix
        )
    }

    static func selectBackend(
        for role: SubagentRole,
        discoveredCLIs: [String: String]
    ) -> SubagentBackendSelection? {
        guard let routing = buildRoutingContextSync(for: role, discoveredCLIs: discoveredCLIs) else {
            return nil
        }
        return selectBackend(
            for: role,
            compatibleCLIs: routing.compatibleCLIs,
            matrix: routing.matrix
        )
    }

    private static func selectBackend(
        for role: SubagentRole,
        compatibleCLIs: [String: String],
        matrix: ProviderCapabilityMatrix
    ) -> SubagentBackendSelection? {
        guard !compatibleCLIs.isEmpty else { return nil }
        let preferredProviders = SubagentCLIConfig.preferredBackendNames(
            readOnly: SubagentCLIConfig.isReadOnly(role)
        )
        let fallbackChain = preferredProviders
            + compatibleCLIs.keys.sorted().filter { !preferredProviders.contains($0) }
        let router = ProviderRouter()
        let selection = router.selectWithFallback(
            matrix: matrix,
            role: role.agentRole,
            fallbackChain: fallbackChain
        )
        guard case .success(let result) = selection,
              let cliPath = compatibleCLIs[result.provider.providerId] else {
            return nil
        }
        return SubagentBackendSelection(
            providerID: result.provider.providerId,
            cliPath: cliPath,
            timeoutSeconds: SubagentCLIConfig.timeout(for: role)
        )
    }

    private static func buildRoutingContextSync(
        for role: SubagentRole,
        discoveredCLIs: [String: String]
    ) -> (compatibleCLIs: [String: String], matrix: ProviderCapabilityMatrix)? {
        let readOnly = SubagentCLIConfig.isReadOnly(role)
        let compatibleCLIs = discoveredCLIs.filter { _, path in
            SubagentCLIConfig.supportsSandboxExpectations(
                cliPath: path,
                readOnly: readOnly
            )
        }
        guard !compatibleCLIs.isEmpty else { return nil }

        let matrix = ProviderCapabilityMatrix(
            providers: compatibleCLIs.keys.sorted().map { providerID in
                capabilityEntry(for: providerID)
            }
        )
        return (compatibleCLIs, matrix)
    }

    private static func buildRoutingContext(
        for role: SubagentRole,
        discoveredCLIs: [String: String]
    ) async -> (compatibleCLIs: [String: String], matrix: ProviderCapabilityMatrix)? {
        guard let base = buildRoutingContextSync(for: role, discoveredCLIs: discoveredCLIs) else {
            return nil
        }
        let hydratedMatrix = await SubagentProviderHealthRuntime.shared.hydratedMatrix(
            from: base.matrix
        )
        return (base.compatibleCLIs, hydratedMatrix)
    }

    static func discoverAvailableCLIs() -> [String: String] {
        var discovered: [String: String] = [:]
        for providerID in SubagentCLIConfig.knownProviderIDs {
            if let path = PathFinder.find(
                executable: providerID,
                pathEnv: SubagentCLIConfig.constrainedPATH,
                allowInteractiveShellLookup: false,
                includeDefaultCandidates: false
            ) {
                discovered[providerID] = path
            }
        }
        return discovered
    }

    private static func capabilityEntry(for providerID: String) -> ProviderCapabilityEntry {
        switch providerID {
        case "codex":
            return ProviderCapabilityEntry(
                providerId: providerID,
                supportsReadonlySubagent: true,
                supportsWriteSubagent: true,
                supportsWorkspaceSandbox: true,
                supportsNativeTools: true
            )
        case "claude":
            return ProviderCapabilityEntry(
                providerId: providerID,
                supportsReadonlySubagent: true,
                supportsWriteSubagent: false,
                supportsWorkspaceSandbox: false,
                supportsNativeTools: true
            )
        default:
            return ProviderCapabilityEntry(
                providerId: providerID,
                supportsReadonlySubagent: false,
                supportsWriteSubagent: false,
                supportsWorkspaceSandbox: false,
                supportsNativeTools: false
            )
        }
    }
}

private extension SubagentRole {
    var agentRole: AgentRole {
        switch self {
        case .explorer:
            return .explorer
        case .coder:
            return .coder
        case .debugger:
            return .debugger
        case .reviewer:
            return .reviewer
        case .bugHunter:
            return .bugHunter
        case .testWriter:
            return .testWriter
        case .docWriter:
            return .docWriter
        case .securityAuditor:
            return .securityAuditor
        }
    }
}
