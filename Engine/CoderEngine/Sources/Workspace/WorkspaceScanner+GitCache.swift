import Foundation

extension WorkspaceScanner {
    struct GitScanCacheKey: Hashable {
        let mode: String
        let workspacePath: String
        let excludedFingerprint: String
    }

    private struct GitScanCacheEntry {
        let files: [String]
        let createdAt: Date
    }

    static let gitScanCacheTTL: TimeInterval = 0.75
    static let gitScanCacheLock = NSLock()
    private static var gitScanCache: [GitScanCacheKey: GitScanCacheEntry] = [:]
    static var gitCommandRunnerForTests: ((URL, [String]) -> (status: Int32, output: String)?)?

    static func cachedGitScan(
        mode: String,
        workspacePath: URL,
        excludedPaths: [String],
        loader: () -> [String]
    ) -> [String] {
        let cacheKey = GitScanCacheKey(
            mode: mode,
            workspacePath: workspacePath.standardizedFileURL.path,
            excludedFingerprint: excludedPaths.sorted().joined(separator: "\n")
        )
        let now = Date()

        gitScanCacheLock.lock()
        if let cached = gitScanCache[cacheKey],
           now.timeIntervalSince(cached.createdAt) <= gitScanCacheTTL {
            gitScanCacheLock.unlock()
            return cached.files
        }
        gitScanCacheLock.unlock()

        let files = loader()

        gitScanCacheLock.lock()
        gitScanCache[cacheKey] = GitScanCacheEntry(files: files, createdAt: now)
        if gitScanCache.count > 32,
           let oldestKey = gitScanCache.min(by: { lhs, rhs in
               lhs.value.createdAt < rhs.value.createdAt
           })?.key {
            gitScanCache.removeValue(forKey: oldestKey)
        }
        gitScanCacheLock.unlock()
        return files
    }

    static func cachedGitInventorySourceFiles(
        workspacePath: URL,
        excludedPaths: [String]
    ) -> [String]? {
        let files = cachedGitScan(
            mode: "inventory",
            workspacePath: workspacePath,
            excludedPaths: excludedPaths
        ) {
            guard let output = runGitCommand(
                workspacePath: workspacePath,
                arguments: ["ls-files", "--cached", "--others", "--exclude-standard", "--"]
            ) else {
                return []
            }
            return listSourceFilesFromGitDiffOutput(
                output: output,
                workspacePath: workspacePath,
                excludedPaths: excludedPaths
            )
        }
        return files.isEmpty ? nil : files
    }

    static func runGitCommand(
        workspacePath: URL,
        arguments: [String]
    ) -> String? {
        if let runner = gitCommandRunnerForTests {
            guard let result = runner(workspacePath, arguments),
                  result.status == 0 else {
                return nil
            }
            return result.output
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workspacePath
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func resetGitScanCacheForTests() {
        gitScanCacheLock.lock()
        gitScanCache.removeAll()
        gitScanCacheLock.unlock()
        gitCommandRunnerForTests = nil
    }
}
