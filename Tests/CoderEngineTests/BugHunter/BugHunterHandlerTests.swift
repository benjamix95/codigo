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

    func testBugHunterExplainClusterUsesVerifiedFindingsCanonicalSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_002_000)
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [
                "bug-1": VerifiedFinding(
                    id: "bug-1",
                    domain: .bug,
                    title: "Crash in loader. path A",
                    summary: "bug",
                    category: "correctness",
                    severity: .high,
                    confidence: 0.96,
                    status: .verified,
                    filePath: "Sources/Loader.swift",
                    originEntryPoint: .mcp,
                    findingFingerprint: "bug-1",
                    createdAt: now,
                    updatedAt: now
                ),
                "bug-2": VerifiedFinding(
                    id: "bug-2",
                    domain: .bug,
                    title: "Crash in loader. path B",
                    summary: "bug",
                    category: "correctness",
                    severity: .medium,
                    confidence: 0.90,
                    status: .verified,
                    filePath: "Sources/Loader.swift",
                    originEntryPoint: .mcp,
                    findingFingerprint: "bug-2",
                    createdAt: now,
                    updatedAt: now
                ),
                "security-1": VerifiedFinding(
                    id: "security-1",
                    domain: .security,
                    title: "Auth bypass",
                    summary: "security",
                    category: "security",
                    severity: .critical,
                    confidence: 0.99,
                    status: .verified,
                    filePath: "Sources/Auth.swift",
                    originEntryPoint: .mcp,
                    findingFingerprint: "security-1",
                    createdAt: now,
                    updatedAt: now
                ),
            ],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: []
        )
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
            startedAt: now,
            completedAt: now,
            analysisCompletedAt: now,
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: .passed,
            verifiedFindings: VerifiedFindingsSessionEnvelope(
                sessionId: "review-1",
                canonicalSnapshot: canonical,
                projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
                lastUpdatedAt: now
            ),
            lastUpdatedAt: now
        )
        MCPSharedState.writeCodeReviewSnapshot(reviewSnapshot)
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: "run-1",
                reviewSessionId: "review-1",
                sourceKind: .uncommitted,
                triggerKind: .manual,
                gitRoot: "/tmp/repo",
                status: .completed
            )
        )

        let result = CoderIDEMCPServerApp.handleBugHunterTool(
            name: "bughunter_explain_cluster",
            args: ["run_id": "run-1"]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("cluster_title: Crash in loader"))
        XCTAssertTrue(text.contains("cluster_size: 2"))
        XCTAssertTrue(text.contains("primary_risk: correctness"))
        XCTAssertFalse(text.contains("Auth bypass"))
    }

    func testBugHunterFindingsUsesCanonicalQueryService() {
        let now = Date(timeIntervalSince1970: 1_700_002_100)
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [
                "bughunter-1": VerifiedFinding(
                    id: "bughunter-1",
                    domain: .bug,
                    title: "Crash path",
                    summary: "bug",
                    category: "correctness",
                    severity: .high,
                    confidence: 0.94,
                    status: .verified,
                    filePath: "Sources/App.swift",
                    lineStart: 44,
                    originEntryPoint: .mcp,
                    sourceOrigin: "bugHunter",
                    findingFingerprint: "bughunter-1",
                    createdAt: now,
                    updatedAt: now
                ),
            ],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: []
        )
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
            startedAt: now,
            completedAt: now,
            analysisCompletedAt: now,
            lastError: nil,
            currentJobId: "job-1",
            lastTestStatus: .passed,
            verifiedFindings: VerifiedFindingsSessionEnvelope(
                sessionId: "review-1",
                canonicalSnapshot: canonical,
                projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
                lastUpdatedAt: now
            ),
            lastUpdatedAt: now
        )
        MCPSharedState.writeCodeReviewSnapshot(reviewSnapshot)
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: "run-1",
                reviewSessionId: "review-1",
                sourceKind: .uncommitted,
                triggerKind: .manual,
                gitRoot: "/tmp/repo",
                status: .completed
            )
        )

        let result = CoderIDEMCPServerApp.handleBugHunterTool(
            name: "bughunter_findings",
            args: ["run_id": "run-1"]
        )

        XCTAssertNil(result?.isError)
        let text = textContent(result)
        XCTAssertTrue(text.contains("bughunter-1"))
        XCTAssertTrue(text.contains("domain: bug"))
    }

    private func textContent(_ result: MCP.CallTool.Result?) -> String {
        guard let content = result?.content.first else { return "" }
        if case .text(let text) = content {
            return text
        }
        return ""
    }
}
