import XCTest
@testable import CoderEngine

final class CodeReviewSessionStateTests: XCTestCase {

    // MARK: - Session Lifecycle

    func testInitialStateIsIdle() async {
        let state = CodeReviewSessionState()
        let snap = await state.snapshot()
        XCTAssertEqual(snap.phase, .idle)
        XCTAssertTrue(snap.findings.isEmpty)
        XCTAssertTrue(snap.events.isEmpty)
        XCTAssertNil(snap.startedAt)
        XCTAssertNil(snap.completedAt)
    }

    func testStartTransitionsToAnalyzing() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift", "b.swift"])
        await state.start(scope: scope)
        let snap = await state.snapshot()

        XCTAssertEqual(snap.phase, .analyzing)
        XCTAssertNotNil(snap.startedAt)
        XCTAssertNil(snap.completedAt)
        XCTAssertEqual(snap.scope?.type, .uncommitted)
        XCTAssertEqual(snap.scope?.files.count, 2)
        XCTAssertEqual(snap.events.count, 1)
        XCTAssertEqual(snap.events.first?.type, .sessionStarted)
    }

    func testCompleteTransitionsToCompleted() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .staged, files: ["x.swift"])
        await state.start(scope: scope)
        await state.complete()
        let snap = await state.snapshot()

        XCTAssertEqual(snap.phase, .completed)
        XCTAssertNotNil(snap.completedAt)
        XCTAssertEqual(snap.events.last?.type, .sessionCompleted)
    }

    func testFailTransitionsToFailed() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: [])
        await state.start(scope: scope)
        await state.fail(error: "test error")
        let snap = await state.snapshot()

        XCTAssertEqual(snap.phase, .failed)
        XCTAssertEqual(snap.lastError, "test error")
        XCTAssertNotNil(snap.completedAt)
    }

    func testResetClearsState() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)
        await state.addFinding(CodeReviewFinding(
            severity: .warning, category: .bug,
            filePath: "a.swift", message: "test"
        ))
        await state.reset()
        let snap = await state.snapshot()

        XCTAssertEqual(snap.phase, .idle)
        XCTAssertTrue(snap.findings.isEmpty)
        XCTAssertTrue(snap.events.isEmpty)
        XCTAssertNil(snap.scope)
    }

    // MARK: - Findings

    func testAddFinding() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)

        let finding = CodeReviewFinding(
            severity: .critical, category: .security,
            filePath: "a.swift", lineNumber: 42,
            message: "SQL injection vulnerability"
        )
        await state.addFinding(finding)
        let snap = await state.snapshot()

        XCTAssertEqual(snap.findings.count, 1)
        XCTAssertEqual(snap.findings.first?.severity, .critical)
        XCTAssertEqual(snap.findings.first?.filePath, "a.swift")
        XCTAssertEqual(snap.findings.first?.lineNumber, 42)
    }

    func testAddMultipleFindings() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)

        let findings = [
            CodeReviewFinding(severity: .critical, category: .bug, filePath: "a.swift", message: "crash"),
            CodeReviewFinding(severity: .warning, category: .style, filePath: "b.swift", message: "style"),
        ]
        await state.addFindings(findings)
        let snap = await state.snapshot()

        XCTAssertEqual(snap.findings.count, 2)
    }

    func testApplyFix() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)

        let finding = CodeReviewFinding(
            id: "f1", severity: .warning, category: .bug,
            filePath: "a.swift", message: "test"
        )
        await state.addFinding(finding)
        let result = await state.applyFix(findingId: "f1")

        XCTAssertTrue(result)
        let snap = await state.snapshot()
        XCTAssertEqual(snap.findings.first?.status, .fixApplied)
    }

    func testApplyFixInvalidId() async {
        let state = CodeReviewSessionState()
        let result = await state.applyFix(findingId: "nonexistent")
        XCTAssertFalse(result)
    }

    func testDismissFinding() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)

        let finding = CodeReviewFinding(
            id: "f2", severity: .suggestion, category: .style,
            filePath: "a.swift", message: "naming"
        )
        await state.addFinding(finding)
        let result = await state.dismissFinding(findingId: "f2", reason: "by_design")

        XCTAssertTrue(result)
        let snap = await state.snapshot()
        XCTAssertEqual(snap.findings.first?.status, .dismissed)
    }

    func testAddComment() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)

        let finding = CodeReviewFinding(
            id: "f3", severity: .warning, category: .bug,
            filePath: "a.swift", message: "test"
        )
        await state.addFinding(finding)
        let comment = FindingComment(content: "This is expected behavior")
        let result = await state.addComment(findingId: "f3", comment: comment)

        XCTAssertTrue(result)
        let snap = await state.snapshot()
        XCTAssertEqual(snap.findings.first?.comments.count, 1)
        XCTAssertEqual(snap.findings.first?.comments.first?.content, "This is expected behavior")
    }

    // MARK: - Rounds & Workers

    func testStartRound() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)
        await state.startRound(2)
        let snap = await state.snapshot()

        XCTAssertEqual(snap.currentRound, 2)
        XCTAssertEqual(snap.phase, .fixing)
    }

    func testSetActiveWorkerCount() async {
        let state = CodeReviewSessionState()
        await state.setActiveWorkerCount(4)
        let snap = await state.snapshot()
        XCTAssertEqual(snap.activeWorkerCount, 4)
    }

    // MARK: - Config

    func testUpdateConfig() async {
        let state = CodeReviewSessionState()
        let newConfig = SessionConfig(maxWorkers: 8, maxRounds: 5)
        await state.updateConfig(newConfig)
        let snap = await state.snapshot()

        XCTAssertEqual(snap.config.maxWorkers, 8)
        XCTAssertEqual(snap.config.maxRounds, 5)
    }

    // MARK: - Snapshot Computed Properties

    func testSnapshotGroupedProperties() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift", "b.swift"])
        await state.start(scope: scope)

        await state.addFindings([
            CodeReviewFinding(id: "1", severity: .critical, category: .bug, filePath: "a.swift", message: "crash"),
            CodeReviewFinding(id: "2", severity: .warning, category: .style, filePath: "a.swift", message: "naming"),
            CodeReviewFinding(id: "3", severity: .critical, category: .security, filePath: "b.swift", message: "xss"),
        ])
        await state.applyFix(findingId: "1")

        let snap = await state.snapshot()

        XCTAssertEqual(snap.findingsByFile.count, 2)
        XCTAssertEqual(snap.findingsByFile["a.swift"]?.count, 2)
        XCTAssertEqual(snap.findingsBySeverity[.critical]?.count, 2)
        XCTAssertEqual(snap.openFindings.count, 2)
        XCTAssertTrue(snap.statusSummary.contains("3 findings"))
    }

    // MARK: - State Change Callback

    func testOnStateChangeCallback() async {
        let state = CodeReviewSessionState()
        let expectation = XCTestExpectation(description: "callback fired")
        expectation.expectedFulfillmentCount = 1

        await state.setOnStateChange { snapshot in
            if snapshot.phase == .analyzing {
                expectation.fulfill()
            }
        }

        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)

        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
