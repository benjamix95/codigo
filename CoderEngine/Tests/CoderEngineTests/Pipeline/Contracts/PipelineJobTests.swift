import XCTest
@testable import CoderEngine

final class PipelineJobTests: XCTestCase {

    // MARK: - Default values

    func testPipelineJob_defaultValues() {
        let job = PipelineJob(
            jobId: "job_001",
            workspace: "/tmp/repo",
            request: "Add feature X"
        )
        XCTAssertEqual(job.mode, .strict)
        XCTAssertEqual(job.state, .intake)
        XCTAssertEqual(job.policyVersion, "v2.4")
        XCTAssertEqual(job.jobTimeoutMs, 1_800_000)
        XCTAssertEqual(job.maxConcurrentWorkers, 4)
        XCTAssertEqual(job.errorBudget.maxFailedTasksPercent, 30)
        XCTAssertEqual(job.errorBudget.maxConsecutiveFailures, 5)
        XCTAssertEqual(job.rollbackStrategy, .gitBranch)
    }

    // MARK: - Coding round-trip

    func testPipelineJob_codingRoundTrip() throws {
        let job = PipelineJob(
            jobId: "job_rt",
            workspace: "/abs/path",
            request: "Test request",
            mode: .fast,
            state: .planning,
            jobTimeoutMs: 600_000,
            maxConcurrentWorkers: 2,
            errorBudget: ErrorBudget(maxFailedTasksPercent: 50, maxConsecutiveFailures: 10),
            rollbackStrategy: .gitStash
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(job)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PipelineJob.self, from: data)

        XCTAssertEqual(job.jobId, decoded.jobId)
        XCTAssertEqual(job.mode, decoded.mode)
        XCTAssertEqual(job.state, decoded.state)
        XCTAssertEqual(job.jobTimeoutMs, decoded.jobTimeoutMs)
        XCTAssertEqual(job.maxConcurrentWorkers, decoded.maxConcurrentWorkers)
        XCTAssertEqual(job.rollbackStrategy, decoded.rollbackStrategy)
    }

    // MARK: - JSON key format

    func testPipelineJob_jsonKeys() throws {
        let job = PipelineJob(
            jobId: "j1", workspace: "/w", request: "r"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(job)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"job_id\""))
        XCTAssertTrue(json.contains("\"job_timeout_ms\""))
        XCTAssertTrue(json.contains("\"max_concurrent_workers\""))
        XCTAssertTrue(json.contains("\"error_budget\""))
        XCTAssertTrue(json.contains("\"rollback_strategy\""))
        XCTAssertTrue(json.contains("\"policy_version\""))
    }

    // MARK: - Validation

    func testPipelineJob_validationPass() throws {
        let job = PipelineJob(
            jobId: "j1", workspace: "/w", request: "do stuff"
        )
        XCTAssertNoThrow(try job.validate())
    }

    func testPipelineJob_emptyJobId_fails() {
        let job = PipelineJob(jobId: "", workspace: "/w", request: "r")
        XCTAssertThrowsError(try job.validate()) { error in
            guard case PipelineValidationError.missingRequiredField(let f, _) = error else {
                XCTFail("Wrong error type"); return
            }
            XCTAssertEqual(f, "job_id")
        }
    }

    func testPipelineJob_workersOutOfRange_fails() {
        let job = PipelineJob(
            jobId: "j1", workspace: "/w", request: "r",
            maxConcurrentWorkers: 20
        )
        XCTAssertThrowsError(try job.validate()) { error in
            guard case PipelineValidationError.valueOutOfRange(let f, _, _, _) = error else {
                XCTFail("Wrong error type"); return
            }
            XCTAssertEqual(f, "max_concurrent_workers")
        }
    }

    func testPipelineJob_timeoutZero_fails() {
        let job = PipelineJob(
            jobId: "j1", workspace: "/w", request: "r",
            jobTimeoutMs: 0
        )
        XCTAssertThrowsError(try job.validate())
    }

    // MARK: - ErrorBudget validation

    func testErrorBudget_validationPass() throws {
        let budget = ErrorBudget(maxFailedTasksPercent: 50, maxConsecutiveFailures: 10)
        XCTAssertNoThrow(try budget.validate())
    }

    func testErrorBudget_percentOutOfRange_fails() {
        let budget = ErrorBudget(maxFailedTasksPercent: 0, maxConsecutiveFailures: 5)
        XCTAssertThrowsError(try budget.validate())
    }

    func testErrorBudget_consecutiveOutOfRange_fails() {
        let budget = ErrorBudget(maxFailedTasksPercent: 30, maxConsecutiveFailures: 25)
        XCTAssertThrowsError(try budget.validate())
    }

    // MARK: - SwarmBudgetConfig

    func testSwarmBudgetConfig_codingRoundTrip() throws {
        let config = SwarmBudgetConfig(
            maxExplorersPerTask: 5,
            adaptive: false
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SwarmBudgetConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }
}
