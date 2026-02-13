import Foundation

/// Scansiona il workspace per fornire contesto
public enum WorkspaceScanner {
    /// Controlla se un path è escluso
    public static func isExcluded(path: String, basePath: URL, excludedPaths: [String]) -> Bool {
        for excluded in excludedPaths {
            let excludedNorm = excluded.hasSuffix("/") ? String(excluded.dropLast()) : excluded
            if excludedNorm.hasPrefix("/") {
                if path == excludedNorm || path.hasPrefix(excludedNorm + "/") { return true }
            } else {
                let fullExcluded = basePath.appendingPathComponent(excludedNorm).path
                if path == fullExcluded || path.hasPrefix(fullExcluded + "/") { return true }
            }
        }
        return false
    }

    /// Elenco file nella root del workspace (max N), filtrando esclusi
    public static func listRootFiles(workspacePath: URL, excludedPaths: [String] = [], maxFiles: Int = 20) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: workspacePath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let defaultExcluded = ["node_modules", ".git", ".build", "build", "DerivedData"]
        let allExcluded = defaultExcluded + excludedPaths
        let filtered = contents.filter { item in
            !allExcluded.contains(item.lastPathComponent)
        }
        return filtered.prefix(maxFiles).map { $0.lastPathComponent }
    }

    /// Estensioni file sorgente per code review
    private static let sourceExtensions = ["swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "java", "kt", "rb", "php", "c", "cpp", "h", "hpp", "m", "mm"]

    /// Elenco ricorsivo di file sorgente nel workspace
    public static func listSourceFiles(workspacePath: URL, excludedPaths: [String] = []) -> [String] {
        let defaultExcluded = ["node_modules", ".git", ".build", "build", "DerivedData", "dist", "out"]
        let allExcluded = defaultExcluded + excludedPaths
        var result: [String] = []
        enumerateSourceFiles(
            at: workspacePath,
            basePath: workspacePath,
            relativePrefix: "",
            excludedDirs: Set(allExcluded),
            excludedPaths: excludedPaths,
            result: &result
        )
        return result
    }

    private static func enumerateSourceFiles(
        at url: URL,
        basePath: URL,
        relativePrefix: String,
        excludedDirs: Set<String>,
        excludedPaths: [String],
        result: inout [String]
    ) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            let name = item.lastPathComponent
            if excludedDirs.contains(name) { continue }
            let relPath = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
            if isExcluded(path: basePath.appendingPathComponent(relPath).path, basePath: basePath, excludedPaths: excludedPaths) {
                continue
            }
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue {
                enumerateSourceFiles(
                    at: item,
                    basePath: basePath,
                    relativePrefix: relPath,
                    excludedDirs: excludedDirs,
                    excludedPaths: excludedPaths,
                    result: &result
                )
            } else if sourceExtensions.contains(item.pathExtension.lowercased()) {
                result.append(relPath)
            }
        }
    }
}
