import Foundation

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
}
