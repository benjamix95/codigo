import Foundation

// MARK: - Plugin Discovery

/// Servizio per la scoperta automatica di plugin su disco.
/// Cerca nelle directory convenzionali e carica i manifest.
actor PluginDiscovery {
    /// Directory di ricerca per i plugin.
    struct SearchPath: Sendable {
        let path: String
        let isBuiltIn: Bool
    }

    private let decoder = JSONDecoder()
    private let manifestFileName = "manifest.json"

    // MARK: - Discovery

    /// Scopre tutti i plugin nelle directory di ricerca.
    func discover(searchPaths: [SearchPath]) async -> [PluginDescriptor] {
        var results: [PluginDescriptor] = []
        let fm = FileManager.default

        for searchPath in searchPaths {
            guard fm.fileExists(atPath: searchPath.path) else { continue }

            let entries: [String]
            do {
                entries = try fm.contentsOfDirectory(atPath: searchPath.path)
            } catch {
                continue
            }

            for entry in entries {
                let pluginDir = (searchPath.path as NSString).appendingPathComponent(entry)
                if let descriptor = loadDescriptor(at: pluginDir) {
                    results.append(descriptor)
                }
            }
        }

        return results.sorted { $0.manifest.name < $1.manifest.name }
    }

    /// Scopre plugin usando le directory standard dell'applicazione.
    func discoverDefault(workspacePath: String?) async -> [PluginDescriptor] {
        var paths: [SearchPath] = []

        // Directory built-in
        if let bundlePath = Bundle.main.resourcePath {
            let builtIn = (bundlePath as NSString).appendingPathComponent("Plugins")
            paths.append(SearchPath(path: builtIn, isBuiltIn: true))
        }

        // Directory utente (~/.solocode/plugins)
        let userDir = NSHomeDirectory()
        let userPlugins = (userDir as NSString).appendingPathComponent(".solocode/plugins")
        paths.append(SearchPath(path: userPlugins, isBuiltIn: false))

        // Directory workspace (.solocode/plugins)
        if let workspace = workspacePath {
            let wsPlugins = (workspace as NSString).appendingPathComponent(".solocode/plugins")
            paths.append(SearchPath(path: wsPlugins, isBuiltIn: false))
        }

        return await discover(searchPaths: paths)
    }

    /// Verifica se un manifest è valido senza caricare il plugin.
    func validateManifest(at directoryPath: String) -> (valid: Bool, error: String?) {
        let manifestPath = (directoryPath as NSString)
            .appendingPathComponent(manifestFileName)

        guard FileManager.default.fileExists(atPath: manifestPath) else {
            return (false, "manifest.json non trovato")
        }

        guard let data = FileManager.default.contents(atPath: manifestPath) else {
            return (false, "Impossibile leggere manifest.json")
        }

        do {
            let manifest = try decoder.decode(ExtensionManifest.self, from: data)
            if manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (false, "ID mancante nel manifest")
            }
            if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (false, "Nome mancante nel manifest")
            }
            return (true, nil)
        } catch {
            return (false, "Parsing manifest fallito: \(error.localizedDescription)")
        }
    }

    // MARK: - Privato

    private func loadDescriptor(at directoryPath: String) -> PluginDescriptor? {
        let manifestPath = (directoryPath as NSString)
            .appendingPathComponent(manifestFileName)

        guard let data = FileManager.default.contents(atPath: manifestPath),
              let manifest = try? decoder.decode(ExtensionManifest.self, from: data) else {
            return nil
        }

        let pluginType = inferPluginType(from: manifest)

        return PluginDescriptor(
            id: manifest.id,
            manifest: manifest,
            pluginType: pluginType,
            description: manifest.name,
            rootPath: directoryPath,
            discoveredAt: Date(),
            state: .discovered,
            loadError: nil
        )
    }

    private func inferPluginType(from manifest: ExtensionManifest) -> SoloCodePluginType {
        let name = manifest.name.lowercased()
        let tools = Set(manifest.exposedTools.map { $0.lowercased() })

        if name.contains("theme") || name.contains("tema") { return .theme }
        if name.contains("lint") || name.contains("format") { return .linter }
        if name.contains("language") || name.contains("lang") { return .language }
        if name.contains("snippet") { return .snippet }
        if tools.contains("panel") || name.contains("panel") { return .panel }

        return .tool
    }
}
