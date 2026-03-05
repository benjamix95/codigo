import XCTest
@testable import CoderEngine

final class ReplayRunnerTests: XCTestCase {

    private let runner = ReplayRunner()

    private func makeSnapshot() -> ReplaySnapshot {
        ReplaySnapshot(
            jobSnapshotPath: "artifacts/job_1.json",
            eventLogPath: "artifacts/events.ndjson",
            providerSelection: [
                ProviderSelection(phase: "planning", provider: "codex-cli"),
            ],
            seed: "seed-1"
        )
    }

    private func makeEntry(
        jobId: String = "job_1",
        event: String = "task_started",
        phase: String = "executing",
        taskId: String? = "T1",
        seq: UInt64 = 1
    ) -> EventLogEntry {
        EventLogEntry(
            jobId: jobId,
            taskId: taskId,
            phase: phase,
            event: event,
            sequenceNumber: seq
        )
    }

    // MARK: - Extract Decisions

    func testExtractDecisions_filtersOrchestratorEvents() {
        let entries = [
            makeEntry(event: "task_started", seq: 1),
            makeEntry(event: "plan_created", seq: 2),
            makeEntry(event: "task_completed", seq: 3),
        ]
        let decisions = runner.extractDecisions(from: entries)
        XCTAssertEqual(decisions.count, 2)
        XCTAssertEqual(decisions[0].event, "task_started")
        XCTAssertEqual(decisions[1].event, "task_completed")
    }

    func testExtractDecisions_sortsBySequence() {
        let entries = [
            makeEntry(event: "task_completed", seq: 3),
            makeEntry(event: "task_started", seq: 1),
        ]
        let decisions = runner.extractDecisions(from: entries)
        XCTAssertEqual(decisions.first?.sequenceNumber, 1)
    }

    func testExtractDecisions_empty() {
        let decisions = runner.extractDecisions(from: [])
        XCTAssertTrue(decisions.isEmpty)
    }

    // MARK: - Compare Runs

    func testCompare_identicalRuns_noDivergences() {
        let d1 = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_started",
                phase: "executing", jobId: "j1", taskId: "T1"
            ),
        ]
        let divergences = runner.compare(original: d1, replay: d1)
        XCTAssertTrue(divergences.isEmpty)
    }

    func testCompare_eventDivergence() {
        let original = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_started",
                phase: "executing", jobId: "j1"
            ),
        ]
        let replay = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_failed",
                phase: "executing", jobId: "j1"
            ),
        ]
        let divergences = runner.compare(
            original: original, replay: replay
        )
        XCTAssertEqual(divergences.count, 1)
        XCTAssertTrue(divergences[0].reason.contains("event"))
    }

    func testCompare_phaseDivergence() {
        let original = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_started",
                phase: "executing", jobId: "j1"
            ),
        ]
        let replay = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_started",
                phase: "reviewing", jobId: "j1"
            ),
        ]
        let divergences = runner.compare(
            original: original, replay: replay
        )
        XCTAssertEqual(divergences.count, 1)
        XCTAssertTrue(divergences[0].reason.contains("phase"))
    }

    func testCompare_missingInReplay() {
        let original = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_started",
                phase: "executing", jobId: "j1"
            ),
            ReplayDecision(
                sequenceNumber: 2, event: "task_completed",
                phase: "executing", jobId: "j1"
            ),
        ]
        let replay = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_started",
                phase: "executing", jobId: "j1"
            ),
        ]
        let divergences = runner.compare(
            original: original, replay: replay
        )
        XCTAssertEqual(divergences.count, 1)
        XCTAssertTrue(divergences[0].reason.contains("missing"))
    }

    func testCompare_extraInReplay() {
        let original = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_started",
                phase: "executing", jobId: "j1"
            ),
        ]
        let replay = [
            ReplayDecision(
                sequenceNumber: 1, event: "task_started",
                phase: "executing", jobId: "j1"
            ),
            ReplayDecision(
                sequenceNumber: 2, event: "task_completed",
                phase: "executing", jobId: "j1"
            ),
        ]
        let divergences = runner.compare(
            original: original, replay: replay
        )
        XCTAssertEqual(divergences.count, 1)
        XCTAssertTrue(divergences[0].reason.contains("Extra"))
    }

    // MARK: - Replay

    func testReplay_fullMatch() throws {
        let entries = [
            makeEntry(event: "task_started", seq: 1),
            makeEntry(event: "task_completed", seq: 2),
        ]
        let report = try runner.replay(
            snapshot: makeSnapshot(),
            originalEntries: entries,
            replayEntries: entries
        )
        XCTAssertTrue(report.isFullMatch)
        XCTAssertEqual(report.matchRate, 1.0, accuracy: 0.001)
        XCTAssertEqual(report.totalDecisions, 2)
    }

    func testReplay_withDivergences() throws {
        let original = [
            makeEntry(event: "task_started", seq: 1),
            makeEntry(event: "task_completed", seq: 2),
        ]
        let replay = [
            makeEntry(event: "task_started", seq: 1),
            makeEntry(event: "task_failed", seq: 2),
        ]
        let report = try runner.replay(
            snapshot: makeSnapshot(),
            originalEntries: original,
            replayEntries: replay
        )
        XCTAssertFalse(report.isFullMatch)
        XCTAssertEqual(report.divergences.count, 1)
    }

    func testReplay_emptyLog_throws() {
        do {
            _ = try runner.replay(
                snapshot: makeSnapshot(),
                originalEntries: [],
                replayEntries: []
            )
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is ReplayRunnerError)
        }
    }

    func testReplay_invalidSnapshot_throws() {
        let invalid = ReplaySnapshot(
            jobSnapshotPath: "",
            eventLogPath: "events.ndjson"
        )
        do {
            _ = try runner.replay(
                snapshot: invalid,
                originalEntries: [makeEntry()],
                replayEntries: [makeEntry()]
            )
            XCTFail("Expected validation error")
        } catch {}
    }

    // MARK: - ReplayReport

    func testReplayReport_matchRate() {
        let report = ReplayReport(
            snapshot: makeSnapshot(),
            totalDecisions: 10,
            matchedDecisions: 8,
            divergences: [],
            replayDurationMs: 100
        )
        XCTAssertEqual(report.matchRate, 0.8, accuracy: 0.001)
    }

    func testReplayReport_zeroDecisions() {
        let report = ReplayReport(
            snapshot: makeSnapshot(),
            totalDecisions: 0,
            matchedDecisions: 0,
            divergences: [],
            replayDurationMs: 0
        )
        XCTAssertEqual(report.matchRate, 0)
    }
}
