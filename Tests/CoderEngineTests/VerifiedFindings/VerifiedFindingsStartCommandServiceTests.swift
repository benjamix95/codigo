import XCTest
@testable import CoderEngine

final class VerifiedFindingsStartCommandServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        super.tearDown()
    }

    func testMakeRequestRejectsInvalidScope() {
        XCTAssertThrowsError(
            try VerifiedFindingsStartCommandService.makeRequest(
                args: ["scope": "invalid"],
                conversationId: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifiedFindingsStartCommandError,
                .invalidScope("invalid")
            )
        }
    }

    func testMakeRequestRequiresRefForAgainstRef() {
        XCTAssertThrowsError(
            try VerifiedFindingsStartCommandService.makeRequest(
                args: ["scope": "against_ref"],
                conversationId: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifiedFindingsStartCommandError,
                .missingRef
            )
        }
    }

    func testEnqueueReviewStartRejectsDuplicateQueuedSession() throws {
        let request = try VerifiedFindingsStartCommandService.makeRequest(
            args: ["session_id": "session-1"],
            conversationId: nil
        )
        _ = try VerifiedFindingsStartCommandService.enqueueReviewStart(request: request)

        XCTAssertThrowsError(
            try VerifiedFindingsStartCommandService.enqueueReviewStart(request: request)
        ) { error in
            XCTAssertEqual(
                error as? VerifiedFindingsStartCommandError,
                .sessionAlreadyQueued("session-1")
            )
        }
    }

    func testMakeRequestNormalizesPayloadAndConversation() throws {
        let conversationId = UUID()
        let request = try VerifiedFindingsStartCommandService.makeRequest(
            args: [
                "scope": "staged",
                "session_id": "session-2",
                "analysis_only": "true",
            ],
            conversationId: conversationId
        )

        XCTAssertEqual(request.scope, "staged")
        XCTAssertEqual(request.sessionId, "session-2")
        XCTAssertEqual(request.payload["scope"], "staged")
        XCTAssertEqual(request.payload["session_id"], "session-2")
        XCTAssertEqual(
            request.payload["conversation_id"],
            conversationId.uuidString.lowercased()
        )
    }

    func testSecurityWorkflowServiceInjectsSecurityPromptOverride() throws {
        let request = try SecurityWorkflowService.makeStartRequest(
            args: ["scope": "staged", "session_id": "security-session"],
            conversationId: nil
        )

        XCTAssertEqual(request.scope, "staged")
        XCTAssertEqual(request.sessionId, "security-session")
        XCTAssertTrue(
            request.payload["review_prompt_override"]?.contains("[MODE:security-audit]") == true
        )
        XCTAssertEqual(request.payload["analysis_only"], "true")
        XCTAssertEqual(request.payload["auto_prepare_verified_patches"], "true")
        XCTAssertEqual(request.payload["auto_prepare_origin_filter"], FindingOrigin.securityAuditor.rawValue)
    }

    func testBugHunterWorkflowServiceBuildsStartRequest() throws {
        let request = try BugHunterWorkflowService.makeStartRequest(
            runId: "run-1",
            reviewSessionId: "bughunter-review-run-1",
            sourceKind: .commit,
            againstRef: "HEAD~3",
            prompt: "[AGAINST:HEAD~3] [MODE:bug-hunter]",
            maxRounds: 4,
            maxWorkers: 5
        )

        XCTAssertEqual(request.scope, "against_ref")
        XCTAssertEqual(request.ref, "HEAD~3")
        XCTAssertEqual(request.payload["bughunter_run_id"], "run-1")
        XCTAssertEqual(request.payload["bughunter_profile"], "commit_review")
        XCTAssertEqual(request.payload["max_rounds"], "4")
        XCTAssertEqual(request.payload["max_workers"], "5")
        XCTAssertEqual(request.payload["analysis_only"], "true")
        XCTAssertEqual(request.payload["auto_prepare_verified_patches"], "true")
        XCTAssertEqual(request.payload["auto_prepare_origin_filter"], FindingOrigin.bugHunter.rawValue)
    }

    func testLifecycleQueueCloseFindingRejectsOpenFinding() throws {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "review-session-open",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "f-open",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Open finding"
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
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        XCTAssertThrowsError(
            try VerifiedFindingsLifecycleCommandService.queueFindingCommand(
                action: "close_finding",
                sessionId: "review-session-open",
                findingId: "f-open",
                conversationId: nil,
                payload: [
                    "session_id": "review-session-open",
                    "finding_id": "f-open",
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifiedFindingsLifecycleCommandError,
                .findingNotClosable
            )
        }
    }

    func testLifecycleQueueCloseFindingAcceptsMergedFinding() throws {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "review-session-merged",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "f-merged",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Merged finding",
                    status: .merged
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
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let queued = try VerifiedFindingsLifecycleCommandService.queueFindingCommand(
            action: "close_finding",
            sessionId: "review-session-merged",
            findingId: "f-merged",
            conversationId: nil,
            payload: [
                "session_id": "review-session-merged",
                "finding_id": "f-merged",
                "reason": "fixed_verified",
            ]
        )

        XCTAssertEqual(queued.findingId, "f-merged")
    }
}
