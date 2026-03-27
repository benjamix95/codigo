import Foundation

extension CodebaseIndex {
    struct IncrementalWorkspaceInventory {
        let sourceNodes: [String: FileNode]
        let requiresFullTreeRefresh: Bool
    }

    func collectIncrementalWorkspaceInventory() -> IncrementalWorkspaceInventory {
        var sourceNodes: [String: FileNode] = [:]
        for rootURL in currentWorkspacePaths {
            collectIncrementalSourceNodes(
                at: rootURL,
                relativePath: "",
                depth: 0,
                sourceNodes: &sourceNodes
            )
        }

        let currentSourcePaths = Set(sourceNodes.keys)
        let indexedPaths = Set(indexedFiles.keys)
        let removedPaths = indexedPaths.subtracting(currentSourcePaths)
        let addedPaths = currentSourcePaths.subtracting(indexedPaths)
        let requiresFullTreeRefresh = !removedPaths.isEmpty
            || !addedPaths.isEmpty
            || fileTrees.isEmpty
            || allFileNodes.isEmpty

        return IncrementalWorkspaceInventory(
            sourceNodes: sourceNodes,
            requiresFullTreeRefresh: requiresFullTreeRefresh
        )
    }

    private func collectIncrementalSourceNodes(
        at url: URL,
        relativePath: String,
        depth: Int,
        sourceNodes: inout [String: FileNode]
    ) {
        let fm = FileManager.default
        let name = url.lastPathComponent

        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        ), let isDirectory = values.isDirectory else {
            return
        }

        if isDirectory {
            let relPath = relativePath.isEmpty ? name : relativePath
            if Self.defaultExcludedDirs.contains(name)
                || isExcluded(name, relativePath: relPath)
                || isGitignored(relPath, isDirectory: true)
            {
                return
            }

            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            for childURL in contents.sorted(by: {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }) {
                let childRel = relPath.isEmpty
                    ? childURL.lastPathComponent
                    : "\(relPath)/\(childURL.lastPathComponent)"
                collectIncrementalSourceNodes(
                    at: childURL,
                    relativePath: childRel,
                    depth: depth + 1,
                    sourceNodes: &sourceNodes
                )
            }
            return
        }

        let ext = url.pathExtension.lowercased()
        guard Self.indexableExtensions.contains(ext) else { return }

        let relPath = relativePath.isEmpty ? name : relativePath
        guard !isFileExcluded(relPath), !isGitignored(relPath, isDirectory: false) else { return }

        let size = UInt64(values.fileSize ?? 0)
        guard size <= Self.maxFileSize else { return }

        sourceNodes[relPath] = FileNode(
            name: name,
            kind: .file,
            extension_: ext.isEmpty ? nil : ext,
            relativePath: relPath,
            absolutePath: url.path,
            depth: depth,
            size: size,
            modifiedAt: values.contentModificationDate ?? .distantPast
        )
    }

    func applyIncrementalWorkspaceInventory(
        _ inventory: IncrementalWorkspaceInventory
    ) {
        if inventory.requiresFullTreeRefresh {
            rebuildWorkspaceFileTrees()
            return
        }

        for (relativePath, node) in inventory.sourceNodes {
            allFileNodes[relativePath] = node
        }
    }
}
