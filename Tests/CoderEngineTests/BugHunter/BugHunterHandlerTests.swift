import XCTest
import MCP
import CoderEngine
@testable import CoderIDEMCPServer

final class BugHunterHandlerTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try super.tearDownWithError()
    }

    func testBugHunterCancelRunQueuesCommand() {
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: "run-1",
                reviewSessionId: "review-1",
                sourceKind: .uncommitted,
                triggerKind: .manual,
                gitRoot: "/tmp/repo",
                status: .running
            )
        )

        let result = CoderIDEMCPServerApp.handleBugHunterTool(
            name: "bughunter_cancel_run",
            args: ["run_id": "run-1"]
        )

        XCTAssertNil(result?.isError)
        XCTAssertTrue(textContent(result).contains("queued"))
    }

    func testBugHunterStatusIncludesVerifiedFindingsCounters() {
        let reviewSnapshot = CodeReviewSessionSnapshot(
            sessionId: "review-1",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [],
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
            currentJobId: "job-1",
            lastTestStatus: .passed,
            verifiedFindings: VerifiedFindingsSessionEnvelope(
                sessionId: "review-1",
                canonicalSnapshot: VerifiedFindingsCanonicalSnapshot(
                    runs: [:],
                    findings: [:],
                    evidences: [:],
                    verificationReports: [:],
                    patchArtifacts: [:],
                    revalidationReports: [:],
                    commandLog: [],
                    eventLog: [],
                    traceLog: []
                ),
                projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                    candidateQueue: [],
                    verifiedQueue: [],
                    duplicatesCount: 0,
                    staleCandidatesCount: 0,
                    traceSnippets: []
                )
            ),
            lastUpdatedAt: Date()
        )
        MCPSharedState.writeCodeReviewSnapshot(reviewSnapshot)
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: "run-1",
                reviewSessionId: "review-1",
                sourceKind: .uncommitted,
                triggerKind: .manual,
                gitRoot: "/tmp/repo",
                status: .running,
                verifiedFindingsCount: 3,
                candidateFindingsCount: 2,
                lastRevalidationVerdict: "fixed_verified",
                securityGateReady: true
            )
        )

        let result = CoderIDEMCPServerApp.handleBugHunterTool(
            name: "bughunter_status",
            args: ["run_id": "run-1"]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("verified_findings_count: 3"))
        XCTAssertTrue(text.contains("candidate_findings_count: 2"))
        XCTAssertTrue(text.contains("last_revalidation_verdict: fixed_verified"))
        XCTAssertTrue(text.contains("security_gate_ready_cached: true"))
        XCTAssertTrue(text.contains("verified_envelope_source: embedded_snapshot"))
        XCTAssertTrue(text.contains("verified_replay_findings: 0"))
    }

    private func textContent(_ result: MCP.CallTool.Result?) -> String {
        guard let content = result?.content.first else { return "" }
        if case .text(let text) = content {
            return text
        }
        return ""
    }
}
