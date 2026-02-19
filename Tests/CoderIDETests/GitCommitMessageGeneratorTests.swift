import XCTest
import CoderEngine
@testable import CoderIDE

private struct MockProvider: LLMProvider {
    let id: String = "mock"
    let displayName: String = "Mock"
    let response: String
    func isAuthenticated() -> Bool { true }
    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(response))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

final class GitCommitMessageGeneratorTests: XCTestCase {
    func testGenerateCommitMessageUsesFirstLineAndTruncates() async throws {
        let generator = GitCommitMessageGenerator()
        let long = "feat: this is a very long commit subject that should be trimmed because it exceeds the seventy two chars limit\nsecond line"
        let provider = MockProvider(response: long)
        let ctx = WorkspaceContext(workspacePath: URL(fileURLWithPath: "/tmp"))
        let msg = try await generator.generateCommitMessage(diff: "diff --git", provider: provider, context: ctx)
        XCTAssertFalse(msg.isEmpty)
        XCTAssertLessThanOrEqual(msg.count, 72)
        XCTAssertFalse(msg.contains("\n"))
    }

    func testFallbackMessage() {
        let generator = GitCommitMessageGenerator()
        let status = GitStatusSummary(changedFiles: 2, added: 0, removed: 0, modified: 2, untracked: 0, aheadBehind: nil, hasRemote: true)
        XCTAssertEqual(generator.fallbackMessage(from: status), "chore: update project files")
    }
}
