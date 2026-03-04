import Foundation

// MARK: - Codigo Plugin Protocol

/// Protocollo ad alto livello per i plugin Codigo.
/// Estende IDEExtensionPlugin con lifecycle hooks e metadati aggiuntivi.
protocol CodigoPlugin: IDEExtensionPlugin {
    /// Tipo del plugin (tema, linter, tool, language, snippet).
    var pluginType: CodigoPluginType { get }

    /// Descrizione human-readable del plugin.
    var pluginDescription: String { get }

    /// URL della homepage/documentazione del plugin (opzionale).
    var homepageURL: URL? { get }

    /// Hook chiamato quando il workspace cambia.
    func onWorkspaceChanged(roots: [String]) async

    /// Hook chiamato quando le preferenze utente cambiano.
    func onPreferencesChanged(preferences: [String: String]) async
}

/// Tipo di plugin Codigo.
enum CodigoPluginType: String, Codable, Sendable, CaseIterable {
    case tool       // Tool che esegue operazioni
    case theme      // Tema visuale
    case linter     // Linter/formatter
    case language   // Supporto linguaggio
    case snippet    // Provider di snippet
    case panel      // Pannello UI custom
}

/// Stato corrente di un plugin nel sistema.
enum PluginState: String, Sendable {
    case discovered     // Trovato su disco
    case validated      // Manifest validato
    case loading        // In fase di caricamento
    case active         // Attivo e funzionante
    case error          // Errore durante il caricamento
    case disabled       // Disabilitato dall'utente
    case uninstalled    // In fase di rimozione
}

/// Descrittore completo di un plugin registrato.
struct PluginDescriptor: Identifiable, Sendable {
    let id: String
    let manifest: ExtensionManifest
    let pluginType: CodigoPluginType
    let description: String
    let rootPath: String
    let discoveredAt: Date
    var state: PluginState
    var loadError: String?
}

// MARK: - Default Implementations

extension CodigoPlugin {
    var homepageURL: URL? { nil }
    var pluginDescription: String { manifest.name }

    func onWorkspaceChanged(roots: [String]) async {}
    func onPreferencesChanged(preferences: [String: String]) async {}
}
