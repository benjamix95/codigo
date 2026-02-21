import Foundation

struct GitBranch: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let isCurrent: Bool
    let isRemoteTracking: Bool
}

struct GitStatusSummary: Equatable {
    let changedFiles: Int
    let added: Int
    let removed: Int
    let modified: Int
    let untracked: Int
    let aheadBehind: String?
    let hasRemote: Bool
}

struct GitCommitResult: Equatable {
    let sha: String
    let shortSha: String
    let subject: String
}

struct GitPRResult: Equatable {
    let url: String
}

struct GitChangedFile: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let added: Int
    let removed: Int
    let status: String
}

struct GitFileDiffChunk: Equatable {
    let header: String
    let lines: [String]
}

struct GitFileDiff: Equatable {
    let path: String
    let chunks: [GitFileDiffChunk]
    let isBinary: Bool
}

struct GitLogEntry: Identifiable, Equatable {
    let id = UUID()
    let sha: String
    let shortSha: String
    let subject: String
    let authorName: String
    let relativeDate: String
}

enum GitServiceError: LocalizedError {
    case missingWorkingDirectory
    case notGitRepository
    case branchNotFound(String)
    case noChangesToCommit
    case missingRemote
    case ghNotInstalled
    case ghNotAuthenticated
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkingDirectory:
            return "Directory di lavoro non disponibile."
        case .notGitRepository:
            return "Nessuna repository Git nel contesto attivo."
        case .branchNotFound(let branch):
            return "Branch non trovato: \(branch)."
        case .noChangesToCommit:
            return "Nessuna modifica da committare."
        case .missingRemote:
            return "Remote non configurato per questo repository."
        case .ghNotInstalled:
            return "GitHub CLI (gh) non installato."
        case .ghNotAuthenticated:
            return "GitHub CLI non autenticato."
        case .commandFailed(let message):
            return message
        }
    }
}

struct GitService {
    private let gitPath = "/usr/bin/git"

