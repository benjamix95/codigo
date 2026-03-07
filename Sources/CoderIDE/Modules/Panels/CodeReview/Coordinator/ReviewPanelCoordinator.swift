import CoderEngine
import Foundation

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
        onComplete: @escaping @MainActor (CodeReviewSessionSnapshot) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        cancelReview()
        isReviewRunning = true

        reviewTask = Task { @MainActor in
            onStart()
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

                let snapshot = await sessionState.snapshot()
                isReviewRunning = false

                if snapshot.phase == .completed {
                    onComplete(snapshot)
                } else if Task.isCancelled {
                    onError("Review cancelled")
                } else {
                    let msg = snapshot.lastError
                        ?? "Review did not complete (phase: \(snapshot.phase.rawValue))"
                    onError(msg)
                }
            } catch {
                isReviewRunning = false
                if !Task.isCancelled {
                    await sessionState.fail(error: error.localizedDescription)
                    onError(error.localizedDescription)
                }
            }
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
        onToken: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        cancelChat()

        chatTask = Task { @MainActor in
            do {
                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    imageURLs: nil
                )
                var accumulated = ""
                for try await event in stream {
                    if Task.isCancelled { break }
                    if case .textDelta(let text) = event {
                        accumulated += text
                        onToken(accumulated)
                    }
                }
                if !Task.isCancelled {
                    onComplete()
                }
            } catch {
                if !Task.isCancelled {
                    onError(error.localizedDescription)
                }
            }
        }
    }

    func cancelChat() {
        chatTask?.cancel()
        chatTask = nil
    }
}
