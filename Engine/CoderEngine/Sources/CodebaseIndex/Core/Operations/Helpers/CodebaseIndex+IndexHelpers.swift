import Foundation

extension CodebaseIndex {
    private struct FileNodeMetadata {
        let isDirectory: Bool
        let size: UInt64
        let modifiedAt: Date
    }

    func buildFileTree(
        at url: URL,
        relativePath: String,
        depth: Int
    ) -> FileNode {
        let fm = FileManager.default
        let name = url.lastPathComponent

        guard let metadata = fileNodeMetadata(for: url, fileManager: fm) else {
            return FileNode(
                name: name,
                kind: .file,
                extension_: url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased(),
                relativePath: relativePath.isEmpty ? name : relativePath,
                absolutePath: url.path,
                depth: depth
            )
        }

        if metadata.isDirectory {
            let relPath = relativePath.isEmpty ? name : relativePath

            // Check if excluded
            if Self.defaultExcludedDirs.contains(name) || isExcluded(name, relativePath: relPath) || isGitignored(relPath, isDirectory: true) {
                return FileNode(
                    name: name,
                    kind: .directory,
                    relativePath: relPath,
                    absolutePath: url.path,
                    depth: depth,
                    children: []
                )
            }

            // List children
            guard
                let contents = try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                    ],
                    options: [.skipsHiddenFiles]
                )
            else {
                return FileNode(
                    name: name,
                    kind: .directory,
                    relativePath: relPath,
                    absolutePath: url.path,
                    depth: depth,
                    children: []
                )
            }

            let children =
                contents
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                        == .orderedAscending
                }
                .map { childURL in
                    let childRel =
                        relPath.isEmpty
                        ? childURL.lastPathComponent : "\(relPath)/\(childURL.lastPathComponent)"
                    return buildFileTree(at: childURL, relativePath: childRel, depth: depth + 1)
                }

            return FileNode(
                name: name,
                kind: .directory,
                relativePath: relPath,
                absolutePath: url.path,
                depth: depth,
                children: children
            )
        } else {
            // File
            let ext = url.pathExtension.lowercased()
            return FileNode(
                name: name,
                kind: .file,
                extension_: ext.isEmpty ? nil : ext,
                relativePath: relativePath.isEmpty ? name : relativePath,
                absolutePath: url.path,
                depth: depth,
                size: metadata.size,
                modifiedAt: metadata.modifiedAt
            )
        }
    }

    /// Flattens all nodes into the allFileNodes index
    func flattenNodes(_ node: FileNode) {
        if node.kind == .file {
            allFileNodes[node.relativePath] = node
        } else {
            allFileNodes[node.relativePath] = node
            for child in node.children {
                flattenNodes(child)
            }
        }
    }

    // MARK: - Private: Indexing Helpers

    func addIndexedFile(_ indexed: IndexedFile) {
        indexedFiles[indexed.relativePath] = indexed
        contentHashes[indexed.absolutePath] = indexed.contentHash

        var symbolsForFile = symbolsByFile[indexed.relativePath, default: []]
        var symbolIdsForFile = Set(symbolsForFile.map(\.id))
        var symbolsByNameCache: [String: (symbols: [IndexedSymbol], ids: Set<String>)] = [:]
        var symbolsByKindCache: [SymbolKind: (symbols: [IndexedSymbol], ids: Set<String>)] = [:]

        for symbol in indexed.symbols {
            let key = symbol.name.lowercased()

            var symbolsForName = symbolsByNameCache[key] ?? {
                let existing = symbolsByName[key, default: []]
                return (existing, Set(existing.map(\.id)))
            }()
            if symbolsForName.ids.insert(symbol.id).inserted {
                symbolsForName.symbols.append(symbol)
            }
            symbolsByNameCache[key] = symbolsForName

            if symbolIdsForFile.insert(symbol.id).inserted {
                symbolsForFile.append(symbol)
                totalSymbolsExtracted += 1
            }

            var symbolsForKind = symbolsByKindCache[symbol.kind] ?? {
                let existing = symbolsByKind[symbol.kind, default: []]
                return (existing, Set(existing.map(\.id)))
            }()
            if symbolsForKind.ids.insert(symbol.id).inserted {
                symbolsForKind.symbols.append(symbol)
            }
            symbolsByKindCache[symbol.kind] = symbolsForKind
        }

        symbolsByFile[indexed.relativePath] = symbolsForFile
        for (name, bucket) in symbolsByNameCache {
            symbolsByName[name] = bucket.symbols
        }
        for (kind, bucket) in symbolsByKindCache {
            symbolsByKind[kind] = bucket.symbols
        }
    }

    func removeIndexedFile(_ relativePath: String) {
        guard let existing = indexedFiles[relativePath] else { return }

        // Collect all symbols to remove from both the IndexedFile and symbolsByFile
        // to handle any inconsistencies between the two sources
        var symbolIdsToRemove = Set<String>()
        var allSymbols: [IndexedSymbol] = []

        for symbol in existing.symbols {
            if symbolIdsToRemove.insert(symbol.id).inserted {
                allSymbols.append(symbol)
            }
        }
        if let fileSymbols = symbolsByFile[relativePath] {
            for symbol in fileSymbols {
                if symbolIdsToRemove.insert(symbol.id).inserted {
                    allSymbols.append(symbol)
                }
            }
        }

        // Remove symbols from symbolsByName and symbolsByKind
        for symbol in allSymbols {
            let key = symbol.name.lowercased()
            symbolsByName[key]?.removeAll { $0.id == symbol.id }
            if symbolsByName[key]?.isEmpty == true {
                symbolsByName.removeValue(forKey: key)
            }
            symbolsByKind[symbol.kind]?.removeAll { $0.id == symbol.id }
            if symbolsByKind[symbol.kind]?.isEmpty == true {
                symbolsByKind.removeValue(forKey: symbol.kind)
            }
            if totalSymbolsExtracted > 0 { totalSymbolsExtracted -= 1 }
        }
        symbolsByFile.removeValue(forKey: relativePath)
        contentHashes.removeValue(forKey: existing.absolutePath)
        indexedFiles.removeValue(forKey: relativePath)
    }

    func buildImportGraph() {
        importGraph.removeAll()
        reverseImportGraph.removeAll()

        for (relativePath, indexed) in indexedFiles {
            let uniqueImports = Array(Set(indexed.imports)).sorted()
            importGraph[relativePath] = uniqueImports
            for imp in uniqueImports {
                reverseImportGraph[imp, default: []].append(relativePath)
            }
        }
    }

    func countDirectories(_ node: FileNode) -> Int {
        if node.kind != .directory { return 0 }
        return 1 + node.children.reduce(0) { $0 + countDirectories($1) }
    }

    func languageBreakdown() -> [FileLanguage: Int] {
        var counts: [FileLanguage: Int] = [:]
        for indexed in indexedFiles.values {
            counts[indexed.language, default: 0] += 1
        }
        return counts
    }

    private func fileNodeMetadata(for url: URL, fileManager: FileManager) -> FileNodeMetadata? {
        if let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        ), let isDirectory = values.isDirectory {
            return FileNodeMetadata(
                isDirectory: isDirectory,
                size: UInt64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }

        var isDirectoryFlag: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectoryFlag) else {
            return nil
        }
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        return FileNodeMetadata(
            isDirectory: isDirectoryFlag.boolValue,
            size: attrs?[.size] as? UInt64 ?? 0,
            modifiedAt: attrs?[.modificationDate] as? Date ?? .distantPast
        )
    }
}
