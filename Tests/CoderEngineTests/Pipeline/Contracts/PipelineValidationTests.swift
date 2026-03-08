import XCTest
@testable import CoderEngine

final class PipelineValidationTests: XCTestCase {

    // MARK: - ReviewSession validation

    func testReviewSession_validationPass() throws {
        let session = ReviewSession(
            sessionId: "rev_01", jobId: "job_01", taskId: "T1"
        )
        XCTAssertNoThrow(try session.validate())
    }

    func testReviewSession_maxWorkersOutOfRange_fails() {
        let session = ReviewSession(
            sessionId: "rev_01", jobId: "job_01", taskId: "T1",
            maxWorkers: 20
        )
        XCTAssertThrowsError(try session.validate())
    }

    func testReviewSession_maxRoundsOutOfRange_fails() {
        let session = ReviewSession(
            sessionId: "rev_01", jobId: "job_01", taskId: "T1",
            maxRounds: 15
        )
        XCTAssertThrowsError(try session.validate())
    }

    func testReviewSession_criticalFindings() {
        var session = ReviewSession(
            sessionId: "rev_01", jobId: "job_01", taskId: "T1",
            findings: [
                ReviewFinding(
                    findingId: "f1", file: "A.swift",
                    severity: .critical, message: "Memory leak"
                )
            ]
        )
        XCTAssertTrue(session.hasCriticalFindings)

        session.findings[0].status = .fixApplied
        XCTAssertFalse(session.hasCriticalFindings)
    }

    func testReviewSession_convergenceBlocked() {
        let session = ReviewSession(
            sessionId: "rev_01", jobId: "job_01", taskId: "T1",
            maxRounds: 3, currentRound: 3,
            findings: [
                ReviewFinding(
                    findingId: "f1", file: "A.swift",
                    severity: .critical, message: "Bug"
                )
            ]
        )
        XCTAssertTrue(session.isConvergenceBlocked)
    }

    // MARK: - ProviderCapabilityMatrix validation

    func testProviderMatrix_validationPass() throws {
        let matrix = ProviderCapabilityMatrix(
            providers: [
                ProviderCapabilityEntry(providerId: "codex-cli", supportsWriteSubagent: true),
                ProviderCapabilityEntry(providerId: "claude-cli")
            ]
        )
        XCTAssertNoThrow(try matrix.validate())
    }

    func testProviderMatrix_emptyProviders_fails() {
        let matrix = ProviderCapabilityMatrix(providers: [])
        XCTAssertThrowsError(try matrix.validate())
    }

    func testProviderMatrix_duplicateIds_fails() {
        let matrix = ProviderCapabilityMatrix(
            providers: [
                ProviderCapabilityEntry(providerId: "same"),
                ProviderCapabilityEntry(providerId: "same")
            ]
        )
        XCTAssertThrowsError(try matrix.validate())
    }

    func testProviderMatrix_healthyProviders() {
        let matrix = ProviderCapabilityMatrix(
            providers: [
                ProviderCapabilityEntry(providerId: "a", healthStatus: .healthy),
                ProviderCapabilityEntry(providerId: "b", healthStatus: .unhealthy),
                ProviderCapabilityEntry(providerId: "c", healthStatus: .recovering)
            ]
        )
        XCTAssertEqual(matrix.healthyProviders.count, 2)
    }

    // MARK: - ProjectMemory validation

    func testProjectMemory_validationPass() throws {
        let mem = ProjectMemory(workspace: "/repo")
        XCTAssertNoThrow(try mem.validate())
    }

    func testProjectMemory_emptyWorkspace_fails() {
        let mem = ProjectMemory(workspace: "")
        XCTAssertThrowsError(try mem.validate())
    }

    func testProjectMemory_bugHistoryScore() {
        let mem = ProjectMemory(
            workspace: "/repo",
            fileBugHistory: [
                "A.swift": FileBugRecord(bugCount: 5),
                "B.swift": FileBugRecord(bugCount: 1)
            ]
        )
        XCTAssertEqual(mem.bugHistoryScore(for: "A.swift"), 1.0)
        XCTAssertEqual(mem.bugHistoryScore(for: "B.swift"), 0.2)
        XCTAssertEqual(mem.bugHistoryScore(for: "C.swift"), 0)
    }

    // MARK: - EventLogEntry validation

    func testEventLogEntry_validationPass() throws {
        let entry = EventLogEntry(
            jobId: "job_01", phase: "executing",
            event: "task_started", sequenceNumber: 1
        )
        XCTAssertNoThrow(try entry.validate())
    }

    func testEventLogEntry_emptyJobId_fails() {
        let entry = EventLogEntry(
            jobId: "", phase: "executing",
            event: "task_started", sequenceNumber: 1
        )
        XCTAssertThrowsError(try entry.validate())
    }

