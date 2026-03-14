import XCTest
import MCP
import CoderEngine
@testable import CoderIDEMCPServer

extension CodeReviewHandlerTests {
    func testUnknownToolReturnsNil() {
        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "nonexistent_tool",
            args: [:]
        )
        XCTAssertNil(result)
    }

    func textContent(_ result: MCP.CallTool.Result?) -> String {
        guard let content = result?.content.first else { return "" }
        if case .text(let text) = content {
            return text
        }
        return ""
    }

    func reviewSessionArgs(
        _ snapshot: CodeReviewSessionSnapshot,
        extras: [String: String] = [:]
    ) -> [String: String] {
        var args = extras
        args["session_id"] = snapshot.sessionId
        if let conversationId = snapshot.conversationId?.uuidString.lowercased() {
            args["conversation_id"] = conversationId
        }
        return args
    }

    func seedSnapshot(
        sessionId: String = "session-1",
        conversationId: UUID = UUID(),
        phase: ReviewSessionPhase = .fixing,
        findings: [CodeReviewFinding] = [
            CodeReviewFinding(
                id: "f123",
                severity: .warning,
                category: .correctness,
                origin: .bugHunter,
                filePath: "Package.swift",
                message: "Test finding"
            )
        ]
    ) -> CodeReviewSessionSnapshot {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            phase: phase,
            stage: phase == .completed ? .completed : .fixing,
            findings: findings,
            events: [
                .sessionStarted(scope: "uncommitted changes", fileCount: 1)
            ],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Package.swift"]),
            workspacePath: FileManager.default.currentDirectoryPath,
            currentRound: 1,
            activeWorkerCount: phase == .completed ? 0 : 1,
            startedAt: Date(),
            completedAt: phase == .completed ? Date() : nil,
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )
        MCPSharedState.writeCodeReviewSnapshot(snapshot)
        return snapshot
    }

    func testReviewStatusFallsBackToConversationScopedSessionWhenConversationIdIsOmitted() {
        let snapshot = seedSnapshot(phase: .analyzing)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_status",
            args: [:]
        )

        XCTAssertNil(result?.isError)
        XCTAssertFalse(textContent(result).contains("No active review session."))
        XCTAssertTrue(textContent(result).contains("session_id: \(snapshot.sessionId)"))
    }

    func testReviewFindingsFallsBackToConversationScopedSessionWhenConversationIdIsOmitted() {
        let snapshot = seedSnapshot(phase: .analyzing)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_findings",
            args: [:]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("Findings"))
        XCTAssertFalse(text.contains("No active review session."))
        XCTAssertFalse(text.contains(snapshot.findings[0].message))
        XCTAssertFalse(text.contains(snapshot.findings[0].filePath))
    }

    func testReviewDiffSummaryFallsBackToConversationScopedSessionWhenConversationIdIsOmitted() {
        let snapshot = seedSnapshot(phase: .analyzing)

        let result = CoderIDEMCPServerApp.handleCodeReviewTool(
            name: "review_diff_summary",
            args: [:]
        )

        XCTAssertNil(result?.isError)
        XCTAssertFalse(textContent(result).contains("conversation_id"))
        XCTAssertFalse(textContent(result).contains("No active review session."))
        XCTAssertTrue(
            textContent(result).contains("No diff data available")
                || textContent(result).contains(snapshot.sessionId)
        )
    }
}
