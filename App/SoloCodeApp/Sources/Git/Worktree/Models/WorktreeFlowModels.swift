import Foundation

struct WorktreeSheetBootstrap: Equatable, Sendable {
    let localRootPath: String
    let localBranches: [GitBranch]
    let currentBranch: String
    let suggestedBaseBranch: String
    let suggestedMergeTargetBranch: String
    let suggestedWorktreeBranch: String
}

enum WorktreeSheetLoadState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct WorktreeCreateFlowInput: Sendable {
    let conversationId: UUID
    let localRootPath: String
    let worktreePath: String
    let worktreeBranch: String
    let baseBranch: String
    let mergeTargetBranch: String
    let autoMergeOnReturn: Bool
    let deleteBranchAfterMerge: Bool
}

struct WorktreeCreationOutcome: Equatable, Sendable {
    let session: WorktreeSession
    let rollbackPerformed: Bool
    let didSwitchContext: Bool
}

enum WorktreeFlowError: LocalizedError, Equatable, Sendable {
    case preloadFailed(String)
    case validationFailed(String)
    case switchFailedAfterCreate(reason: String, rollbackPerformed: Bool)

    var errorDescription: String? {
        switch self {
        case .preloadFailed(let message),
             .validationFailed(let message):
            return message
        case .switchFailedAfterCreate(let reason, let rollbackPerformed):
            if rollbackPerformed {
                return "\(reason)\nRollback worktree completato."
            }
            return "\(reason)\nRollback worktree non completato."
        }
    }
}
