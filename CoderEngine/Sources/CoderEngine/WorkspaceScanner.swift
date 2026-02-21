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

    /// Elenco file sorgente non committati (git status --porcelain: modified, added, untracked)
    public static func listUncommittedSourceFiles(workspacePath: URL, excludedPaths: [String] = []) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain", "-u"]
        process.currentDirectoryURL = workspacePath
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            guard line.count >= 3 else { continue }
            let chars = Array(line)
            let x = chars[0]
            let y = chars[1]
            let status = String([x, y])
            let startIndex = line.index(line.startIndex, offsetBy: 3)
            var path = String(line[startIndex...])
            if path.contains(" -> ") {
                path = String(path.components(separatedBy: " -> ").last ?? path)
            }
            if path.hasPrefix("\"") && path.hasSuffix("\"") {
                path = unquoteGitPath(path)
            }
            path = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let relevant = x == "M" || x == "A" || x == "R" || x == "C" || y == "M" || y == "A" || status == "??"
            let deleted = x == "D" || y == "D"
            guard !deleted else { continue }
            guard relevant else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            guard sourceExtensions.contains(ext) else { continue }
            let fullPath = workspacePath.appendingPathComponent(path).path
            if isExcluded(path: fullPath, basePath: workspacePath, excludedPaths: excludedPaths) { continue }
            if seen.insert(path).inserted {
                result.append(path)
            }
        }
        return result.sorted()
    }

    private static func unquoteGitPath(_ raw: String) -> String {
        guard raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else { return raw }
        let inner = String(raw.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

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
        let sortedContents = contents.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        for item in sortedContents {
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
