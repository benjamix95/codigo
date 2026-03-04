import Foundation

extension GitService {
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
        let trimmedBranch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = fromBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = worktreePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranch.isEmpty, !trimmedBase.isEmpty, !trimmedPath.isEmpty else {
            throw GitServiceError.commandFailed("Parametri worktree non validi.")
        }
        try ensureBranchAbsent(name: trimmedBranch, gitRoot: gitRoot)
        let parent = (trimmedPath as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            try FileManager.default.createDirectory(
                atPath: parent,
                withIntermediateDirectories: true
            )
        }
        _ = try runGit(
            ["worktree", "add", "-b", trimmedBranch, trimmedPath, trimmedBase],
            gitRoot: gitRoot
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
}
