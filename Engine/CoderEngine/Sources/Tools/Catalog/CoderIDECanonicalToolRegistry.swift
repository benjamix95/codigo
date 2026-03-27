import Foundation

public enum CanonicalToolAvailability: String, Codable, Sendable {
    case available
    case blocked
    case rerouted
    case mcpRequired = "mcp_required"
}

public enum CanonicalToolSurface: Sendable {
    case app
    case subagents
    case providers
}

public struct CanonicalToolAvailabilityMatrix: Codable, Sendable {
    public let app: CanonicalToolAvailability
    public let subagents: CanonicalToolAvailability
    public let providers: CanonicalToolAvailability
}

public struct CanonicalToolRecord: Codable, Sendable {
    public let mcpName: String
    public let runtimeName: String
    public let family: String
    public let description: String
    public let readOnly: Bool
    public let mutatingRuntime: Bool
    public let firstRoundExempt: Bool
    public let pluginCapabilities: [String]
    public let runtimeAliases: [String]
    public let availability: CanonicalToolAvailabilityMatrix

    enum CodingKeys: String, CodingKey {
        case mcpName = "mcp_name"
        case runtimeName = "runtime_name"
        case family
        case description
        case readOnly = "read_only"
        case mutatingRuntime = "mutating_runtime"
        case firstRoundExempt = "first_round_exempt"
        case pluginCapabilities = "plugin_capabilities"
        case runtimeAliases = "runtime_aliases"
        case availability
    }
}

private struct CanonicalToolManifest: Codable {
    let version: Int
    let generatedFromBootstrap: Bool?
    let tools: [CanonicalToolRecord]
    let nonMcpAliases: [String: String]
    let subagentProviderProfiles: [String: CanonicalSubagentProviderProfile]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedFromBootstrap = "generated_from_bootstrap"
        case tools
        case nonMcpAliases = "non_mcp_aliases"
        case subagentProviderProfiles = "subagent_provider_profiles"
    }
}

public struct CanonicalSubagentProviderProfile: Codable, Sendable {
    public let supportsReadonlySubagent: Bool
    public let supportsWriteSubagent: Bool
    public let supportsWorkspaceSandbox: Bool
    public let supportsNativeTools: Bool

    enum CodingKeys: String, CodingKey {
        case supportsReadonlySubagent = "supports_readonly_subagent"
        case supportsWriteSubagent = "supports_write_subagent"
        case supportsWorkspaceSandbox = "supports_workspace_sandbox"
        case supportsNativeTools = "supports_native_tools"
    }
}

public enum CoderIDECanonicalToolRegistry {
    public static let shared = CoderIDECanonicalToolRegistryStore()
}

public final class CoderIDECanonicalToolRegistryStore {
    public let allRecords: [CanonicalToolRecord]
    public let runtimeAliasesToCanonicalName: [String: String]
    public let allowedRuntimeToolNames: Set<String>
    public let mutatingRuntimeToolNames: Set<String>
    public let firstRoundExemptRuntimeToolNames: Set<String>
    public let pluginToolsByCapability: [PluginCapability: Set<String>]
    public let subagentProviderProfiles: [String: CanonicalSubagentProviderProfile]

    private let manifest: CanonicalToolManifest
    private let recordsByMCPName: [String: CanonicalToolRecord]
    private let recordsByRuntimeName: [String: CanonicalToolRecord]

