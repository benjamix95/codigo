import Foundation

extension CodebaseIndex {
    func buildFileTree(
        at url: URL,
        relativePath: String,
        depth: Int
    ) -> FileNode {
        let fm = FileManager.default
        let name = url.lastPathComponent

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return FileNode(
                name: name,
                kind: .file,
                extension_: url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased(),
                relativePath: relativePath.isEmpty ? name : relativePath,
                absolutePath: url.path,
                depth: depth
            )
        }

        if isDir.boolValue {
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
            var size: UInt64 = 0
            var modDate = Date.distantPast
            if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                size = attrs[.size] as? UInt64 ?? 0
                modDate = attrs[.modificationDate] as? Date ?? .distantPast
            }

            return FileNode(
                name: name,
                kind: .file,
                extension_: ext.isEmpty ? nil : ext,
                relativePath: relativePath.isEmpty ? name : relativePath,
                absolutePath: url.path,
                depth: depth,
                size: size,
                modifiedAt: modDate
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

        for symbol in indexed.symbols {
            let key = symbol.name.lowercased()
            symbolsByName[key, default: []].append(symbol)
            symbolsByFile[indexed.relativePath, default: []].append(symbol)
            symbolsByKind[symbol.kind, default: []].append(symbol)
            totalSymbolsExtracted += 1
        }
    }

    func removeIndexedFile(_ relativePath: String) {
        guard let existing = indexedFiles[relativePath] else { return }

        // Remove symbols
        for symbol in existing.symbols {
            let key = symbol.name.lowercased()
            symbolsByName[key]?.removeAll { $0.id == symbol.id }
            if symbolsByName[key]?.isEmpty == true {
                symbolsByName.removeValue(forKey: key)
            }
            symbolsByKind[symbol.kind]?.removeAll { $0.id == symbol.id }
            if symbolsByKind[symbol.kind]?.isEmpty == true {
                symbolsByKind.removeValue(forKey: symbol.kind)
            }
            totalSymbolsExtracted -= 1
        }
        symbolsByFile.removeValue(forKey: relativePath)
        contentHashes.removeValue(forKey: existing.absolutePath)
        indexedFiles.removeValue(forKey: relativePath)
    }

    func buildImportGraph() {
        importGraph.removeAll()
        reverseImportGraph.removeAll()

        for (relativePath, indexed) in indexedFiles {
            importGraph[relativePath] = indexed.imports
            for imp in indexed.imports {
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
}
