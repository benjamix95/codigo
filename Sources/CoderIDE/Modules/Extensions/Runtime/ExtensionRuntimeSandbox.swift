import Foundation
import CoderEngine

enum ExtensionRuntimeError: Error, LocalizedError, Equatable {
    case runtimeDisabled
    case invalidManifest(String)
    case pluginAlreadyLoaded(String)
    case pluginNotLoaded(String)
    case toolNotExposed(pluginId: String, tool: String)
    case capabilityDenied(ExtensionCapability)
    case minimumIDEVersionNotSatisfied(required: String, current: String)

    var errorDescription: String? {
        switch self {
        case .runtimeDisabled:
            return "Extension runtime disabilitato da feature flag."
        case .invalidManifest(let reason):
            return "Manifest non valido: \(reason)"
        case .pluginAlreadyLoaded(let id):
            return "Plugin già caricato: \(id)"
        case .pluginNotLoaded(let id):
            return "Plugin non caricato: \(id)"
        case .toolNotExposed(let pluginId, let tool):
            return "Tool non esposto dal plugin \(pluginId): \(tool)"
        case .capabilityDenied(let capability):
            return "Capability negata dal sandbox: \(capability.rawValue)"
        case .minimumIDEVersionNotSatisfied(let required, let current):
            return "Plugin richiede IDE >= \(required), versione corrente: \(current)"
        }
    }
}

struct ExtensionRuntimeSandbox: Sendable {
    let allowedCapabilities: Set<ExtensionCapability>

    func validate(
        manifest: ExtensionManifest,
        currentIDEVersion: String
    ) throws -> Set<ExtensionCapability> {
        guard !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtensionRuntimeError.invalidManifest("id mancante")
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtensionRuntimeError.invalidManifest("name mancante")
        }
        guard !manifest.exposedTools.isEmpty else {
            throw ExtensionRuntimeError.invalidManifest("exposedTools vuoto")
        }
        let granted = Set(manifest.capabilities)
        for capability in granted where !allowedCapabilities.contains(capability) {
            throw ExtensionRuntimeError.capabilityDenied(capability)
        }

        if let minimum = manifest.minimumIDEVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !minimum.isEmpty {
            guard let satisfies = IDEVersionComparator.satisfies(minimum: minimum, current: currentIDEVersion) else {
                throw ExtensionRuntimeError.invalidManifest("minimumIDEVersion non valido: \(minimum)")
            }
            if !satisfies {
                throw ExtensionRuntimeError.minimumIDEVersionNotSatisfied(
                    required: minimum,
                    current: currentIDEVersion
                )
            }
        }
        return granted
    }
}
