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

    /// Piani di riuso cache: file ancora validi per hash, file da re-indicizzare, path da rimuovere dal semantic index.
    struct PrimarySymbolCacheHydration: Sendable {
        let reusableFiles: [IndexedFile]
        let filesToReindex: [FileNode]
        let semanticRemovals: [String]
    }

    /// Carica la cache simboli e la confronta file-per-file con il disco: riusa ciò che non è cambiato e richiede
    /// solo i diff (nuovi / modificati / non in cache). I path presenti in cache ma assenti dal workspace attuale
    /// vanno rimossi dall’indice semantico persistito.
    func loadPrimarySymbolCacheHydration(
        cacheURL: URL,
        filesToIndex: [FileNode],
        workspacePathsKey: String,
        settingsKey: String
    ) async -> PrimarySymbolCacheHydration? {
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
        guard !expected.isEmpty else { return nil }

        let cachedPaths = Set(payload.files.map(\.relativePath))
        let semanticRemovals = cachedPaths.subtracting(expected).sorted()

        var byRel: [String: IndexedFile] = [:]
        for f in payload.files {
            byRel[f.relativePath] = f
        }

        let orderedNodes = filesToIndex.sorted { $0.relativePath < $1.relativePath }
        var reusable: [IndexedFile] = []
        reusable.reserveCapacity(orderedNodes.count)
        var toReindex: [FileNode] = []
        toReindex.reserveCapacity(min(32, orderedNodes.count))

        for node in orderedNodes {
            if let cachedFile = byRel[node.relativePath],
               let diskData = FileManager.default.contents(atPath: node.absolutePath),
               SymbolExtractor.fnv1aHash(diskData) == cachedFile.contentHash {
                if cachedFile.absolutePath == node.absolutePath {
                    reusable.append(cachedFile)
                } else {
                    reusable.append(
                        IndexedFile(
                            relativePath: cachedFile.relativePath,
                            absolutePath: node.absolutePath,
                            language: cachedFile.language,
                            symbols: cachedFile.symbols,
                            imports: cachedFile.imports,
                            lineCount: cachedFile.lineCount,
                            size: cachedFile.size,
                            indexedAt: cachedFile.indexedAt,
                            contentHash: cachedFile.contentHash
                        ))
                }
            } else {
                toReindex.append(node)
            }
        }

        return PrimarySymbolCacheHydration(
            reusableFiles: reusable,
            filesToReindex: toReindex,
            semanticRemovals: semanticRemovals
        )
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
