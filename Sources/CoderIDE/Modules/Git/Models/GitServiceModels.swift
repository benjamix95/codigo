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
    let isStaged: Bool
}

struct GitStashEntry: Identifiable, Equatable {
    var id: Int { index }
    let index: Int
    let message: String
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

struct GitWorktreeCreateRequest: Equatable {
    let gitRoot: String
    let branchName: String
    let fromBranch: String
    let worktreePath: String
}

struct GitAutoMergeReport: Equatable {
    let localRootPath: String
    let worktreePath: String
    let worktreeBranch: String
    let mergeTargetBranch: String
    let steps: [String]
    let deletedWorktree: Bool
    let deletedBranch: Bool
}

struct GitMergeStartResult: Equatable {
    let hadConflicts: Bool
    let output: String
}

enum GitDiffBaseline: Equatable {
    case head
    case worktree
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
            return "Working directory is unavailable."
        case .notGitRepository:
            return "No Git repository in the active context."
        case .branchNotFound(let branch):
            return "Branch not found: \(branch)."
        case .noChangesToCommit:
            return "No changes to commit."
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
