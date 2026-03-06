import Foundation

extension CodeReviewSessionState {
    public func start(scope: ReviewSessionScope) {
        self.phase = .analyzing
        self.stage = .analysis
        self.scope = scope
        self.findings = []
        self.events = []
        self.currentRound = 0
        self.activeWorkerCount = 0
        self.startedAt = Date()
        self.completedAt = nil
        self.analysisCompletedAt = nil
        self.lastError = nil
        self.currentJobId = nil
        self.lastTestStatus = nil

        events.append(.sessionStarted(scope: scope.description, fileCount: scope.files.count))
        notifyChange()
    }

    public func complete() {
        phase = .completed
        stage = .completed
        completedAt = Date()
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
        events.append(.error(error))
        notifyChange()
    }

    public func reset() {
        phase = .idle
        stage = .idle
        findings = []
        events = []
        scope = nil
        currentRound = 0
        activeWorkerCount = 0
        startedAt = nil
        completedAt = nil
        analysisCompletedAt = nil
        lastError = nil
        currentJobId = nil
        lastTestStatus = nil
        notifyChange()
    }

    public func setPhase(_ newPhase: ReviewSessionPhase) {
        phase = newPhase
        notifyChange()
    }

    public func setStage(_ newStage: ReviewSessionStage) {
        stage = newStage
        notifyChange()
    }

    public func setCurrentJobId(_ jobId: String?) {
        currentJobId = jobId
        notifyChange()
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

    public func startRound(_ round: Int) {
        currentRound = round
        phase = .fixing
        stage = .fixing
        events.append(.roundStarted(round: round, maxRounds: config.maxRounds))
        notifyChange()
    }

    public func setActiveWorkerCount(_ count: Int) {
        activeWorkerCount = count
        notifyChange()
    }

    public func markWorkerSpawned(workerId: String, title: String) {
        events.append(CodeReviewSessionEvent(
            type: .workerSpawned,
            detail: title,
            metadata: ["worker_id": workerId]
        ))
        notifyChange()
    }

    public func markWorkerCompleted(workerId: String, title: String) {
        events.append(CodeReviewSessionEvent(
            type: .workerCompleted,
            detail: title,
            metadata: ["worker_id": workerId]
        ))
        notifyChange()
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
