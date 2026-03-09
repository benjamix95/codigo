import Foundation

public enum MCPSharedBugHunterRunStatus: String, Codable, Sendable {
    case queued
    case running
    case awaitingApproval = "awaiting_approval"
    case revalidating
    case completed
    case failed
    case cancelled
}

public enum MCPSharedBugHunterSourceKind: String, Codable, Sendable {
    case uncommitted
    case commit
    case commitWindow = "commit_window"
    case branchWindow = "branch_window"
    case autofixRound = "autofix_round"
}

public enum MCPSharedBugHunterTriggerKind: String, Codable, Sendable {
    case manual
    case appCommit = "app_commit"
    case gitHook = "git_hook"
}

public struct MCPSharedBugHunterSnapshot: Codable, Sendable {
    public let runId: String
    public let conversationId: String?
    public let reviewSessionId: String?
    public let sourceKind: MCPSharedBugHunterSourceKind
    public let triggerKind: MCPSharedBugHunterTriggerKind
    public let gitRoot: String
    public let branchName: String?
    public let primaryCommit: String?
    public let relatedCommits: [String]
    public let status: MCPSharedBugHunterRunStatus
    public let startedAt: Date?
    public let completedAt: Date?
    public let lastUpdatedAt: Date
    public let lastMessage: String?
    public let autoFixMode: String
    public let cleanAfterFix: Bool
    public let verifiedFindingsCount: Int
    public let candidateFindingsCount: Int
    public let lastRevalidationVerdict: String?
    public let securityGateReady: Bool?

    public init(
        runId: String,
        conversationId: String? = nil,
        reviewSessionId: String? = nil,
        sourceKind: MCPSharedBugHunterSourceKind,
        triggerKind: MCPSharedBugHunterTriggerKind,
        gitRoot: String,
        branchName: String? = nil,
        primaryCommit: String? = nil,
        relatedCommits: [String] = [],
        status: MCPSharedBugHunterRunStatus,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        lastUpdatedAt: Date = Date(),
        lastMessage: String? = nil,
        autoFixMode: String = "manual_preview",
        cleanAfterFix: Bool = false,
        verifiedFindingsCount: Int = 0,
        candidateFindingsCount: Int = 0,
        lastRevalidationVerdict: String? = nil,
        securityGateReady: Bool? = nil
    ) {
        self.runId = runId
        self.conversationId = conversationId
        self.reviewSessionId = reviewSessionId
        self.sourceKind = sourceKind
        self.triggerKind = triggerKind
        self.gitRoot = gitRoot
        self.branchName = branchName
        self.primaryCommit = primaryCommit
        self.relatedCommits = relatedCommits
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.lastMessage = lastMessage
        self.autoFixMode = autoFixMode
        self.cleanAfterFix = cleanAfterFix
        self.verifiedFindingsCount = verifiedFindingsCount
        self.candidateFindingsCount = candidateFindingsCount
        self.lastRevalidationVerdict = lastRevalidationVerdict
        self.securityGateReady = securityGateReady
    }
}

public struct MCPSharedBugHunterCommand: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        case processing
        case completed
        case failed
    }

    public let id: String
    public let action: String
    public let runId: String
    public let conversationId: String?
    public let payload: [String: String]
    public let createdAt: Date
    public var updatedAt: Date
    public var status: Status
    public var resultMessage: String?
}

public struct MCPSharedBugHunterHookEvent: Codable, Sendable {
    public let id: String
    public let gitRoot: String
    public let headSHA: String
    public let createdAt: Date
}
