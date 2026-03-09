import XCTest
import MCP
@testable import CoderEngine
@testable import CoderIDEMCPServer

final class SecurityHandlerTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try super.tearDownWithError()
    }

    func testSecurityFindingsFiltersSecurityOrigin() {
        let snapshot = makeSecuritySnapshot()
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleSecurityTool(
            name: "security_findings",
            args: [
                "session_id": snapshot.sessionId,
                "conversation_id": snapshot.conversationId!.uuidString.lowercased(),
            ]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("security-1"))
        XCTAssertFalse(text.contains("bug-1"))
    }

    func testSecurityVerifyFindingQueuesSharedWorkflowCommand() {
        let snapshot = makeSecuritySnapshot()
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleSecurityTool(
            name: "security_verify_finding",
            args: [
                "session_id": snapshot.sessionId,
                "conversation_id": snapshot.conversationId!.uuidString.lowercased(),
                "finding_id": "security-1",
            ]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("action=verify_finding"))
        XCTAssertTrue(text.contains("session_id=\(snapshot.sessionId)"))
    }

    func testSecurityCloseFindingQueuesSharedWorkflowCommand() {
        let snapshot = makeSecuritySnapshot()
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let result = CoderIDEMCPServerApp.handleSecurityTool(
            name: "security_close_finding",
            args: [
                "session_id": snapshot.sessionId,
                "conversation_id": snapshot.conversationId!.uuidString.lowercased(),
                "finding_id": "security-1",
                "reason": "fixed_verified",
            ]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("action=close_finding"))
        XCTAssertTrue(text.contains("session_id=\(snapshot.sessionId)"))
    }

    private func makeSecuritySnapshot() -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: "security-session-1",
            conversationId: UUID(),
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "security-1",
                    severity: .critical,
                    category: .security,
                    origin: .securityAuditor,
                    filePath: "Sources/Auth.swift",
                    message: "Missing authz check"
                ),
                CodeReviewFinding(
                    id: "bug-1",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/App.swift",
                    message: "Crash path"
                ),
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
    }

    func textContent(_ result: MCP.CallTool.Result?) -> String {
        guard let content = result?.content.first else { return "" }
        if case .text(let text) = content {
            return text
        }
        return ""
    }
}
