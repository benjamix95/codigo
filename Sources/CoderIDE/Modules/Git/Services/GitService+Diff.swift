import Foundation

extension GitService {
    func fileDiff(
        gitRoot: String,
        path: String,
        baseline: GitDiffBaseline = .head
    ) throws -> GitFileDiff {
        let diffArgs: [String]
        switch baseline {
        case .head:
            diffArgs = ["diff", "HEAD", "--", path]
        case .worktree:
            diffArgs = ["diff", "--", path]
        }
        let raw = try runGit(diffArgs, gitRoot: gitRoot)
        if raw.contains("Binary files") {
            return GitFileDiff(path: path, chunks: [], isBinary: true)
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return GitFileDiff(path: path, chunks: [], isBinary: false)
        }

        let lines = raw.components(separatedBy: .newlines)
        var chunks: [GitFileDiffChunk] = []
        var currentHeader = ""
        var currentLines: [String] = []
        for line in lines {
            if line.hasPrefix("@@") {
                if !currentHeader.isEmpty || !currentLines.isEmpty {
                    chunks.append(GitFileDiffChunk(header: currentHeader, lines: currentLines))
                }
                currentHeader = line
                currentLines = []
            } else if !line.hasPrefix("diff --git"),
                      !line.hasPrefix("index "),
                      !line.hasPrefix("--- "),
                      !line.hasPrefix("+++ ") {
                currentLines.append(line)
            }
        }
        if !currentHeader.isEmpty || !currentLines.isEmpty {
            chunks.append(GitFileDiffChunk(header: currentHeader, lines: currentLines))
        }
        return GitFileDiff(path: path, chunks: chunks, isBinary: false)
    }

    func restoreFile(gitRoot: String, path: String) throws {
        let statusLine = try runGit(["status", "--porcelain", "--", path], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if statusLine.hasPrefix("??") {
            let fullPath = URL(fileURLWithPath: gitRoot).appendingPathComponent(path).path
            guard fullPath.hasPrefix(gitRoot + "/") || fullPath == gitRoot else {
                throw GitServiceError.commandFailed("Path fuori repository: \(path)")
            }
            try? FileManager.default.removeItem(atPath: fullPath)
            return
        }
        _ = try runGit(["restore", "--worktree", "--", path], gitRoot: gitRoot)
    }

    func restoreAll(gitRoot: String) throws {
        _ = try runGit(["restore", "--worktree", ":/"], gitRoot: gitRoot)
        let untracked = try runGit(["ls-files", "--others", "--exclude-standard"], gitRoot: gitRoot)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        for path in untracked {
            let fullPath = URL(fileURLWithPath: gitRoot).appendingPathComponent(path).path
            if fullPath.hasPrefix(gitRoot + "/") || fullPath == gitRoot {
                try? FileManager.default.removeItem(atPath: fullPath)
            }
        }
    }
}
