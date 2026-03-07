import Foundation
import CoderEngine

enum EnginePluginManifestAdapter {
    static func toExtensionManifest(_ manifest: IDEPluginManifest) -> ExtensionManifest {
        let mappedCapabilities = mapCapabilities(manifest.capabilities)
        let sortedCapabilities = Array(mappedCapabilities).sorted { $0.rawValue < $1.rawValue }

        return ExtensionManifest(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            entryPoint: manifest.entryPoint,
            capabilities: sortedCapabilities,
            exposedTools: manifest.exposedTools,
            minimumIDEVersion: manifest.minimumIDEVersion
        )
    }

    private static func mapCapabilities(_ capabilities: [PluginCapability]) -> Set<ExtensionCapability> {
        var mapped: Set<ExtensionCapability> = []
        for capability in capabilities {
            switch capability {
            case .read:
                mapped.insert(.readWorkspace)
                mapped.insert(.readOnlyTools)
            case .edit, .write:
                mapped.insert(.writeWorkspace)
            case .bash, .subagent:
                mapped.insert(.executeCommands)
            case .web, .mcp:
                mapped.insert(.networkAccess)
            case .git, .debug:
                mapped.insert(.readOnlyTools)
            }
        }
        return mapped
    }
}
