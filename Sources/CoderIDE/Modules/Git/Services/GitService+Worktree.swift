import Foundation

extension GitService {
    struct GitWorktreePreflightResult: Equatable, Sendable {
        let gitRoot: String
        let branchName: String
        let fromBranch: String
        let worktreePath: String
    }

    func createWorktree(request: GitWorktreeCreateRequest) throws {
        try createWorktree(
            gitRoot: request.gitRoot,
            branchName: request.branchName,
            fromBranch: request.fromBranch,
            worktreePath: request.worktreePath
        )
    }

    func createWorktree(
        gitRoot: String,
        branchName: String,
        fromBranch: String,
        worktreePath: String
    ) throws {
        let preflight = try preflightCreateWorktree(
            gitRoot: gitRoot,
            branchName: branchName,
            fromBranch: fromBranch,
            worktreePath: worktreePath
        )

        let parent = (preflight.worktreePath as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            try FileManager.default.createDirectory(
                atPath: parent,
                withIntermediateDirectories: true
            )
        }
        _ = try runGit(
            ["worktree", "add", "-b", preflight.branchName, preflight.worktreePath, preflight.fromBranch],
            gitRoot: preflight.gitRoot
        )
    }

    func preflightCreateWorktree(
        gitRoot: String,
        branchName: String,
        fromBranch: String,
        worktreePath: String
    ) throws -> GitWorktreePreflightResult {
        let resolvedRoot = try resolveGitRoot(from: gitRoot)
        let trimmedPath = worktreePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw GitServiceError.commandFailed("Percorso worktree non valido.")
        }

        let validatedBranch = try validatedGitRef(branchName, label: "branch worktree")
        let validatedBase = try validatedGitRef(fromBranch, label: "branch base")
        let normalizedPath = normalizeWorktreePath(trimmedPath)

        try ensureBranchExists(name: validatedBase, gitRoot: resolvedRoot)
        try ensureBranchAbsent(name: validatedBranch, gitRoot: resolvedRoot)
        try ensureWorktreePathAvailable(normalizedPath, gitRoot: resolvedRoot)

        return GitWorktreePreflightResult(
            gitRoot: resolvedRoot,
            branchName: validatedBranch,
            fromBranch: validatedBase,
            worktreePath: normalizedPath
        )
    }

    func removeWorktree(gitRoot: String, worktreePath: String, force: Bool) throws {
        let trimmedPath = worktreePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw GitServiceError.commandFailed("Percorso worktree non valido.")
        }
        var args = ["worktree", "remove", trimmedPath]
        if force {
            args.append("--force")
        }
        _ = try runGit(args, gitRoot: gitRoot)
    }

    func listConflictedFiles(gitRoot: String) throws -> [String] {
        let out = try runGit(["diff", "--name-only", "--diff-filter=U"], gitRoot: gitRoot)
        return out
            .split(separator: "\n")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func worktreeStatusIsDirty(gitRoot: String) throws -> Bool {
        let out = try runGit(["status", "--porcelain"], gitRoot: gitRoot)
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func ensureBranchExists(name: String, gitRoot: String) throws {
        guard try branchExists(name: name, gitRoot: gitRoot) else {
            throw GitServiceError.branchNotFound(name)
        }
    }

    func ensureBranchAbsent(name: String, gitRoot: String) throws {
        if try branchExists(name: name, gitRoot: gitRoot) {
            throw GitServiceError.commandFailed("Il branch '\(name)' esiste già.")
        }
    }

    func branchExists(name: String, gitRoot: String) throws -> Bool {
        let branches = try listLocalBranches(gitRoot: gitRoot).map(\.name)
        return branches.contains(name)
    }

    func listWorktreePaths(gitRoot: String) throws -> [String] {
        let out = try runGit(["worktree", "list", "--porcelain"], gitRoot: gitRoot)
        return out
            .split(separator: "\n")
            .compactMap { line -> String? in
                let row = String(line)
                guard row.hasPrefix("worktree ") else { return nil }
                return normalizeWorktreePath(String(row.dropFirst("worktree ".count)))
            }
    }

    private func ensureWorktreePathAvailable(_ worktreePath: String, gitRoot: String) throws {
        let existingWorktrees = try listWorktreePaths(gitRoot: gitRoot)
        if existingWorktrees.contains(worktreePath) {
            throw GitServiceError.commandFailed("Esiste già un worktree registrato per \(worktreePath).")
        }

        if FileManager.default.fileExists(atPath: worktreePath) {
            throw GitServiceError.commandFailed("Il percorso worktree è già occupato: \(worktreePath)")
        }
    }

    private func normalizeWorktreePath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .path(percentEncoded: false)
    }
}
