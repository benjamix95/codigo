import XCTest
import CoderEngine
@testable import CoderIDEMCPServer

extension CodeReviewHandlerTests {
    func testReviewStartRejectsInvalidSessionIdFormat() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: ["session_id": "../../tmp/pwn"]
        )
        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("session_id"))
    }

    func testReviewStartRejectsQueuedDuplicateSessionId() {
        _ = MCPSharedState.enqueueCodeReviewCommand(
            action: "start",
            sessionId: "session-dup",
            conversationId: nil,
            payload: ["scope": "uncommitted", "session_id": "session-dup"]
        )

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: ["session_id": "session-dup"]
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("queued start"))
    }

    func testReviewStartRejectsInvalidAnalysisOnlyValue() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_start",
            args: ["analysis_only": "sometimes"]
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("analysis_only"))
    }

    func testReviewStatusFallsBackToOnlyActiveSessions() {
        let conversationId = UUID()
        _ = seedSnapshot(
            sessionId: "completed-session",
            conversationId: conversationId,
            phase: .completed
        )
        let active = seedSnapshot(
            sessionId: "active-session",
            conversationId: conversationId,
            phase: .fixing
        )

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_status",
            args: ["conversation_id": conversationId.uuidString.lowercased()]
        )

        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains(active.sessionId))
    }

    func testReviewApplyFixRejectsFindingOutsideSession() {
        let snapshot = seedSnapshot()

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_apply_fix",
            args: reviewSessionArgs(snapshot, extras: ["finding_id": "missing-finding"])
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("does not belong"))
    }

    func testReviewCommentRejectsFindingOutsideSession() {
        let snapshot = seedSnapshot()

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_comment",
            args: reviewSessionArgs(snapshot, extras: [
                "finding_id": "missing-finding",
                "content": "not valid"
            ])
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("does not belong"))
    }

    func testReviewListSessionsWithoutConversationIncludesConversationScopedSessions() {
        let snapshot = seedSnapshot()

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_list_sessions",
            args: [:]
        )

        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains(snapshot.sessionId))
    }

    func testReviewConfigureAcceptsAnalysisOnlyWithoutOtherFields() {
        let snapshot = seedSnapshot()

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_configure",
            args: reviewSessionArgs(snapshot, extras: ["analysis_only": "true"])
        )

        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("queued"))
    }

    func testReviewStatusFailsClosedWhenRustCoreIsForcedOff() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }

        let snapshot = seedSnapshot(phase: .analyzing)
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_status",
            args: reviewSessionArgs(snapshot)
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("Rust review core unavailable for review_status"))
    }

    func testReviewFindingsFailsClosedWhenRustCoreIsForcedOff() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }

        let snapshot = seedSnapshot()
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: reviewSessionArgs(snapshot)
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("Rust review core unavailable for review_findings"))
    }

    func testReviewRevalidateFindingFailsClosedWhenRustCoreIsForcedOff() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }

        let patch = ReviewPatchArtifact(
            id: "patch-fallback-1",
            findingId: "f123",
            patchText: "diff --git a/Package.swift b/Package.swift",
            diffPreview: "@@",
            touchedFiles: ["Package.swift"],
            status: .applied,
            verifyStatus: .verified,
            validationStatus: .passed
        )
        let snapshot = seedSnapshot().copying(patches: [patch])
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_revalidate_finding",
            args: reviewSessionArgs(snapshot, extras: ["finding_id": "f123"])
        )

        XCTAssertEqual(result?.isError, true)
        XCTAssertTrue(textContent(result).contains("Rust review core unavailable for review_revalidate_finding"))
    }

    func testReviewFindingsOmitsSensitiveDetailsFromOutput() {
        let snapshot = seedSnapshot()

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: reviewSessionArgs(snapshot)
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("Findings"))
        XCTAssertTrue(text.contains("Redacted"))
        XCTAssertTrue(text.contains("redacted-swift-file-"))
        XCTAssertTrue(text.contains("origin: bugHunter"))
        XCTAssertTrue(text.contains("category: correctness"))
        XCTAssertFalse(text.contains("Package.swift"))
        XCTAssertFalse(text.contains("Test finding"))
        XCTAssertFalse(text.contains("? —"))
    }

    func testReviewFindingsDoesNotFallBackToCompletedSessionWhenNoActiveSessionExists() {
        let conversationId = UUID()
        _ = seedSnapshot(
            sessionId: "completed-findings",
            conversationId: conversationId,
            phase: .completed
        )

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: ["conversation_id": conversationId.uuidString.lowercased()]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("No review session found.") || text.contains("No active review session."))
    }
}

final class CodeReviewHandlerFailClosedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    func testReviewRevalidateFindingFailsClosedWhenRustCoreIsForcedOff() {
        let patch = ReviewPatchArtifact(
            id: "patch-fallback-1",
            findingId: "f123",
            patchText: "diff --git a/Package.swift b/Package.swift",
            diffPreview: "@@",
            touchedFiles: ["Package.swift"],
            status: .applied,
            verifyStatus: .verified,
            validationStatus: .passed
        )
        let conversationId = UUID()
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "review-session-fail-closed",
            conversationId: conversationId,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "f123",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Package.swift",
                    lineNumber: 17,
                    message: "Test finding"
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        ).copying(patches: [patch])
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_revalidate_finding",
            args: [
                "session_id": snapshot.sessionId,
                "conversation_id": conversationId.uuidString.lowercased(),
                "finding_id": "f123",
            ]
        )

        XCTAssertEqual(result?.isError, true)
        let text: String
        if let first = result?.content.first, case .text(let value) = first {
            text = value
        } else {
            text = ""
        }
        XCTAssertTrue(text.contains("Rust review core unavailable for review_revalidate_finding"))
    }
}
