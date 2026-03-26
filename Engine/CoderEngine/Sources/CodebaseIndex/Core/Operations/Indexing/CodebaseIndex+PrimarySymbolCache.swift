import Foundation

// MARK: - Persistenza indice simboli (riuso tra aperture progetto)

extension CodebaseIndex {
    static let primarySymbolCacheFileName = "primary_symbol_index_v1.json"
    static let primarySymbolCacheVersion: Int = 1

    struct PrimarySymbolCachePayload: Codable {
        var version: Int
        var workspacePathsKey: String
        var settingsKey: String
        var files: [IndexedFile]
    }

    /// Chiave stabile per esclusioni / gitignore (invalida la cache se cambia).
    static func primaryCacheSettingsKey(
        excludedPaths: [String],
        excludedFilePatterns: [String],
        respectGitignore: Bool
    ) -> String {
        let a = excludedPaths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .sorted().joined(separator: "\n")
        let b = excludedFilePatterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .sorted().joined(separator: "\n")
        return "\(a)\u{1f}\(b)\u{1f}\(respectGitignore)"
    }

    /// Prova a ripristinare l’indice simboli da disco se workspace, settings e hash file coincidono.
    func loadValidatedPrimarySymbolCache(
        cacheURL: URL,
        filesToIndex: [FileNode],
        workspacePathsKey: String,
        settingsKey: String
    ) async -> [IndexedFile]? {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(PrimarySymbolCachePayload.self, from: data),
              payload.version == Self.primarySymbolCacheVersion,
              payload.workspacePathsKey == workspacePathsKey,
              payload.settingsKey == settingsKey
        else {
            return nil
        }
        let expected = Set(filesToIndex.map(\.relativePath))
        let cached = Set(payload.files.map(\.relativePath))
        guard expected == cached, !expected.isEmpty else {
            return nil
        }
        var byRel: [String: IndexedFile] = [:]
        for f in payload.files {
            byRel[f.relativePath] = f
        }
        for node in filesToIndex {
            guard let cachedFile = byRel[node.relativePath] else { return nil }
            guard let diskData = FileManager.default.contents(atPath: node.absolutePath) else {
                return nil
            }
            if SymbolExtractor.fnv1aHash(diskData) != cachedFile.contentHash {
                return nil
            }
        }
        return filesToIndex.compactMap { node -> IndexedFile? in
            guard let f = byRel[node.relativePath] else { return nil }
            if f.absolutePath == node.absolutePath {
                return f
            }
            return IndexedFile(
                relativePath: f.relativePath,
                absolutePath: node.absolutePath,
                language: f.language,
                symbols: f.symbols,
                imports: f.imports,
                lineCount: f.lineCount,
                size: f.size,
                indexedAt: f.indexedAt,
                contentHash: f.contentHash
            )
        }
    }

    func savePrimarySymbolCache(
        cacheURL: URL,
        paths: [URL],
        excludedPaths: [String],
        excludedFilePatterns: [String],
        respectGitignore: Bool
    ) {
        let payload = PrimarySymbolCachePayload(
            version: Self.primarySymbolCacheVersion,
            workspacePathsKey: Self.indexCachePathsKey(for: paths),
            settingsKey: Self.primaryCacheSettingsKey(
                excludedPaths: excludedPaths,
                excludedFilePatterns: excludedFilePatterns,
                respectGitignore: respectGitignore
            ),
            files: indexedFiles.values.sorted { $0.relativePath < $1.relativePath }
        )
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let data = try enc.encode(payload)
            try data.write(to: cacheURL, options: [.atomic])
            Self.logger.info("saved primary symbol cache (\(payload.files.count) files)")
        } catch {
            Self.logger.error("primary symbol cache save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
