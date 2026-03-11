import XCTest
import CoderEngine
@testable import CoderIDE

actor ReviewProviderGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var completed = false

    func wait() async {
        if completed { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func finishSuccessfully() {
        completed = true
        let current = continuations
        continuations.removeAll()
        current.forEach { $0.resume() }
    }
}

final class DeferredCodeReviewProvider: LLMProvider, @unchecked Sendable {
    let id = "deferred-code-review-provider"
    let displayName = "DeferredCodeReviewProvider"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    private let sessionState: CodeReviewSessionState?
    private let gate: ReviewProviderGate
    private let scopeFiles: [String]

    init(
        sessionState: CodeReviewSessionState?,
        gate: ReviewProviderGate,
        scopeFiles: [String]
    ) {
        self.sessionState = sessionState
        self.gate = gate
        self.scopeFiles = scopeFiles
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let sessionState = self.sessionState
        let gate = self.gate
        let scopeFiles = self.scopeFiles
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                if let sessionState {
                    await sessionState.start(
                        scope: ReviewSessionScope(type: .uncommitted, files: scopeFiles),
                        workspacePath: context.workspacePath.path
                    )
                }
                await gate.wait()
                if let sessionState {
                    await sessionState.complete()
                }
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }
}

final class ValidationOnlyProvider: LLMProvider, @unchecked Sendable {
    let id = "validation-only-provider"
    let displayName = "ValidationOnlyProvider"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

final class FailingDeferredCodeReviewProvider: LLMProvider, @unchecked Sendable {
    let id = "failing-deferred-code-review-provider"
    let displayName = "FailingDeferredCodeReviewProvider"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    private let sessionState: CodeReviewSessionState?
    private let scopeFiles: [String]
    private let failureMessage: String

    init(
        sessionState: CodeReviewSessionState?,
        scopeFiles: [String],
        failureMessage: String = "Synthetic review failure"
    ) {
        self.sessionState = sessionState
        self.scopeFiles = scopeFiles
        self.failureMessage = failureMessage
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let sessionState = self.sessionState
        let scopeFiles = self.scopeFiles
        let failureMessage = self.failureMessage
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                if let sessionState {
                    await sessionState.start(
                        scope: ReviewSessionScope(type: .uncommitted, files: scopeFiles),
                        workspacePath: context.workspacePath.path
                    )
                    await sessionState.fail(error: failureMessage)
                }
                continuation.finish()
            }
        }
    }
}
