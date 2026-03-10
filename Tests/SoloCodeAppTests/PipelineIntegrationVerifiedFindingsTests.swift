import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class PipelineIntegrationVerifiedFindingsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsDirectoryPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsDirectoryPath)
        try super.tearDownWithError()
    }

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
        let store = TaskActivityStore(
            persistenceBridge: TaskActivityPersistenceBridge(
                writeCodeReviewSnapshot: { _ in }
            )
        )
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

    func testCodeReviewPayloadBuildsVerifiedFindingsFromSnapshotWithoutPersistenceRead() {
        let store = TaskActivityStore()
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "payload-sync-session",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-sync-1",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/Runtime/Flow.swift",
                    lineNumber: 44,
                    endLineNumber: 44,
                    message: "Duplicate terminal event",
                    status: .open
                )
            ],
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
            verifiedFindings: nil,
            lastUpdatedAt: Date()
        )

        let payload = store.codeReviewPayload(snapshot, conversationId: nil)

        XCTAssertEqual(payload["verified_envelope_source"], "synced_from_snapshot")
        XCTAssertEqual(payload["verified_replay_findings_count"], "1")
        XCTAssertEqual(payload["verified_queue_count"], "1")
        XCTAssertEqual(payload["verified_candidate_queue_count"], "0")
    }

    func testIngestPrefersSnapshotProjection() {
        let conversationId = UUID()
        let sessionId = "ingest-sync-session"
        MCPSharedState.writeVerifiedFindingsEnvelope(
            VerifiedFindingsSessionEnvelope(
                sessionId: sessionId,
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
            )
        )

        let store = TaskActivityStore()
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-ingest-1",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/Runtime/ReviewFlow.swift",
                    lineNumber: 18,
                    endLineNumber: 18,
                    message: "Stale stored envelope must not override snapshot findings.",
                    status: .open
                )
            ],
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
            verifiedFindings: nil,
            lastUpdatedAt: Date()
        )

        store.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)

        let projection = store.verifiedFindingsProjection(for: conversationId)
        XCTAssertEqual(projection.verifiedQueue.map(\.id), ["finding-ingest-1"])
        XCTAssertEqual(projection.candidateQueue.count, 0)
    }

    func testIngestDoesNotSynchronouslyReadPersistedEnvelopeOnColdStart() async {
        let conversationId = UUID()
        let sessionId = "ingest-cold-start-session"
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-cold-start-1",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/Runtime/ColdStart.swift",
                    lineNumber: 12,
                    endLineNumber: 12,
                    message: "Cold-start sync should preserve persisted metadata.",
                    status: .open
                )
            ],
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
            verifiedFindings: nil,
            lastUpdatedAt: Date()
        )
        let persisted = VerifiedFindingsSessionSyncService.sync(snapshot: snapshot)
        let persistedCanonical = persisted.canonicalSnapshot
        let persistedCommand = await CommandDeduplicationService().record(
            meta: VerifiedCommandMeta(
                commandId: "cmd-cold-start",
                entityId: "finding-cold-start-1",
                issuedBy: "tests",
                issuedFrom: .reviewChat,
                issuedAt: Date(timeIntervalSince1970: 1_700_000_010),
                requestFingerprint: "fingerprint-cold-start"
            ),
            resultSummary: "persisted-command",
            recordedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        MCPSharedState.writeVerifiedFindingsEnvelope(
            VerifiedFindingsSessionEnvelope(
                sessionId: sessionId,
                canonicalSnapshot: VerifiedFindingsCanonicalSnapshot(
                    runs: persistedCanonical.runs,
                    findings: persistedCanonical.findings,
                    evidences: persistedCanonical.evidences,
                    verificationReports: persistedCanonical.verificationReports,
                    patchArtifacts: persistedCanonical.patchArtifacts,
                    revalidationReports: persistedCanonical.revalidationReports,
                    commandLog: [persistedCommand],
                    eventLog: persistedCanonical.eventLog,
                    traceLog: persistedCanonical.traceLog
                ),
                projectionSnapshot: persisted.projectionSnapshot
            )
        )

        let store = TaskActivityStore(
            persistenceBridge: TaskActivityPersistenceBridge(
                writeCodeReviewSnapshot: { _ in }
            )
        )
        store.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)

        let storedSnapshot = store.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )
        XCTAssertEqual(
            storedSnapshot?.verifiedFindings?.canonicalSnapshot.commandLog,
            []
        )
        XCTAssertEqual(
            store.verifiedFindingsEnvelopesBySession[sessionId]?.canonicalSnapshot.commandLog,
            []
        )
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
