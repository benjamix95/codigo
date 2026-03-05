import XCTest
@testable import CoderEngine

final class PipelineEventLoggerTests: XCTestCase {

    private func makeEntry(
        jobId: String = "job_1",
        phase: String = "executing",
        event: String = "task_started",
        seq: UInt64 = 0
    ) -> EventLogEntry {
        EventLogEntry(
            jobId: jobId,
            phase: phase,
            event: event,
            sequenceNumber: seq
        )
    }

    // MARK: - Append

    func testAppend_incrementsSequence() async throws {
        let logger = PipelineEventLogger()
        try await logger.append(makeEntry())
        try await logger.append(makeEntry())
        let seq = await logger.currentSequence()
        XCTAssertEqual(seq, 2)
    }

    func testAppend_enrichesSequenceNumber() async throws {
        let logger = PipelineEventLogger()
        try await logger.append(makeEntry())
        let entries = await logger.allEntries()
        XCTAssertEqual(entries.first?.sequenceNumber, 1)
    }

    func testAppend_afterShutdown_throws() async throws {
        let logger = PipelineEventLogger()
        await logger.shutdown()
        do {
            try await logger.append(makeEntry())
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is PipelineEventLoggerError)
        }
    }

    func testAppend_invalidEntry_throws() async {
        let logger = PipelineEventLogger()
        let invalid = EventLogEntry(
            jobId: "", phase: "x", event: "y", sequenceNumber: 0
        )
        do {
            try await logger.append(invalid)
            XCTFail("Expected validation error")
        } catch {}
    }

    // MARK: - Query

    func testEntries_forJob_filtersCorrectly() async throws {
        let logger = PipelineEventLogger()
        try await logger.append(makeEntry(jobId: "job_A"))
        try await logger.append(makeEntry(jobId: "job_B"))
        try await logger.append(makeEntry(jobId: "job_A"))
        let aEntries = await logger.entries(forJob: "job_A")
        XCTAssertEqual(aEntries.count, 2)
    }

    func testAllEntries_preservesOrder() async throws {
        let logger = PipelineEventLogger()
        try await logger.append(makeEntry(event: "e1"))
        try await logger.append(makeEntry(event: "e2"))
        try await logger.append(makeEntry(event: "e3"))
        let all = await logger.allEntries()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].event, "e1")
        XCTAssertEqual(all[2].event, "e3")
    }

    func testEntryCount() async throws {
        let logger = PipelineEventLogger()
        try await logger.append(makeEntry())
        let count = await logger.entryCount()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Job Sequences

    func testJobSequence_tracksPerJob() async throws {
        let logger = PipelineEventLogger()
        try await logger.append(makeEntry(jobId: "j1"))
        try await logger.append(makeEntry(jobId: "j2"))
        try await logger.append(makeEntry(jobId: "j1"))
        let j1Seq = await logger.jobSequence(for: "j1")
        let j2Seq = await logger.jobSequence(for: "j2")
        XCTAssertEqual(j1Seq, 2)
        XCTAssertEqual(j2Seq, 1)
    }

    // MARK: - NDJSON Export

    func testExportNDJSON_producesValidData() async throws {
        let logger = PipelineEventLogger()
        try await logger.append(makeEntry(event: "e1"))
        try await logger.append(makeEntry(event: "e2"))
        let data = try await logger.exportNDJSON()
        let string = String(data: data, encoding: .utf8)!
        let lines = string.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("e1"))
        XCTAssertTrue(lines[1].contains("e2"))
    }

    // MARK: - Reset

    func testReset_clearsAll() async throws {
        let logger = PipelineEventLogger()
        try await logger.append(makeEntry())
        await logger.reset()
        let count = await logger.entryCount()
        let seq = await logger.currentSequence()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(seq, 0)
    }

    // MARK: - Monotonic Sequence Guarantee

    func testSequenceNumbers_areMonotonic() async throws {
        let logger = PipelineEventLogger()
        for _ in 0..<10 {
            try await logger.append(makeEntry())
        }
        let all = await logger.allEntries()
        for i in 1..<all.count {
            XCTAssertGreaterThan(
                all[i].sequenceNumber,
                all[i - 1].sequenceNumber
            )
        }
    }
}
