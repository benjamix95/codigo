import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class PipelineIntegrationVerifiedFindingsTests: XCTestCase {
    func testReviewFindingCreatesInlineVerifiedFindingsSessionForConversation() {
        let suiteName = "PipelineIntegrationVerifiedFindingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let chatStore = ChatStore(userDefaults: defaults)
        let todoStore = TodoStore(
            storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)",
            userDefaults: defaults
        )
        let taskActivityStore = TaskActivityStore()
        let swarmProgressStore = SwarmProgressStore()
        let executionController = ExecutionController()
        let service = PipelineIntegrationService()
        service.configure(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            executionController: executionController
        )

        let conversationId = chatStore.conversations[0].id
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )

        service.handleEvent(
            .reviewFinding(
                ReviewFindingPayload(
                    jobId: "job-main-security",
                    taskId: "security-audit",
                    finding: ReviewFinding(
                        findingId: "finding-inline-1",
                        file: "Sources/Auth.swift",
                        line: 44,
                        severity: .critical,
                        status: .open,
                        message: "Security: missing authz check"
                    )
                )
            ),
            for: conversationId
        )

        let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: "inline-review-\(conversationId.uuidString.lowercased())",
            conversationId: conversationId
        )
        XCTAssertEqual(snapshot?.findings.count, 1)
        XCTAssertEqual(snapshot?.verifiedFindings?.projectionSnapshot.verifiedQueue.count, 1)
        XCTAssertEqual(
            snapshot?.verifiedFindings?.canonicalSnapshot.findings["finding-inline-1"]?.domain,
            .security
        )
    }

    func testCodeReviewPayloadIncludesVerifiedFindingsFacadeFields() {
        let store = TaskActivityStore()
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "payload-session",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            verifiedFindings: VerifiedFindingsSessionEnvelope(
                sessionId: "payload-session",
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

        let payload = store.codeReviewPayload(snapshot, conversationId: nil)

        XCTAssertEqual(payload["verified_envelope_source"], "embedded_snapshot")
        XCTAssertEqual(payload["verified_replay_candidate_count"], "0")
        XCTAssertEqual(payload["verified_replay_findings_count"], "0")
        XCTAssertEqual(payload["verified_security_gate_ready"], "true")
    }

    func testReviewFindingBuildsStructuredChatArtifactPayloadFromSharedSnapshot() {
        let suiteName = "PipelineIntegrationVerifiedFindingsCardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let chatStore = ChatStore(userDefaults: defaults)
        let todoStore = TodoStore(
            storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)",
            userDefaults: defaults
        )
        let taskActivityStore = TaskActivityStore()
        let swarmProgressStore = SwarmProgressStore()
        let executionController = ExecutionController()
        let service = PipelineIntegrationService()
        service.configure(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            executionController: executionController
        )

        let conversationId = chatStore.conversations[0].id
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )

        let payload = ReviewFindingPayload(
            jobId: "job-main-bug",
            taskId: "bug-hunt",
            finding: ReviewFinding(
                findingId: "finding-inline-card",
                file: "Sources/Runtime/Flow.swift",
                line: 88,
                severity: .warning,
                status: .open,
                message: "BugHunter: stale state can emit duplicate terminal events.",
                suggestedFix: "Guard terminal emission with a single-owner state check."
            )
        )
        service.handleEvent(.reviewFinding(payload), for: conversationId)

        let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: "inline-review-\(conversationId.uuidString.lowercased())",
            conversationId: conversationId
        )
        let artifact = snapshot.map {
            VerifiedFindingsChatPresentationService.mainChatArtifactPayload(
                payload: payload,
                snapshot: $0
            )
        }

        XCTAssertEqual(artifact?["title"], "WARNING bug · Flow.swift")
        XCTAssertTrue(artifact?["detail"]?.contains("#### Summary") == true)
        XCTAssertTrue(artifact?["detail"]?.contains("Patch non ancora preparata") == true)
        XCTAssertTrue(artifact?["detail"]?.contains("duplicate terminal events") == true)
    }
}