    // MARK: - EventBusEvent validation

    func testEventBusEvent_validationPass() throws {
        let event = EventBusEvent(
            eventId: "evt_01", jobId: "job_01",
            type: .taskStarted, idempotencyKey: "key_01"
        )
        XCTAssertNoThrow(try event.validate())
    }

    func testEventBusEvent_shouldDeadLetter() {
        var event = EventBusEvent(
            eventId: "evt_01", jobId: "job_01",
            type: .taskFailed, idempotencyKey: "key_01",
            deliveryStatus: .failed, deliveryAttempts: 3
        )
        XCTAssertTrue(event.shouldDeadLetter)

        event.deliveryAttempts = 2
        XCTAssertFalse(event.shouldDeadLetter)
    }

    // MARK: - CircuitBreakerState validation

    func testCircuitBreakerState_shouldTrip() {
        let state = CircuitBreakerState(
            jobId: "j1", consecutiveFailures: 5,
            totalFailures: 4, totalTasks: 10
        )
        let budget = ErrorBudget(maxFailedTasksPercent: 30, maxConsecutiveFailures: 5)
        XCTAssertTrue(state.shouldTrip(budget: budget))
    }

    func testCircuitBreakerState_noTripUnder5Tasks() {
        let state = CircuitBreakerState(
            jobId: "j1", consecutiveFailures: 10,
            totalFailures: 3, totalTasks: 3
        )
        let budget = ErrorBudget()
        XCTAssertFalse(state.shouldTrip(budget: budget))
    }

    func testCircuitBreakerState_errorBudgetRemaining() {
        let state = CircuitBreakerState(
            jobId: "j1", totalFailures: 2, totalTasks: 10
        )
        let budget = ErrorBudget(maxFailedTasksPercent: 30)
        XCTAssertEqual(state.errorBudgetRemaining(budget: budget), 10, accuracy: 0.01)
    }

    // MARK: - ReplaySnapshot validation

    func testReplaySnapshot_validationPass() throws {
        let snap = ReplaySnapshot(
            jobSnapshotPath: "path/to/job.json",
            eventLogPath: "path/to/events.ndjson"
        )
        XCTAssertNoThrow(try snap.validate())
    }

    func testReplaySnapshot_emptyPath_fails() {
        let snap = ReplaySnapshot(jobSnapshotPath: "", eventLogPath: "e.ndjson")
        XCTAssertThrowsError(try snap.validate())
    }

    // MARK: - RollbackRecord validation

    func testRollbackRecord_validationPass() throws {
        let record = RollbackRecord(
            rollbackId: "rb_01", jobId: "j1", taskId: "T1",
            patchId: "p_01", strategy: .gitBranch,
            rollbackRef: "branch:rollback_p_01",
            filesRestored: ["A.swift"]
        )
        XCTAssertNoThrow(try record.validate())
    }

    func testRollbackRecord_emptyFiles_fails() {
        let record = RollbackRecord(
            rollbackId: "rb_01", jobId: "j1", taskId: "T1",
            patchId: "p_01", strategy: .gitBranch,
            rollbackRef: "branch:rollback_p_01",
            filesRestored: []
        )
        XCTAssertThrowsError(try record.validate())
    }

    func testRollbackRecord_durationAndOvertime() {
        let start = Date()
        let end = start.addingTimeInterval(12)
        let record = RollbackRecord(
            rollbackId: "rb_01", jobId: "j1", taskId: "T1",
            patchId: "p_01", strategy: .gitBranch,
            rollbackRef: "ref", filesRestored: ["A.swift"],
            startedAt: start, completedAt: end, status: .success
        )
        XCTAssertNotNil(record.durationMs)
        XCTAssertTrue(record.isOvertime)
    }

    func testRollbackRecord_notOvertimeWhenFast() {
        let start = Date()
        let end = start.addingTimeInterval(2)
        let record = RollbackRecord(
            rollbackId: "rb_01", jobId: "j1", taskId: "T1",
            patchId: "p_01", strategy: .gitStash,
            rollbackRef: "ref", filesRestored: ["A.swift"],
            startedAt: start, completedAt: end, status: .success
        )
        XCTAssertFalse(record.isOvertime)
    }

    // MARK: - PipelineValidationError descriptions

    func testValidationError_descriptions() {
        let errors: [PipelineValidationError] = [
            .missingRequiredField(field: "f", contract: "C"),
            .valueOutOfRange(field: "f", contract: "C", value: "v", range: "r"),
            .invalidEnumValue(field: "f", contract: "C", value: "v"),
            .invalidTransition(from: "a", to: "b", contract: "C"),
            .constraintViolation(field: "f", contract: "C", reason: "r")
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
