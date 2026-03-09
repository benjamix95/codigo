import Foundation

struct GitBranch: Identifiable, Equatable, Sendable {
    let id = UUID()
    let name: String
    let isCurrent: Bool
    let isRemoteTracking: Bool
}

struct GitStatusSummary: Equatable, Sendable {
    let changedFiles: Int
    let added: Int
    let removed: Int
    let modified: Int
    let untracked: Int
    let aheadBehind: String?
    let hasRemote: Bool
}

struct GitCommitResult: Equatable, Sendable {
    let sha: String
    let shortSha: String
    let subject: String
}

struct GitPRResult: Equatable, Sendable {
    let url: String
}

struct GitChangedFile: Identifiable, Equatable, Sendable {
    let id = UUID()
    let path: String
    let added: Int
    let removed: Int
    let status: String
    let isStaged: Bool
}

struct GitStashEntry: Identifiable, Equatable, Sendable {
    var id: Int { index }
    let index: Int
    let message: String
}

struct GitFileDiffChunk: Equatable, Sendable {
    let header: String
    let lines: [String]
}

struct GitFileDiff: Equatable, Sendable {
    let path: String
    let chunks: [GitFileDiffChunk]
    let isBinary: Bool
}

struct GitWorktreeCreateRequest: Equatable, Sendable {
    let gitRoot: String
    let branchName: String
    let fromBranch: String
    let worktreePath: String
}

struct GitAutoMergeReport: Equatable, Sendable {
    let localRootPath: String
    let worktreePath: String
    let worktreeBranch: String
    let mergeTargetBranch: String
    let steps: [String]
    let deletedWorktree: Bool
    let deletedBranch: Bool
}

struct GitMergeStartResult: Equatable, Sendable {
    let hadConflicts: Bool
    let output: String
}

enum GitDiffBaseline: Equatable, Sendable {
    case head
    case worktree
}

struct GitLogEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let sha: String
    let shortSha: String
    let subject: String
    let authorName: String
    let relativeDate: String
}

enum GitServiceError: LocalizedError, Sendable {
    case missingWorkingDirectory
    case notGitRepository
    case branchNotFound(String)
    case noChangesToCommit
    case unstagedCommitNotAllowed
    case validationFailed(String)
    case missingRemote
    case ghNotInstalled
    case ghNotAuthenticated
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkingDirectory:
            return "Working directory is unavailable."
        case .notGitRepository:
            return "No Git repository in the active context."
        case .branchNotFound(let branch):
            return "Branch not found: \(branch)."
        case .noChangesToCommit:
            return "No changes to commit."
        case .unstagedCommitNotAllowed:
            return "Il commit locale richiede staging selettivo: i file unstaged non vengono inclusi automaticamente."
        case .validationFailed(let message):
            return "Validation pipeline fallita: \(message)"
        case .missingRemote:
            return "Remote is not configured for this repository."
        case .ghNotInstalled:
            return "GitHub CLI (gh) is not installed."
        case .ghNotAuthenticated:
            return "GitHub CLI is not authenticated."
        case .commandFailed(let message):
            return message
        }
    }
}