    func resolveGitRoot(from workingDirectory: String?) throws -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            throw GitServiceError.missingWorkingDirectory
        }
        do {
            return try runCommand(
                executable: gitPath,
                args: ["rev-parse", "--show-toplevel"],
                cwd: workingDirectory
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw GitServiceError.notGitRepository
        }
    }

    func currentBranch(gitRoot: String) throws -> String {
        let out = try runGit(["branch", "--show-current"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return out }
        let detached = try runGit(["rev-parse", "--short", "HEAD"], gitRoot: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return detached.isEmpty ? "(detached)" : "detached@\(detached)"
    }

    func listLocalBranches(gitRoot: String) throws -> [GitBranch] {
        let current = try currentBranch(gitRoot: gitRoot)
        let out = try runGit(["for-each-ref", "--format=%(refname:short)|%(upstream:short)", "refs/heads"], gitRoot: gitRoot)
        let branches = out
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { row -> GitBranch in
                let parts = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                let name = parts.first ?? ""
                let upstream = parts.count > 1 ? parts[1] : ""
                return GitBranch(name: name, isCurrent: name == current, isRemoteTracking: !upstream.isEmpty)
            }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
                return lhs.name < rhs.name
            }
        return branches
    }

    func checkoutBranch(name: String, gitRoot: String) throws {
        let existing = try listLocalBranches(gitRoot: gitRoot).map(\.name)
        guard existing.contains(name) else {
            throw GitServiceError.branchNotFound(name)
        }
        _ = try runGit(["checkout", name], gitRoot: gitRoot)
    }

    func createAndCheckoutBranch(name: String, gitRoot: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitServiceError.commandFailed("Nome branch non valido.")
        }
        _ = try runGit(["checkout", "-b", trimmed], gitRoot: gitRoot)
    }

    func status(gitRoot: String) throws -> GitStatusSummary {
        let porcelain = try runGit(["status", "--porcelain"], gitRoot: gitRoot)
        let lines = porcelain.split(separator: "\n").map(String.init)
        var added = 0
        var removed = 0
        var modified = 0
        var untracked = 0
        for line in lines {
            guard line.count >= 2 else { continue }
            let prefix = String(line.prefix(2))
            if prefix == "??" {
                untracked += 1
                continue
            }
            let chars = Array(prefix)
            if chars.contains("A") { added += 1 }
            if chars.contains("D") { removed += 1 }
            if chars.contains("M") || chars.contains("R") || chars.contains("C") || chars.contains("T") {
                modified += 1
            }
        }
        let hasRemote = !(try runGit(["remote"], gitRoot: gitRoot).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let aheadBehind = try? runGit(["status", "-sb"], gitRoot: gitRoot)
            .split(separator: "\n")
            .first
            .map(String.init)
        return GitStatusSummary(
            changedFiles: lines.count,
            added: added,
            removed: removed,
            modified: modified,
            untracked: untracked,
            aheadBehind: aheadBehind,
            hasRemote: hasRemote
        )
    }

    func diffForCommitMessage(gitRoot: String, includeUnstaged: Bool) throws -> String {
        let args = includeUnstaged ? ["diff", "--cached", "HEAD", "--", ".", ":(exclude).git"] : ["diff", "--cached"]
        var diff = try runGit(args, gitRoot: gitRoot)
        if includeUnstaged {
            let unstaged = try runGit(["diff", "--", ".", ":(exclude).git"], gitRoot: gitRoot)
            if !unstaged.isEmpty {
                diff += "\n\n# Unstaged\n" + unstaged
            }
            let untracked = try runGit(["ls-files", "--others", "--exclude-standard"], gitRoot: gitRoot)
            if !untracked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diff += "\n\n# Untracked files\n" + untracked
            }
        }
        return diff
    }

    func commit(gitRoot: String, message: String, includeUnstaged: Bool) throws -> GitCommitResult {
        if includeUnstaged {
            _ = try runGit(["add", "-A"], gitRoot: gitRoot)
        }
        let st = try status(gitRoot: gitRoot)
        if st.changedFiles == 0 {
            throw GitServiceError.noChangesToCommit
        }
        _ = try runGit(["commit", "-m", message], gitRoot: gitRoot)
        let sha = try runGit(["rev-parse", "HEAD"], gitRoot: gitRoot).trimmingCharacters(in: .whitespacesAndNewlines)
        let short = try runGit(["rev-parse", "--short", "HEAD"], gitRoot: gitRoot).trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = try runGit(["log", "-1", "--pretty=%s"], gitRoot: gitRoot).trimmingCharacters(in: .whitespacesAndNewlines)
        return GitCommitResult(sha: sha, shortSha: short, subject: subject)
    }

    func push(gitRoot: String, branch: String) throws {
        let hasRemote = !(try runGit(["remote"], gitRoot: gitRoot).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        guard hasRemote else { throw GitServiceError.missingRemote }
        _ = try runGit(["push", "-u", "origin", branch], gitRoot: gitRoot)
    }

    func createPullRequest(gitRoot: String, base: String?, title: String, body: String?) throws -> GitPRResult {
        guard isGhInstalled() else { throw GitServiceError.ghNotInstalled }
        guard isGhAuthenticated(gitRoot: gitRoot) else { throw GitServiceError.ghNotAuthenticated }
        var args = ["pr", "create", "--title", title]
        if let body, !body.isEmpty {
            args += ["--body", body]
        } else {
            args += ["--body", ""]
        }
        if let base, !base.isEmpty {
            args += ["--base", base]
        }
        args += ["--fill-first", "--json", "url", "--jq", ".url"]
        let url = try runCommand(executable: "/usr/bin/env", args: ["gh"] + args, cwd: gitRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            throw GitServiceError.commandFailed("PR creata ma URL non disponibile.")
        }
        return GitPRResult(url: url)
    }

    func changedFiles(gitRoot: String) throws -> [GitChangedFile] {
        let porcelain = try runGit(["status", "--porcelain"], gitRoot: gitRoot)
        let lines = porcelain.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        var result: [GitChangedFile] = []
        for line in lines {
            guard line.count >= 4 else { continue }
            let statusCode = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            let rawPath = String(line.dropFirst(3))
            let path = rawPath.components(separatedBy: " -> ").last ?? rawPath

            var added = 0
            var removed = 0
            if statusCode != "??" {
                // Include both staged and unstaged deltas against HEAD for accurate file totals.
                let stat = try runGit(["diff", "--numstat", "HEAD", "--", path], gitRoot: gitRoot)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stat.isEmpty {
                    let comps = stat.split(separator: "\t")
                    if comps.count >= 2 {
                        added = Int(comps[0]) ?? 0
                        removed = Int(comps[1]) ?? 0
                    }
                }
            }

            result.append(GitChangedFile(path: path, added: added, removed: removed, status: statusCode.isEmpty ? "M" : statusCode))
        }
        return result
    }

    func commitHistory(gitRoot: String, limit: Int = 20) throws -> [GitLogEntry] {
        let format = "%H|%h|%an|%ar|%s"
        let out = try runGit(["log", "--format=\(format)", "-\(limit)"], gitRoot: gitRoot)
        return out
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .compactMap { line -> GitLogEntry? in
                let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 5 else { return nil }
                return GitLogEntry(
                    sha: parts[0],
                    shortSha: parts[1],
                    subject: parts[4],
                    authorName: parts[2],
                    relativeDate: parts[3]
                )
            }
    }

    func fileDiff(gitRoot: String, path: String) throws -> GitFileDiff {
        let raw = try runGit(["diff", "--", path], gitRoot: gitRoot)
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

    private func isGhInstalled() -> Bool {
        (try? runCommand(executable: "/usr/bin/env", args: ["which", "gh"], cwd: nil).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?? false
    }

    private func isGhAuthenticated(gitRoot: String) -> Bool {
        (try? runCommand(executable: "/usr/bin/env", args: ["gh", "auth", "status"], cwd: gitRoot)) != nil
    }

    @discardableResult
    private func runGit(_ args: [String], gitRoot: String) throws -> String {
        try runCommand(executable: gitPath, args: args, cwd: gitRoot)
    }

    @discardableResult
    private func runCommand(executable: String, args: [String], cwd: String?) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd, !cwd.isEmpty {
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            let cmd = ([executable] + args).joined(separator: " ")
            throw GitServiceError.commandFailed("Comando fallito (\(cmd)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return stdout
    }
}
