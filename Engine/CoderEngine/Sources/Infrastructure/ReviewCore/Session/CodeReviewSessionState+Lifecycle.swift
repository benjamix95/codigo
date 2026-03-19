import Foundation

extension CodeReviewSessionEvent {
    public enum EventType: String, Sendable, Codable, CaseIterable {
        case sessionStarted = "session_started"
        case analysisStarted = "analysis_started"
        case analysisCompleted = "analysis_completed"
        case auditStarted = "audit_started"
        case auditCompleted = "audit_completed"
        case candidateAdded = "candidate_added"
        case candidateVerified = "candidate_verified"
        case candidateRejected = "candidate_rejected"
        case findingAdded = "finding_added"
        case findingFixApplied = "finding_fix_applied"
        case findingDismissed = "finding_dismissed"
        case findingCommented = "finding_commented"
        case patchPrepared = "patch_prepared"
        case patchVerified = "patch_verified"
        case patchApplyFailed = "patch_apply_failed"
        case prOpened = "pr_opened"
        case prMerged = "pr_merged"
        case conflictDetected = "conflict_detected"
        case outcomePublished = "outcome_published"
        case roundStarted = "round_started"
        case roundCompleted = "round_completed"
        case workerSpawned = "worker_spawned"
        case workerCompleted = "worker_completed"
        case testsPassed = "tests_passed"
        case testsFailed = "tests_failed"
        case configUpdated = "config_updated"
        case sessionCompleted = "session_completed"
        case error = "error"
    }

    public static func sessionStarted(scope: String, fileCount: Int) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .sessionStarted,
            detail: "Review started with scope: \(scope)",
            metadata: ["scope": scope, "file_count": String(fileCount)]
        )
    }

    public static func candidateAdded(candidateId: String, filePath: String) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .candidateAdded,
            detail: filePath,
            metadata: ["candidate_id": candidateId, "file_path": filePath]
        )
    }

    public static func candidateVerified(candidateId: String) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .candidateVerified,
            detail: "Candidate \(candidateId) verified",
            metadata: ["candidate_id": candidateId]
        )
    }

    public static func candidateRejected(candidateId: String, reason: String) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .candidateRejected,
            detail: "Candidate \(candidateId) rejected",
            metadata: ["candidate_id": candidateId, "reason": reason]
        )
    }

    public static func roundStarted(round: Int, maxRounds: Int) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .roundStarted,
            detail: "Round \(round)/\(maxRounds)",
            metadata: ["round": String(round), "max_rounds": String(maxRounds)]
        )
    }

    public static func error(_ message: String) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(type: .error, detail: message)
    }
}

extension CodeReviewSessionState {
    public func start(
        scope: ReviewSessionScope,
        workspacePath: String? = nil
    ) {
        _ = applySessionAction(operation: "start") {
            $0.scope = scope
            $0.workspacePath = workspacePath
        }
    }

    public func complete() {
        _ = applySessionAction(operation: "complete")
    }

    public func fail(error: String) {
        _ = applySessionAction(operation: "fail") {
            $0.error = error
        }
    }

    public func reset() {
        _ = applySessionAction(operation: "reset")
    }

    public func setPhase(_ newPhase: ReviewSessionPhase) {
        _ = applySessionAction(operation: "set_phase", mode: .coalesced) {
            $0.phase = newPhase
        }
    }

    public func setStage(_ newStage: ReviewSessionStage) {
        _ = applySessionAction(operation: "set_stage", mode: .coalesced) {
            $0.stage = newStage
        }
    }

    public func setCurrentJobId(_ jobId: String?) {
        _ = applySessionAction(operation: "set_current_job_id", mode: .coalesced) {
            $0.jobId = jobId
        }
    }

    public func markAnalysisStarted() {
        _ = applySessionAction(operation: "mark_analysis_started")
    }

    public func markAnalysisCompleted() {
        _ = applySessionAction(operation: "mark_analysis_completed")
    }

    public func markAuditStarted(toolName: String) {
        _ = applySessionAction(operation: "mark_audit_started", mode: .coalesced) {
            $0.toolName = toolName
        }
    }

    public func recordAuditResult(_ result: ReviewAuditToolResult) {
        _ = applySessionAction(operation: "record_audit_result") {
            $0.auditResult = result
        }
    }

    public func startRound(_ round: Int) {
        _ = applySessionAction(operation: "start_round") {
            $0.round = round
        }
    }

    public func setActiveWorkerCount(_ count: Int) {
        _ = applySessionAction(operation: "set_active_worker_count", mode: .coalesced) {
            $0.count = count
        }
    }

    public func markWorkerSpawned(workerId: String, title: String) {
        _ = applySessionAction(operation: "mark_worker_spawned", mode: .coalesced) {
            $0.workerId = workerId
            $0.title = title
        }
    }

    public func markWorkerCompleted(workerId: String, title: String) {
        _ = applySessionAction(operation: "mark_worker_completed", mode: .coalesced) {
            $0.workerId = workerId
            $0.title = title
        }
    }

    public func markRoundCompleted(_ round: Int) {
        _ = applySessionAction(operation: "mark_round_completed") {
            $0.round = round
        }
    }

    public func markTestingStarted() {
        _ = applySessionAction(operation: "mark_testing_started")
    }

    public func markTestResult(_ result: ReviewSessionTestStatus, detail: String) {
        _ = applySessionAction(operation: "mark_test_result") {
            $0.testStatus = result
            $0.resultDetail = detail
        }
    }

    public func markReReviewStarted(round: Int) {
        _ = applySessionAction(operation: "mark_re_review_started") {
            $0.round = round
        }
    }
}
