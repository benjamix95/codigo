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
            severity: .warning, category: .correctness,
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
            CodeReviewFinding(severity: .critical, category: .correctness, filePath: "a.swift", message: "crash"),
            CodeReviewFinding(severity: .warning, category: .maintainability, filePath: "b.swift", message: "style"),
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
            id: "f1", severity: .warning, category: .correctness,
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
            id: "f2", severity: .suggestion, category: .maintainability,
            filePath: "a.swift", message: "naming"
        )
        await state.addFinding(finding)
        let result = await state.dismissFinding(findingId: "f2", reason: "by_design")

        XCTAssertTrue(result)
        let snap = await state.snapshot()
        XCTAssertEqual(snap.findings.first?.status, .dismissed)
    }

    func testDismissFindingMarksWontFixStatus() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)

        let finding = CodeReviewFinding(
            id: "f2", severity: .suggestion, category: .maintainability,
            filePath: "a.swift", message: "naming"
        )
        await state.addFinding(finding)
        let result = await state.dismissFinding(findingId: "f2", reason: "wont_fix")

        XCTAssertTrue(result)
        let snap = await state.snapshot()
        XCTAssertEqual(snap.findings.first?.status, .wontFix)
    }

    func testAddComment() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)

        let finding = CodeReviewFinding(
            id: "f3", severity: .warning, category: .correctness,
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

    func testReplaceOpenFindingsKeepsClosedEntries() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)
        await state.addFindings([
            CodeReviewFinding(id: "open-1", severity: .warning, category: .correctness, filePath: "a.swift", message: "old open"),
            CodeReviewFinding(id: "fixed-1", severity: .warning, category: .correctness, filePath: "a.swift", message: "old fixed", status: .fixApplied),
        ])

        await state.replaceOpenFindings(with: [
            CodeReviewFinding(id: "open-2", severity: .critical, category: .security, filePath: "a.swift", message: "new open")
        ])

        let snap = await state.snapshot()
        XCTAssertEqual(snap.findings.map(\.id).sorted(), ["fixed-1", "open-2"])
    }

    func testMarkAllOpenFindingsAsFixApplied() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift"])
        await state.start(scope: scope)
        await state.addFindings([
            CodeReviewFinding(id: "open-1", severity: .warning, category: .correctness, filePath: "a.swift", message: "old open"),
            CodeReviewFinding(id: "open-2", severity: .critical, category: .security, filePath: "a.swift", message: "old open 2"),
        ])

        await state.markAllOpenFindingsAsFixApplied()

        let snap = await state.snapshot()
        XCTAssertTrue(snap.findings.allSatisfy { $0.status == .fixApplied })
    }

    // MARK: - Snapshot Computed Properties

    func testSnapshotGroupedProperties() async {
        let state = CodeReviewSessionState()
        let scope = ReviewSessionScope(type: .uncommitted, files: ["a.swift", "b.swift"])
        await state.start(scope: scope)

        await state.addFindings([
            CodeReviewFinding(id: "1", severity: .critical, category: .correctness, filePath: "a.swift", message: "crash"),
            CodeReviewFinding(id: "2", severity: .warning, category: .maintainability, filePath: "a.swift", message: "naming"),
            CodeReviewFinding(id: "3", severity: .critical, category: .security, filePath: "b.swift", message: "xss"),
        ])
        _ = await state.applyFix(findingId: "1")

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

    func testCoalescesWorkerLifecycleCallbacks() async {
        let state = CodeReviewSessionState()
        let callbackExpectation = XCTestExpectation(description: "coalesced callback fired once")
        callbackExpectation.expectedFulfillmentCount = 1
        let counter = CallbackCounter()

        await state.setOnStateChange { snapshot in
            if snapshot.events.contains(where: { $0.type == .workerCompleted }) {
                Task { await counter.increment() }
                callbackExpectation.fulfill()
            }
        }

        await state.setActiveWorkerCount(1)
        await state.markWorkerSpawned(workerId: "worker-1", title: "Worker 1")
        await state.markWorkerCompleted(workerId: "worker-1", title: "Worker 1")

        await fulfillment(of: [callbackExpectation], timeout: 2.0)
        try? await Task.sleep(nanoseconds: 80_000_000)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testImmediateMilestoneCancelsPendingCoalescedEmission() async {
        let state = CodeReviewSessionState()
        let callbackExpectation = XCTestExpectation(description: "milestone callback fired")
        callbackExpectation.expectedFulfillmentCount = 1
        let counter = CallbackCounter()

        await state.setOnStateChange { snapshot in
            if snapshot.events.contains(where: { $0.type == .roundCompleted }) {
                Task { await counter.increment() }
                callbackExpectation.fulfill()
            }
        }

        await state.setActiveWorkerCount(2)
        await state.markRoundCompleted(1)

        await fulfillment(of: [callbackExpectation], timeout: 2.0)
        try? await Task.sleep(nanoseconds: 80_000_000)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }
}

private actor CallbackCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    var value: Int { count }
}
