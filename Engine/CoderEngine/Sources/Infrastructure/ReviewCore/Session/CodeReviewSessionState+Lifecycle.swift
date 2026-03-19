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
        self.phase = .analyzing
        self.stage = .analysis
        self.scope = scope
        self.workspacePath = workspacePath
        self.findings = []
        self.candidates = []
        self.patches = []
        self.events = []
        self.currentRound = 0
        self.activeWorkerCount = 0
        self.startedAt = Date()
        self.completedAt = nil
        self.analysisCompletedAt = nil
        self.lastError = nil
        self.currentJobId = nil
        self.lastTestStatus = nil
        self.audit = .empty
        self.outcome = .empty
        self.phaseLedger = []
        self.fileLedger = []

        events.append(.sessionStarted(scope: scope.description, fileCount: scope.files.count))
        notifyChange()
    }

    public func complete() {
        phase = .completed
        stage = .completed
        completedAt = Date()
        activeWorkerCount = 0
        currentJobId = nil
        outcome = snapshot().buildOutcomeSummary()
        events.append(CodeReviewSessionEvent(
            type: .sessionCompleted,
            detail: "Review completed with \(findings.count) findings"
        ))
        notifyChange()
    }

    public func fail(error: String) {
        phase = .failed
        stage = .failed
        lastError = error
        completedAt = Date()
        activeWorkerCount = 0
        currentJobId = nil
        outcome = snapshot().buildOutcomeSummary(summaryOverride: "Review failed: \(error)")
        events.append(.error(error))
        notifyChange()
    }

    public func reset() {
        phase = .idle
        stage = .idle
        findings = []
        candidates = []
        patches = []
        events = []
        scope = nil
        workspacePath = nil
        currentRound = 0
        activeWorkerCount = 0
        startedAt = nil
        completedAt = nil
        analysisCompletedAt = nil
        lastError = nil
        currentJobId = nil
        lastTestStatus = nil
        audit = .empty
        outcome = .empty
        phaseLedger = []
        fileLedger = []
        notifyChange()
    }

    public func setPhase(_ newPhase: ReviewSessionPhase) {
        phase = newPhase
        notifyChange(mode: .coalesced)
    }

    public func setStage(_ newStage: ReviewSessionStage) {
        stage = newStage
        notifyChange(mode: .coalesced)
    }

    public func setCurrentJobId(_ jobId: String?) {
        currentJobId = jobId
        notifyChange(mode: .coalesced)
    }

    public func markAnalysisStarted() {
        phase = .analyzing
        stage = .analysis
        events.append(CodeReviewSessionEvent(type: .analysisStarted, detail: "Analysis started"))
        notifyChange()
    }

    public func markAnalysisCompleted() {
        analysisCompletedAt = Date()
        stage = .findings
        events.append(CodeReviewSessionEvent(type: .analysisCompleted, detail: "Analysis completed"))
        notifyChange()
    }

    public func markAuditStarted(toolName: String) {
        events.append(CodeReviewSessionEvent(
            type: .auditStarted,
            detail: "Running \(toolName)",
            metadata: ["tool": toolName]
        ))
        notifyChange(mode: .coalesced)
    }

    public func recordAuditResult(_ result: ReviewAuditToolResult) {
        var coverage = audit.toolCoverage
        coverage[result.toolName] = result.coverageAvailable

        var durations = audit.toolDurationsMs
        durations[result.toolName] = result.durationMs

        var findingsCounts = audit.toolFindingsCounts
        findingsCounts[result.toolName] = result.findings.count

        var adapters = audit.toolAdapters
        adapters[result.toolName] = result.adaptersUsed

        audit = ReviewAuditSnapshot(
            toolCoverage: coverage,
            toolDurationsMs: durations,
            toolFindingsCounts: findingsCounts,
            toolAdapters: adapters
        )

        events.append(CodeReviewSessionEvent(
            type: .auditCompleted,
            detail: result.summary,
            metadata: [
                "tool": result.toolName,
                "coverage": result.coverageAvailable ? "true" : "false",
                "duration_ms": String(result.durationMs),
                "findings_count": String(result.findings.count),
            ]
        ))
        notifyChange()
    }

    public func startRound(_ round: Int) {
        currentRound = round
        phase = .fixing
        stage = .fixing
        events.append(.roundStarted(round: round, maxRounds: config.maxRounds))
        notifyChange()
    }

    public func setActiveWorkerCount(_ count: Int) {
        activeWorkerCount = count
        notifyChange(mode: .coalesced)
    }

    public func markWorkerSpawned(workerId: String, title: String) {
        events.append(CodeReviewSessionEvent(
            type: .workerSpawned,
            detail: title,
            metadata: ["worker_id": workerId]
        ))
        notifyChange(mode: .coalesced)
    }

    public func markWorkerCompleted(workerId: String, title: String) {
        events.append(CodeReviewSessionEvent(
            type: .workerCompleted,
            detail: title,
            metadata: ["worker_id": workerId]
        ))
        notifyChange(mode: .coalesced)
    }

    public func markRoundCompleted(_ round: Int) {
        events.append(CodeReviewSessionEvent(
            type: .roundCompleted,
            detail: "Round \(round) completed",
            metadata: ["round": String(round)]
        ))
        notifyChange()
    }

    public func markTestingStarted() {
        phase = .testing
        stage = .testing
        notifyChange()
    }

    public func markTestResult(_ result: ReviewSessionTestStatus, detail: String) {
        phase = .testing
        stage = .testing
        lastTestStatus = result
        let type: CodeReviewSessionEvent.EventType = result == .passed ? .testsPassed : .testsFailed
        events.append(CodeReviewSessionEvent(type: type, detail: detail))
        notifyChange()
    }

    public func markReReviewStarted(round: Int) {
        phase = .reReviewing
        stage = .reReview
        events.append(CodeReviewSessionEvent(
            type: .analysisStarted,
            detail: "Re-review round \(round) started",
            metadata: ["round": String(round), "stage": "re_review"]
        ))
        notifyChange()
    }
}
