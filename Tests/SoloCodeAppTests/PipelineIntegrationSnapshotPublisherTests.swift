import Combine
import XCTest
@testable import CoderIDE

@MainActor
final class PipelineIntegrationSnapshotPublisherTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testSnapshotPublisherIgnoresOtherConversationUpdates() {
        let service = PipelineIntegrationService()
        let targetConversationId = UUID()
        let otherConversationId = UUID()
        let inverted = expectation(description: "publisher should ignore other conversations")
        inverted.isInverted = true

        service.snapshotDidChangePublisher(for: targetConversationId)
            .sink { inverted.fulfill() }
            .store(in: &cancellables)

        _ = service.updateSnapshotIfNeeded(
            makeSnapshot(jobId: "job-other"),
            for: otherConversationId
        )

        wait(for: [inverted], timeout: 0.15)
    }

    func testSnapshotPublisherEmitsForMatchingConversation() {
        let service = PipelineIntegrationService()
        let conversationId = UUID()
        let emitted = expectation(description: "publisher emits for matching conversation")

        service.snapshotDidChangePublisher(for: conversationId)
            .sink { emitted.fulfill() }
            .store(in: &cancellables)

        _ = service.updateSnapshotIfNeeded(
            makeSnapshot(jobId: "job-match"),
            for: conversationId
        )

        wait(for: [emitted], timeout: 1.0)
    }

    private func makeSnapshot(jobId: String) -> PipelineConversationSnapshot {
        PipelineConversationSnapshot(
            currentJobId: jobId,
            providerId: "provider-test",
            assistantMessageId: UUID(),
            planConversationId: nil,
            jobState: .executing,
            completedTasks: 1,
            totalTasks: 2,
            isRunning: true,
            lastError: nil,
            circuitBreakerActive: false,
            jobStartTime: Date(timeIntervalSince1970: 1)
        )
    }
}
