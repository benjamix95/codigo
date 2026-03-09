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
}
