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

    func testReviewStatusFallsBackWhenRustCoreIsForcedOff() {
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

        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("session_id: \(snapshot.sessionId)"))
    }

    func testReviewFindingsFallsBackWhenRustCoreIsForcedOff() {
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

        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("Findings"))
        XCTAssertTrue(textContent(result).contains("redacted-swift-file-"))
    }

    func testReviewRevalidateFindingFallsBackWhenRustCoreIsForcedOff() {
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

        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("queued"))
    }
}
