import Foundation

actor ExtensionRuntime {
    struct LoadedExtension: Sendable {
        let pluginId: String
        let pluginName: String
        let version: String
        let exposedTools: Set<String>
        let grantedCapabilities: Set<ExtensionCapability>
    }

    private struct LoadedPlugin {
        let plugin: any IDEExtensionPlugin
        let context: ExtensionRuntimeContext
        let metadata: LoadedExtension
    }

    private let configuration: ExtensionRuntimeConfiguration
    private let sandbox: ExtensionRuntimeSandbox
    private var loadedPlugins: [String: LoadedPlugin] = [:]

    init(configuration: ExtensionRuntimeConfiguration = .load()) {
        self.configuration = configuration
        self.sandbox = ExtensionRuntimeSandbox(allowedCapabilities: configuration.allowedCapabilities)
    }

    func load(
        plugin: any IDEExtensionPlugin,
        workspaceRoots: [String]
    ) async throws -> LoadedExtension {
        guard configuration.runtimeEnabled else {
            throw ExtensionRuntimeError.runtimeDisabled
        }

        let manifest = plugin.manifest
        if loadedPlugins[manifest.id] != nil {
            throw ExtensionRuntimeError.pluginAlreadyLoaded(manifest.id)
        }

        let granted = try sandbox.validate(
            manifest: manifest,
            currentIDEVersion: configuration.currentIDEVersion
        )
        let context = ExtensionRuntimeContext(
            workspaceRoots: workspaceRoots,
            allowedCapabilities: configuration.allowedCapabilities,
            grantedCapabilities: granted
        )

        try await plugin.onLoad(context: context)
        let metadata = LoadedExtension(
            pluginId: manifest.id,
            pluginName: manifest.name,
            version: manifest.version,
            exposedTools: Set(manifest.exposedTools),
            grantedCapabilities: granted
        )
        loadedPlugins[manifest.id] = LoadedPlugin(plugin: plugin, context: context, metadata: metadata)
        return metadata
    }

    func unload(pluginId: String) async throws {
        guard let loaded = loadedPlugins.removeValue(forKey: pluginId) else {
            throw ExtensionRuntimeError.pluginNotLoaded(pluginId)
        }
        await loaded.plugin.onUnload(context: loaded.context)
    }

    func execute(
        pluginId: String,
        tool: String,
        payload: [String: String]
    ) async throws -> ExtensionToolResponse {
        guard let loaded = loadedPlugins[pluginId] else {
            throw ExtensionRuntimeError.pluginNotLoaded(pluginId)
        }

        guard loaded.metadata.exposedTools.contains(tool) else {
            throw ExtensionRuntimeError.toolNotExposed(pluginId: pluginId, tool: tool)
        }

        let request = ExtensionToolRequest(tool: tool, payload: payload)
        return try await loaded.plugin.handle(request: request, context: loaded.context)
    }

    func listLoadedExtensions() -> [LoadedExtension] {
        loadedPlugins.values
            .map(\.metadata)
            .sorted { lhs, rhs in
                if lhs.pluginName != rhs.pluginName { return lhs.pluginName < rhs.pluginName }
                return lhs.pluginId < rhs.pluginId
            }
    }
}
