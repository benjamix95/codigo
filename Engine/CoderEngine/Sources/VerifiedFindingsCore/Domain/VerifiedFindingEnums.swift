import Foundation

public enum VerifiedFindingDomain: String, Sendable, Codable, CaseIterable {
    case bug
    case security
}

public enum VerifiedFindingStatus: String, Sendable, Codable, CaseIterable {
    case candidate
    case verifying
    case verified
    case rejected
    case needsManualReview = "needs_manual_review"
    case patchPreparing = "patch_preparing"
    case patchPrepared = "patch_prepared"
    case patchReviewed = "patch_reviewed"
    case patchApplied = "patch_applied"
    case revalidating
    case fixedVerified = "fixed_verified"
    case fixFailed = "fix_failed"
    case rollbackApplied = "rollback_applied"
    case closed
}

public enum VerifiedFindingSeverity: String, Sendable, Codable, CaseIterable {
    case info
    case low
    case medium
    case high
    case critical
}

public enum VerifiedFindingReproducibility: String, Sendable, Codable, CaseIterable {
    case none
    case partial
    case full
}

public enum VerifiedFindingOriginEntryPoint: String, Sendable, Codable, CaseIterable {
    case panel
    case reviewChat = "review_chat"
    case mainChat = "main_chat"
    case hook
    case mcp
}

public enum VerifiedFindingStaleStatus: String, Sendable, Codable, CaseIterable {
    case active
    case stale
    case archived
}

public enum VerifiedEvidenceType: String, Sendable, Codable, CaseIterable {
    case codeSnippet = "code_snippet"
    case stackTrace = "stack_trace"
    case logExcerpt = "log_excerpt"
    case testFailure = "test_failure"
    case toolOutput = "tool_output"
    case dataFlow = "data_flow"
    case runtimeCheck = "runtime_check"
    case configSnapshot = "config_snapshot"
    case pocResult = "poc_result"
}

public enum VerifiedEvidenceSourceType: String, Sendable, Codable, CaseIterable {
    case test
    case log
    case scanner
    case runtimeCheck = "runtime_check"
    case codeExcerpt = "code_excerpt"
    case manualAssisted = "manual_assisted"
}

public enum VerifiedVisibilityLevel: String, Sendable, Codable, CaseIterable {
    case full
    case redacted
    case restricted
}

public enum VerifiedRetentionClass: String, Sendable, Codable, CaseIterable {
    case standard
    case sensitive
    case ephemeral
}

public enum VerificationVerdict: String, Sendable, Codable, CaseIterable {
    case verified
    case rejected
    case inconclusive
    case needsManualReview = "needs_manual_review"
}

public enum RevalidationVerdict: String, Sendable, Codable, CaseIterable {
    case fixedVerified = "fixed_verified"
    case fixFailed = "fix_failed"
    case inconclusive
}

public enum VerifiedFailureCategory: String, Sendable, Codable, CaseIterable {
    case transientToolFailure = "transient_tool_failure"
    case workspaceMismatch = "workspace_mismatch"
    case versionConflict = "version_conflict"
    case verificationInconclusive = "verification_inconclusive"
    case policyDenied = "policy_denied"
    case patchApplyFailed = "patch_apply_failed"
    case revalidationFailed = "revalidation_failed"
    case unsupportedVerificationPath = "unsupported_verification_path"
    case invalidCommand = "invalid_command"
    case entityLocked = "entity_locked"
    case budgetExceeded = "budget_exceeded"
}

public enum VerifiedFailurePhase: String, Sendable, Codable, CaseIterable {
    case discovery
    case verification
    case patchPreparation = "patch_preparation"
    case apply
    case revalidation
    case close
}

public enum VerifiedPatchStrategy: String, Sendable, Codable, CaseIterable {
    case minimalFix = "minimal_fix"
    case hardeningFix = "hardening_fix"
    case guardFix = "guard_fix"
    case rollbackFix = "rollback_fix"
}

public enum VerifiedRegressionRisk: String, Sendable, Codable, CaseIterable {
    case low
    case medium
    case high
}

public enum VerifiedPatchApplyStatus: String, Sendable, Codable, CaseIterable {
    case notApplied = "not_applied"
    case applying
    case applied
    case failed
    case rolledBack = "rolled_back"
}

public enum VerifiedRunStatus: String, Sendable, Codable, CaseIterable {
    case queued
    case running
    case completed
    case failed
    case timedOut = "timed_out"
    case cancelled
}

public enum VerifiedEntityType: String, Sendable, Codable, CaseIterable {
    case run
    case finding
    case patch
    case evidence
}
