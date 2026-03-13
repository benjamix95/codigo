import CoderEngine
import Foundation

struct ReviewPanelReviewTaskResult {
    let snapshot: CodeReviewSessionSnapshot
    let error: String?
    let wasCancelled: Bool
}

struct ReviewPanelChatTaskResult {
    let error: String?
    let wasCancelled: Bool
}

/// Lightweight coordinator that owns running review and chat Tasks.
/// All state flows back through `CodeReviewSessionState.onStateChange`.
@MainActor
final class ReviewPanelCoordinator {

    // MARK: - Task State

    private(set) var reviewTask: Task<Void, Never>?
    private(set) var chatTask: Task<Void, Never>?
    private(set) var isReviewRunning: Bool = false

    // MARK: - Review Execution

    /// Runs a code review using the multi-swarm provider.
    /// Replicates the pattern from `CodigoApp.launchDeferredReviewCommand`.
    func runReview(
        provider: any LLMProvider,
        prompt: String,
        context: WorkspaceContext,
        sessionState: CodeReviewSessionState,
        onEvent: @escaping @MainActor (StreamEvent) -> Void,
        onStart: @escaping @MainActor () -> Void,
        onFinish: @escaping @MainActor (ReviewPanelReviewTaskResult) -> Void
    ) {
        cancelReview()
        isReviewRunning = true

        reviewTask = Task { @MainActor in
            onStart()
            var streamError: String?
            do {
                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    imageURLs: nil
                )
                for try await event in stream {
                    if Task.isCancelled { break }
                    onEvent(event)
                }
            } catch {
                if !Task.isCancelled {
                    await sessionState.fail(error: error.localizedDescription)
                    streamError = error.localizedDescription
                }
            }
            let snapshot = await sessionState.snapshot()
            isReviewRunning = false
            onFinish(
                ReviewPanelReviewTaskResult(
                    snapshot: snapshot,
                    error: streamError,
                    wasCancelled: Task.isCancelled
                )
            )
        }
    }

    func cancelReview() {
        reviewTask?.cancel()
        reviewTask = nil
        isReviewRunning = false
    }

    // MARK: - Chat Stream

    /// Runs a lightweight chat stream for the panel's independent chat.
    func runChatStream(
        provider: any LLMProvider,
        prompt: String,
        context: WorkspaceContext,
        onEvent: @escaping @MainActor (StreamEvent) -> Void,
        onFinish: @escaping @MainActor (ReviewPanelChatTaskResult) -> Void
    ) {
        cancelChat()

        chatTask = Task { @MainActor in
            var streamError: String?
            do {
                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    imageURLs: nil
                )
                for try await event in stream {
                    if Task.isCancelled { break }
                    onEvent(event)
                }
            } catch {
                if !Task.isCancelled {
                    streamError = error.localizedDescription
                }
            }
            onFinish(
                ReviewPanelChatTaskResult(
                    error: streamError,
                    wasCancelled: Task.isCancelled
                )
            )
        }
    }

    func cancelChat() {
        chatTask?.cancel()
        chatTask = nil
    }
}
