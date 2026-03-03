import Foundation

extension CodebaseIndex {
    public func indexSingleFile(absolutePath: String, relativePath: String) async {
        let canonicalRelativePath = canonicalRelativePath(for: absolutePath) ?? relativePath
        if isWorkspaceRebuildInProgress {
            queueRealtimeChange(kind: .upsert, absolutePath: absolutePath, relativePath: canonicalRelativePath)
            return
        }
        await applyRealtimeFileUpsert(absolutePath: absolutePath, canonicalRelativePath: canonicalRelativePath)
    }

    /// Remove a single file from the index (for real-time delete/rename updates).
    public func removeSingleFile(absolutePath: String, relativePath: String? = nil) async {
        let canonicalRelativePath = relativePath ?? canonicalRelativePath(for: absolutePath)
        guard let canonicalRelativePath else { return }
        if isWorkspaceRebuildInProgress {
            queueRealtimeChange(kind: .remove, absolutePath: absolutePath, relativePath: canonicalRelativePath)
            return
        }
        await applyRealtimeFileRemoval(absolutePath: absolutePath, canonicalRelativePath: canonicalRelativePath)
    }

    func applyRealtimeFileUpsert(absolutePath: String, canonicalRelativePath: String) async {
        // Remove old entry
        removeIndexedFile(canonicalRelativePath)

        // If file disappears between watcher event and read, clear stale semantic entries.
        guard FileManager.default.fileExists(atPath: absolutePath) else {
            allFileNodes.removeValue(forKey: canonicalRelativePath)
            await semanticIndex.removeFile(canonicalRelativePath)
            return
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: absolutePath) {
            let ext = (absolutePath as NSString).pathExtension.lowercased()
            let size = attrs[.size] as? UInt64 ?? 0
            let modDate = attrs[.modificationDate] as? Date ?? .distantPast
            let depth = canonicalRelativePath.split(separator: "/").count - 1
            let node = FileNode(
                name: (absolutePath as NSString).lastPathComponent,
                kind: .file,
                extension_: ext.isEmpty ? nil : ext,
                relativePath: canonicalRelativePath,
                absolutePath: absolutePath,
                depth: max(0, depth),
                size: size,
                modifiedAt: modDate
            )
            allFileNodes[canonicalRelativePath] = node

            let isIndexableSource =
                !ext.isEmpty
                && Self.indexableExtensions.contains(ext)
                && size <= Self.maxFileSize
                && !isFileExcluded(canonicalRelativePath)
                && !isGitignored(canonicalRelativePath, isDirectory: false)
            guard isIndexableSource else {
                await semanticIndex.removeFile(canonicalRelativePath)
                return
            }
        } else {
            allFileNodes.removeValue(forKey: canonicalRelativePath)
            await semanticIndex.removeFile(canonicalRelativePath)
            return
        }

        // Re-index
        if let indexed = SymbolExtractor.indexFile(
            absolutePath: absolutePath,
            relativePath: canonicalRelativePath
        ) {
            addIndexedFile(indexed)
            // Update semantic index for this file.
            await semanticIndex.updateFile(indexed)
        } else {
            allFileNodes.removeValue(forKey: canonicalRelativePath)
            await semanticIndex.removeFile(canonicalRelativePath)
        }
    }

    func applyRealtimeFileRemoval(absolutePath: String, canonicalRelativePath: String) async {
        removeIndexedFile(canonicalRelativePath)
        allFileNodes.removeValue(forKey: canonicalRelativePath)
        await semanticIndex.removeFile(canonicalRelativePath)
    }

    /// Resolve an absolute path to the internal relative path format used by the index.
    public func canonicalRelativePath(for absolutePath: String) -> String? {
        for rootURL in currentWorkspacePaths {
            let rootPath = rootURL.path
            if absolutePath == rootPath {
                return rootURL.lastPathComponent
            }
            let rootWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if absolutePath.hasPrefix(rootWithSlash) {
                let tail = String(absolutePath.dropFirst(rootWithSlash.count))
                let rootName = rootURL.lastPathComponent
                return tail.isEmpty ? rootName : "\(rootName)/\(tail)"
            }
        }
        return nil
    }

    /// Clear all index state and reset status to idle.
    public func clear() async {
        fileTrees.removeAll()
        indexedFiles.removeAll()
        symbolsByName.removeAll()
        symbolsByFile.removeAll()
        symbolsByKind.removeAll()
        allFileNodes.removeAll()
        importGraph.removeAll()
        reverseImportGraph.removeAll()
        contentHashes.removeAll()
        currentWorkspacePaths.removeAll()
        excludedPaths.removeAll()
        excludedFilePatterns.removeAll()
        gitignoreRules.removeAll()
        respectGitignore = true
        _indexingProgress = nil
        queuedRealtimeChanges.removeAll()
        isWorkspaceRebuildInProgress = false
        totalFilesScanned = 0
        totalSymbolsExtracted = 0
        indexDurationMs = 0
        lastFullIndexAt = nil
        _status = .idle
        await semanticIndex.clear()
    }

    // MARK: - Public API: Symbol Search

    // Additional symbol search APIs are implemented in CodebaseIndex+SymbolQueries.swift
}
