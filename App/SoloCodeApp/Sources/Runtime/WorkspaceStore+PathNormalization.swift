import Foundation
import CoderEngine

@MainActor
extension WorkspaceStore {
    func normalizedWorkspacePath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded)
            .standardizedFileURL
            .path(percentEncoded: false)
        if standardized.count > 1 && standardized.hasSuffix("/") {
            return String(standardized.dropLast())
        }
        return standardized
    }

    func addNormalizedWorkspacePath(_ rawPath: String, to paths: inout [String]) -> Bool {
        let normalized = normalizedWorkspacePath(rawPath)
        guard !normalized.isEmpty else { return false }
        guard !paths.contains(where: { normalizedWorkspacePath($0) == normalized }) else { return false }
        paths.append(normalized)
        return true
    }

    func removeNormalizedWorkspacePath(_ rawPath: String, from paths: inout [String]) -> Bool {
        let normalized = normalizedWorkspacePath(rawPath)
        guard !normalized.isEmpty else { return false }
        let originalCount = paths.count
        paths.removeAll { normalizedWorkspacePath($0) == normalized }
        return paths.count != originalCount
    }

    func normalizePersistedWorkspacePaths() -> Bool {
        var didChange = false
        var normalizedWorkspaces: [Workspace] = []
        normalizedWorkspaces.reserveCapacity(workspaces.count)

        for workspace in workspaces {
            var normalizedWorkspace = workspace
            let normalizedFolders = normalizedUniqueWorkspacePaths(workspace.folderPaths)
            let normalizedExclusions = normalizedUniqueWorkspacePaths(workspace.excludedPaths)
            if normalizedFolders != workspace.folderPaths || normalizedExclusions != workspace.excludedPaths {
                didChange = true
            }
            normalizedWorkspace.folderPaths = normalizedFolders
            normalizedWorkspace.excludedPaths = normalizedExclusions
            normalizedWorkspaces.append(normalizedWorkspace)
        }

        if didChange {
            workspaces = normalizedWorkspaces
        }
        return didChange
    }

    func normalizedWorkspace(_ workspace: Workspace) -> Workspace {
        var normalizedWorkspace = workspace
        normalizedWorkspace.folderPaths = normalizedWorkspacePaths(workspace.folderPaths)
        normalizedWorkspace.excludedPaths = normalizedWorkspacePaths(workspace.excludedPaths)
        return normalizedWorkspace
    }

    func normalizedWorkspacePathsCSV(_ rawValue: String) -> [String] {
        normalizedWorkspacePaths(
            rawValue
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    func normalizedWorkspacePaths(_ rawPaths: [String]) -> [String] {
        normalizedUniqueWorkspacePaths(rawPaths)
    }

    func indexerExcludedPaths(for workspacePaths: [URL], excludedPaths: [String]) -> [String] {
        let normalizedRoots = workspacePaths.map {
            (url: $0, path: normalizedWorkspacePath($0.path), rootName: $0.lastPathComponent)
        }
        var seen = Set<String>()
        var relativeExclusions: [String] = []

        for rawExcludedPath in excludedPaths {
            let normalizedExcludedPath = normalizedWorkspacePath(rawExcludedPath)
            guard !normalizedExcludedPath.isEmpty else { continue }

            for root in normalizedRoots {
                if normalizedExcludedPath == root.path {
                    guard seen.insert(root.rootName).inserted else { break }
                    relativeExclusions.append(root.rootName)
                    break
                }

                let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                guard normalizedExcludedPath.hasPrefix(rootPrefix) else { continue }

                let suffix = String(normalizedExcludedPath.dropFirst(rootPrefix.count))
                guard !suffix.isEmpty else { continue }
                let relativePath = "\(root.rootName)/\(suffix)"
                guard seen.insert(relativePath).inserted else { break }
                relativeExclusions.append(relativePath)
                break
            }
        }

        return relativeExclusions
    }

    private func normalizedUniqueWorkspacePaths(_ rawPaths: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        normalized.reserveCapacity(rawPaths.count)

        for rawPath in rawPaths {
            let candidate = normalizedWorkspacePath(rawPath)
            guard !candidate.isEmpty else { continue }
            guard seen.insert(candidate).inserted else { continue }
            normalized.append(candidate)
        }
        return normalized
    }
}
