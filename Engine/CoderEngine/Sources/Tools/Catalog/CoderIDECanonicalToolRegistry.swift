import Foundation

public enum CanonicalToolAvailability: String, Codable, Sendable {
    case available
    case blocked
    case rerouted
    case mcpRequired = "mcp_required"
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

    enum CodingKeys: String, CodingKey {
        case version
        case generatedFromBootstrap = "generated_from_bootstrap"
        case tools
        case nonMcpAliases = "non_mcp_aliases"
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
}