    public init() {
        guard let data = CoderIDECanonicalToolRegistryGenerated.embedded.data(using: .utf8) else {
            preconditionFailure("canonical tool registry embedded data missing")
        }
        do {
            let decoded = try JSONDecoder().decode(CanonicalToolManifest.self, from: data)
            manifest = decoded
        } catch {
            preconditionFailure("canonical tool registry invalid: \(error)")
        }

        allRecords = manifest.tools
        subagentProviderProfiles = manifest.subagentProviderProfiles
        recordsByMCPName = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.mcpName, $0) })
        recordsByRuntimeName = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.runtimeName.lowercased(), $0) })

        var aliasMap = manifest.nonMcpAliases
        for record in allRecords {
            aliasMap[record.runtimeName.lowercased()] = record.runtimeName.lowercased()
            aliasMap[record.mcpName.lowercased()] = record.runtimeName.lowercased()
            for alias in record.runtimeAliases {
                aliasMap[alias.lowercased()] = record.runtimeName.lowercased()
            }
        }
        runtimeAliasesToCanonicalName = aliasMap

        allowedRuntimeToolNames = Set(allRecords.map { $0.runtimeName.lowercased() })
        mutatingRuntimeToolNames = Set(allRecords.filter(\.mutatingRuntime).map { $0.runtimeName.lowercased() })
        firstRoundExemptRuntimeToolNames = Set(allRecords.filter(\.firstRoundExempt).map { $0.runtimeName.lowercased() })

        var toolsByCapability: [PluginCapability: Set<String>] = [:]
        for capability in PluginCapability.allCases {
            let names = allRecords
                .filter { $0.pluginCapabilities.contains(capability.rawValue) }
                .map { $0.runtimeName.lowercased() }
            toolsByCapability[capability] = Set(names)
        }
        pluginToolsByCapability = toolsByCapability
    }

    public func record(forMCPName name: String) -> CanonicalToolRecord? {
        recordsByMCPName[name]
    }

    public func record(forRuntimeName name: String) -> CanonicalToolRecord? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let canonical = runtimeAliasesToCanonicalName[normalized] else {
            return recordsByRuntimeName[normalized]
        }
        return recordsByRuntimeName[canonical]
    }

    public func runtimeName(forMCPName name: String) -> String? {
        record(forMCPName: name)?.runtimeName.lowercased()
    }

    public func toolNames(for capability: PluginCapability) -> Set<String> {
        pluginToolsByCapability[capability] ?? []
    }

    public var knownSubagentProviderIDs: [String] {
        subagentProviderProfiles.keys.sorted()
    }

    public func providerCapabilityEntry(for providerID: String) -> ProviderCapabilityEntry {
        let normalized = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let profile = subagentProviderProfiles[normalized] else {
            return ProviderCapabilityEntry(
                providerId: providerID,
                supportsReadonlySubagent: false,
                supportsWriteSubagent: false,
                supportsWorkspaceSandbox: false,
                supportsNativeTools: false
            )
        }
        return ProviderCapabilityEntry(
            providerId: providerID,
            supportsReadonlySubagent: profile.supportsReadonlySubagent,
            supportsWriteSubagent: profile.supportsWriteSubagent,
            supportsWorkspaceSandbox: profile.supportsWorkspaceSandbox,
            supportsNativeTools: profile.supportsNativeTools
        )
    }

    public func records(forFamily family: String, availableOn surface: CanonicalToolSurface? = nil) -> [CanonicalToolRecord] {
        let normalizedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allRecords
            .filter { record in
                guard record.family == normalizedFamily else { return false }
                guard let surface else { return true }
                return isUsable(availability(for: record, on: surface))
            }
            .sorted { $0.mcpName < $1.mcpName }
    }

    public func preferredPromptName(forRuntimeName name: String, preferMCP: Bool = true) -> String {
        guard let record = record(forRuntimeName: name) else {
            return name
        }
        return preferMCP ? record.mcpName : record.runtimeName
    }

    public func preferredPromptName(forMCPName name: String, preferMCP: Bool = true) -> String {
        guard let record = record(forMCPName: name) else {
            return name
        }
        return preferMCP ? record.mcpName : record.runtimeName
    }

    public func availability(for record: CanonicalToolRecord, on surface: CanonicalToolSurface) -> CanonicalToolAvailability {
        switch surface {
        case .app:
            return record.availability.app
        case .subagents:
            return record.availability.subagents
        case .providers:
            return record.availability.providers
        }
    }

    public func isUsable(_ availability: CanonicalToolAvailability) -> Bool {
        availability != .blocked
    }
}
