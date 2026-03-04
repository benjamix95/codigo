import Foundation

public protocol PluginRuntimeLifecycleHandling: Sendable {
    func load(descriptor: IDEPluginDescriptor) async throws
    func unload(descriptor: IDEPluginDescriptor) async
}

public struct NoopPluginRuntimeLifecycleHandler: PluginRuntimeLifecycleHandling {
    public init() {}

    public func load(descriptor: IDEPluginDescriptor) async throws {
        _ = descriptor
    }

    public func unload(descriptor: IDEPluginDescriptor) async {
        _ = descriptor
    }
}

public actor PluginRuntime {
    private var pluginsByID: [String: IDEPluginDescriptor] = [:]
    private var allowedToolsByPluginID: [String: Set<String>] = [:]
    private let currentIDEVersion: String
    private let lifecycleHandler: any PluginRuntimeLifecycleHandling

    public init(
        currentIDEVersion: String = "1.0.0",
        lifecycleHandler: any PluginRuntimeLifecycleHandling = NoopPluginRuntimeLifecycleHandler()
    ) {
        self.currentIDEVersion = currentIDEVersion
        self.lifecycleHandler = lifecycleHandler
    }

    public func discoverPlugins(in roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var manifests: [URL] = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "manifest.json" {
                    manifests.append(fileURL)
                }
            }
        }
        return manifests.sorted { $0.path < $1.path }
    }

    @discardableResult
    public func loadPlugin(manifestURL: URL) async throws -> IDEPluginDescriptor {
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw IDEPluginRuntimeError.manifestNotFound(manifestURL.path)
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(IDEPluginManifest.self, from: data)
        try PluginCapabilitySandbox.validate(manifest, currentIDEVersion: currentIDEVersion)

        if pluginsByID[manifest.id] != nil {
            throw IDEPluginRuntimeError.pluginAlreadyLoaded(manifest.id)
        }

        let descriptor = IDEPluginDescriptor(
            manifest: manifest,
            rootPath: manifestURL.deletingLastPathComponent().path,
            loadedAt: Date()
        )
        try await lifecycleHandler.load(descriptor: descriptor)
        pluginsByID[manifest.id] = descriptor
        allowedToolsByPluginID[manifest.id] = PluginCapabilitySandbox.effectiveTools(for: manifest)
        return descriptor
    }

    public func unloadPlugin(id: String) async throws {
        guard let descriptor = pluginsByID.removeValue(forKey: id) else {
            throw IDEPluginRuntimeError.pluginNotLoaded(id)
        }
        allowedToolsByPluginID.removeValue(forKey: id)
        await lifecycleHandler.unload(descriptor: descriptor)
    }

    public func loadedPlugins() -> [IDEPluginDescriptor] {
        pluginsByID.values.sorted { $0.manifest.id < $1.manifest.id }
    }

    public func isLoaded(id: String) -> Bool {
        pluginsByID[id] != nil
    }

    public func allowedTools(forPluginID id: String) -> Set<String> {
        allowedToolsByPluginID[id] ?? []
    }

    public func clearAll() async {
        let loadedDescriptors = pluginsByID.values.sorted { lhs, rhs in
            lhs.manifest.id < rhs.manifest.id
        }
        pluginsByID.removeAll()
        allowedToolsByPluginID.removeAll()
        for descriptor in loadedDescriptors {
            await lifecycleHandler.unload(descriptor: descriptor)
        }
    }
}
