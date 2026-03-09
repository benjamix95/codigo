import Foundation

public struct VerifiedPatchHunk: Sendable, Codable, Equatable {
    public let startLineOld: Int?
    public let startLineNew: Int?
    public let diff: String
    public let summary: String
}

public struct VerifiedPatchFileChange: Sendable, Codable, Equatable {
    public let filePath: String
    public let hunks: [VerifiedPatchHunk]
}

public struct VerifiedPatchArtifact: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let findingId: String
    public let title: String
    public let strategy: VerifiedPatchStrategy
    public let fileChanges: [VerifiedPatchFileChange]
    public let rationale: String
    public let regressionRisk: VerifiedRegressionRisk
    public let linkedTestIds: [String]
    public let reversible: Bool
    public let version: Int
    public let workspaceId: String
    public let baseRevision: String?
    public let targetRevision: String?
    public let applyPreconditions: [String]
    public let rollbackAvailable: Bool
    public let applyStrategy: String
    public let applyStatus: VerifiedPatchApplyStatus
    public let applyError: String?
    public let errorCategory: VerifiedFailureCategory?
    public let failureReasonCode: String?
    public let retryable: Bool
    public let retryCount: Int
    public let maxRetryAllowed: Int
    public let containsSensitiveData: Bool
    public let redactionApplied: Bool
    public let retentionClass: VerifiedRetentionClass
    public let visibilityLevel: VerifiedVisibilityLevel
    public let createdAt: Date
    public let updatedAt: Date
}

public struct VerifiedRevalidationReport: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let findingId: String
    public let patchId: String
    public let verdict: RevalidationVerdict
    public let checksRun: [String]
    public let evidenceIds: [String]
    public let summary: String
    public let errorCategory: VerifiedFailureCategory?
    public let failureReasonCode: String?
    public let retryable: Bool
    public let retryCount: Int
    public let maxRetryAllowed: Int
    public let createdAt: Date
}

public struct VerifiedRunBudgetPolicy: Sendable, Codable, Equatable {
    public let name: String
    public let allowRetryOnTransientFailure: Bool

    public init(name: String = "default", allowRetryOnTransientFailure: Bool = true) {
        self.name = name
        self.allowRetryOnTransientFailure = allowRetryOnTransientFailure
    }
}

public struct VerifiedPipelineRun: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let status: VerifiedRunStatus
    public let domainScope: [VerifiedFindingDomain]
    public let workspaceId: String
    public let entryPoint: VerifiedFindingOriginEntryPoint
    public let budgetPolicy: VerifiedRunBudgetPolicy
    public let maxDuration: TimeInterval
    public let maxToolCalls: Int
    public let maxVerificationAttempts: Int
    public let maxPatchAttempts: Int
    public let maxRevalidationAttempts: Int
    public let timeoutAt: Date?
    public let cancelledAt: Date?
    public let cancelReason: String?
    public let toolCallCount: Int
    public let verificationAttemptCount: Int
    public let patchAttemptCount: Int
    public let revalidationAttemptCount: Int
    public let isCancellable: Bool
    public let eventSchemaVersion: Int
    public let entitySchemaVersion: Int
    public let projectionSchemaVersion: Int
    public let createdAt: Date
    public let updatedAt: Date
}

public struct VerifiedPipelineEvent: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let runId: String
    public let entityId: String
    public let entityType: VerifiedEntityType
    public let eventType: String
    public let payload: [String: String]
    public let eventSchemaVersion: Int
    public let entitySchemaVersion: Int
    public let migrationHint: String?
    public let createdAt: Date
}
