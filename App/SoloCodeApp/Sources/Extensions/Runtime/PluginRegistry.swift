import Foundation

// MARK: - Plugin Registry

/// Registro centralizzato per tutti i plugin scoperti e caricati.
/// Gestisce il ciclo di vita dei plugin e mantiene lo stato.
actor PluginRegistry {
    private var descriptors: [String: PluginDescriptor] = [:]
    private var plugins: [String: any IDEExtensionPlugin] = [:]
    private let runtime: ExtensionRuntime

    init(runtime: ExtensionRuntime = ExtensionRuntime()) {
        self.runtime = runtime
    }

    // MARK: - Registrazione

    /// Registra un plugin scoperto nel registry.
    func register(descriptor: PluginDescriptor) {
        descriptors[descriptor.id] = descriptor
    }

    /// Registra e carica un plugin in un solo passo.
    func registerAndLoad(
        plugin: any IDEExtensionPlugin,
        descriptor: PluginDescriptor,
        workspaceRoots: [String]
    ) async -> PluginDescriptor {
        var desc = descriptor
        desc.state = .loading
        descriptors[desc.id] = desc
        plugins[desc.id] = plugin

        do {
            _ = try await runtime.load(plugin: plugin, workspaceRoots: workspaceRoots)
            desc.state = .active
            desc.loadError = nil
        } catch {
            desc.state = .error
            desc.loadError = error.localizedDescription
        }

        descriptors[desc.id] = desc
        return desc
    }

    // MARK: - Scaricamento

    /// Scarica un plugin attivo.
    func unload(pluginId: String) async {
        guard var desc = descriptors[pluginId], desc.state == .active else { return }
        try? await runtime.unload(pluginId: pluginId)
        desc.state = .discovered
        descriptors[pluginId] = desc
        plugins.removeValue(forKey: pluginId)
    }

    /// Disabilita un plugin (scarica e marca come disabled).
    func disable(pluginId: String) async {
        await unload(pluginId: pluginId)
        descriptors[pluginId]?.state = .disabled
        saveDisabledState(pluginId: pluginId, disabled: true)
    }

    /// Riabilita un plugin disabilitato.
    func enable(pluginId: String) {
        guard descriptors[pluginId]?.state == .disabled else { return }
        descriptors[pluginId]?.state = .discovered
        saveDisabledState(pluginId: pluginId, disabled: false)
    }

    // MARK: - Query

    /// Restituisce tutti i descrittori registrati.
    func allDescriptors() -> [PluginDescriptor] {
        descriptors.values.sorted { $0.manifest.name < $1.manifest.name }
    }

    /// Restituisce i descrittori per tipo.
    func descriptors(ofType type: SoloCodePluginType) -> [PluginDescriptor] {
        descriptors.values
            .filter { $0.pluginType == type }
            .sorted { $0.manifest.name < $1.manifest.name }
    }

    /// Restituisce i plugin attivi.
    func activeDescriptors() -> [PluginDescriptor] {
        descriptors.values
            .filter { $0.state == .active }
            .sorted { $0.manifest.name < $1.manifest.name }
    }

    /// Verifica se un plugin è caricato.
    func isLoaded(_ pluginId: String) -> Bool {
        descriptors[pluginId]?.state == .active
    }

    /// Restituisce il descrittore di un plugin specifico.
    func descriptor(for pluginId: String) -> PluginDescriptor? {
        descriptors[pluginId]
    }

    /// Esegue un tool su un plugin attivo.
    func executeTool(
        pluginId: String,
        tool: String,
        payload: [String: String]
    ) async throws -> ExtensionToolResponse {
        try await runtime.execute(pluginId: pluginId, tool: tool, payload: payload)
    }

    // MARK: - Stato Disabilitati

    /// Restituisce i plugin disabilitati dall'utente (da UserDefaults).
    func disabledPluginIds() -> Set<String> {
        let ids = UserDefaults.standard.stringArray(forKey: "disabled_plugins") ?? []
        return Set(ids)
    }

    private func saveDisabledState(pluginId: String, disabled: Bool) {
        var ids = UserDefaults.standard.stringArray(forKey: "disabled_plugins") ?? []
        if disabled {
            if !ids.contains(pluginId) { ids.append(pluginId) }
        } else {
            ids.removeAll { $0 == pluginId }
        }
        UserDefaults.standard.set(ids, forKey: "disabled_plugins")
    }
}
