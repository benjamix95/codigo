import Foundation

struct WorktreeSession: Codable, Equatable, Identifiable {
    var id: UUID { conversationId }
    let conversationId: UUID
    var localRootPath: String
    var worktreePath: String
    var worktreeBranch: String
    var baseBranch: String
    var mergeTargetBranch: String
    var autoMergeOnReturn: Bool
    var deleteBranchAfterMerge: Bool
    var createdAt: Date
    var lastUpdatedAt: Date

    init(
        conversationId: UUID,
        localRootPath: String,
        worktreePath: String,
        worktreeBranch: String,
        baseBranch: String,
        mergeTargetBranch: String,
        autoMergeOnReturn: Bool,
        deleteBranchAfterMerge: Bool,
        createdAt: Date = .now,
        lastUpdatedAt: Date = .now
    ) {
        self.conversationId = conversationId
        self.localRootPath = localRootPath
        self.worktreePath = worktreePath
        self.worktreeBranch = worktreeBranch
        self.baseBranch = baseBranch
        self.mergeTargetBranch = mergeTargetBranch
        self.autoMergeOnReturn = autoMergeOnReturn
        self.deleteBranchAfterMerge = deleteBranchAfterMerge
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}
